// src/routes.jobs.js

const { reviewOverall } = require("./utils/reviewLogic");
const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { haversineDistance, kmToMiles, milesToKm } = require("./utils/haversine");
const { geocodeLocation }  = require("./utils/geocode");
const { buildJobData, validateJobBody, checkDraftAccess } = require("./utils/jobData");
const { isBlockedBetween } = require("./utils/safety");
const { normalizeCancellationReason } = require("./utils/applicationStatus");
const { companyJobsWhere, countCompletedJobs } = require("./utils/companyStats");

const router = express.Router();

// Pausierte Arbeitgeber: ihre Jobs sind fuer Worker unsichtbar und nicht bewerbbar
// Mit userId zusaetzlich: Arbeitgeber, die mit diesem User einen Block haben (beide Richtungen).
// Bewusst nur im Feed (GET /jobs, /jobs/nearby) ausgeblendet; Direktaufrufe (Job-Detail, Firmenprofil,
// Gespeichert, Deep Link) bleiben sichtbar – Bewerben ist dort per BLOCKED-Check in POST /:id/apply gesperrt.
async function pausedEmployerFilter(userId) {
  const paused = await prisma.user.findMany({
    where: { pausedAt: { not: null }, role: "employer" },
    select: { id: true },
  });
  const hiddenIds = paused.map((u) => u.id);
  if (userId) {
    const blocks = await prisma.userBlock.findMany({
      where: { OR: [{ blockerId: userId }, { blockedId: userId }] },
      select: { blockerId: true, blockedId: true },
    });
    for (const b of blocks) hiddenIds.push(b.blockerId === userId ? b.blockedId : b.blockerId);
  }
  if (!hiddenIds.length) return {};
  // OR noetig: NOT IN wuerde Jobs ohne employerId (Seed-Daten) mit ausschliessen
  return { OR: [{ employerId: null }, { employerId: { notIn: hiddenIds } }] };
}

// ─────────────────────────────────────────────
// Helper: JobIDs die der User bereits applied/skipped hat (aus PostgreSQL)
// ─────────────────────────────────────────────
async function getSeenJobIds(userId) {
  const [applies, skips] = await Promise.all([
    prisma.apply.findMany({ where: { userId }, select: { jobId: true } }),
    prisma.skip.findMany({ where: { userId }, select: { jobId: true } }),
  ]);
  return {
    appliedIds: new Set(applies.map((a) => a.jobId)),
    skippedIds: new Set(skips.map((s) => s.jobId)),
  };
}

// ─────────────────────────────────────────────
// Helper: Enriches job list with employer review breakdowns + match reasons
// ─────────────────────────────────────────────
async function enrichJobsWithRatings(jobs, userId) {
  if (!jobs.length) return jobs;

  const employerIds = [...new Set(jobs.map((j) => j.employerId).filter(Boolean))];

  const [reviews, workerProfile] = await Promise.all([
    prisma.workerReview.findMany({
      where: { employerId: { in: employerIds } },
      select: {
        employerId: true,
        communication: true, paymentFairness: true,
        workEnvironment: true, jobDescriptionAccuracy: true,
        overallExperience: true,
      },
    }),
    prisma.worker.findUnique({
      where: { userId },
      select: { preferredCategories: true, payRangeMin: true, payRangeMax: true, maxTravelDistance: true },
    }).catch(() => null),
  ]);

  // Group reviews by employerId
  const byEmployer = {};
  for (const r of reviews) {
    if (!byEmployer[r.employerId]) byEmployer[r.employerId] = [];
    byEmployer[r.employerId].push(r);
  }

  // Compute breakdown per employer
  const breakdownMap = {};
  for (const [empId, revs] of Object.entries(byEmployer)) {
    const avg = (field) => revs.reduce((s, r) => s + r[field], 0) / revs.length;
    const comm = avg("communication");
    const pay  = avg("paymentFairness");
    const env  = avg("workEnvironment");
    const desc = avg("jobDescriptionAccuracy");
    const over = avg("overallExperience");
    const totalAvg = (comm + pay + env + desc + over) / 5;

    const tags = [];
    if (env  >= 4.0) tags.push("Friendly Team");
    if (pay  >= 4.0) tags.push("Fair Pay");
    if (comm >= 4.0) tags.push("Good Communication");
    if (over >= 4.2) tags.push("Great Experience");
    if (desc >= 4.0) tags.push("Clear Job Description");

    breakdownMap[empId] = {
      avgRating: Math.round(totalAvg * 10) / 10,
      totalReviews: revs.length,
      communication: Math.round(comm * 10) / 10,
      paymentFairness: Math.round(pay * 10) / 10,
      workEnvironment: Math.round(env * 10) / 10,
      jobDescriptionAccuracy: Math.round(desc * 10) / 10,
      overallExperience: Math.round(over * 10) / 10,
      tags: tags.slice(0, 3),
    };
  }

  return jobs.map((job) => {
    const bd = job.employerId ? breakdownMap[job.employerId] : null;

    // Match reasons based on user preferences
    const matchReasons = [];
    if (workerProfile) {
      const cats = workerProfile.preferredCategories ?? [];
      if (job.category && cats.includes(job.category)) matchReasons.push("Matches your category preference");
      if (workerProfile.payRangeMin != null && job.payAmount >= workerProfile.payRangeMin) matchReasons.push("Matches your pay expectations");
      if (workerProfile.payRangeMax != null && job.payAmount <= workerProfile.payRangeMax) {/* already counted above */}
    }
    const now = new Date();
    if (job.startTime && new Date(job.startTime) - now <= 24 * 3600 * 1000) matchReasons.push("Starting soon — act fast!");
    if ((job.openSpots ?? 0) <= 2) matchReasons.push("Only a few spots left");

    return { ...job, reviewBreakdown: bd, matchReasons };
  });
}

// ─────────────────────────────────────────────
// GET /jobs?type=quickMoney|startingSoon|popular|recommended
//          &category=Events|Hospitality|...
//
// Gesehene Jobs (applied/skipped) werden NUR gefiltert wenn kein type angegeben
// (= Swipe-Feed). Dashboard-Sektionen und alle anderen Bereiche zeigen immer alle Jobs.
// ─────────────────────────────────────────────
router.get("/", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const { type, category } = req.query;
    console.log(`GET /jobs — type=${type ?? "swipe"}, category=${category ?? "all"}`);

    // Nur für den Swipe-Feed (kein type) werden gesehene Jobs ausgeblendet
    const isSwipeFeed = !type;
    let seenIds = [];
    if (isSwipeFeed) {
      const { appliedIds, skippedIds } = await getSeenJobIds(userId);
      seenIds = [...appliedIds, ...skippedIds];
    }

    const baseWhere = {
      ...(await pausedEmployerFilter(userId)),
      status: "published",
      ...(seenIds.length > 0 && { id: { notIn: seenIds } }),
      ...(category && { category: { equals: category, mode: "insensitive" } }),
    };

    const now = new Date();

    let jobs;
    if (type === "quickMoney") {
      const cutoff = new Date(now.getTime() + 4 * 3_600_000);
      jobs = await prisma.job.findMany({
        where: {
          ...baseWhere,
          payAmount: { gte: 15 },
          startTime: { gte: now, lte: cutoff },
        },
        orderBy: { payAmount: "desc" },
      });

    } else if (type === "startingSoon") {
      const cutoff = new Date(now.getTime() + 48 * 3_600_000);
      jobs = await prisma.job.findMany({
        where: {
          ...baseWhere,
          startTime: { gte: now, lte: cutoff },
        },
        orderBy: { startTime: "asc" },
      });

    } else if (type === "popular") {
      jobs = await prisma.job.findMany({
        where: baseWhere,
        orderBy: { applies: { _count: "desc" } },
      });

    } else if (type === "recommended") {
      const worker = await prisma.worker.findUnique({
        where: { userId },
        select: { preferredCategories: true },
      });
      const preferred = worker?.preferredCategories ?? [];
      const allJobs = await prisma.job.findMany({
        where: baseWhere,
        orderBy: { payAmount: "desc" },
      });
      // Category matches first, then remaining — both groups sorted by payAmount already
      const matched   = allJobs.filter(j => preferred.length > 0 && preferred.includes(j.category));
      const unmatched = allJobs.filter(j => !matched.some(m => m.id === j.id));
      jobs = [...matched, ...unmatched];

    } else {
      jobs = await prisma.job.findMany({
        where: baseWhere,
        orderBy: { createdAt: "desc" },
      });
    }

    const enriched = await enrichJobsWithRatings(jobs, userId);
    return res.json({ jobs: enriched });
  } catch (err) {
    console.error("GET /jobs error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /jobs/nearby?lat=48.77&lng=9.18&radius=100[&unit=mi]
// radius ist standardmaessig in km (abwaertskompatibel); mit unit=mi in Meilen (so ruft die iOS-App auf).
// Angezeigt wird immer in Meilen (distanceText "x.x mi away", distanceMiles); distanceKm bleibt fuer Sortierung/Kompatibilitaet.
// ─────────────────────────────────────────────
router.get("/nearby", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const lat    = parseFloat(req.query.lat);
    const lng    = parseFloat(req.query.lng);
    const radiusUnit = req.query.unit === "mi" ? "mi" : "km";
    const rawRadius = parseFloat(req.query.radius);
    const maxRadius = 500; // sinnvolle Obergrenze in der gewaehlten Einheit
    const radius = rawRadius > 0 && rawRadius <= maxRadius ? rawRadius : (radiusUnit === "mi" ? 60 : 100);
    const radiusKm = radiusUnit === "mi" ? milesToKm(radius) : radius;

    if (isNaN(lat) || isNaN(lng)) {
      return res.status(400).json({ error: "Missing or invalid lat/lng query params." });
    }

    // Radar zeigt immer alle Jobs — unabhängig von apply/skip
    const allJobs = await prisma.job.findMany({
      where: {
        ...(await pausedEmployerFilter(userId)),
        status: "published",
        lat: { not: null },
        lng: { not: null },
      },
    });

    const nearbyJobs = allJobs
      .map((job) => {
        const rawKm = haversineDistance(lat, lng, job.lat, job.lng);
        const distanceMiles = Math.round(kmToMiles(rawKm) * 10) / 10;
        // _rawKm (ungerundet) nur fuer Filter/Sortierung; gerundete Werte nur zur Anzeige
        return { ...job, _rawKm: rawKm, distanceKm: Math.round(rawKm * 10) / 10, distanceMiles, distanceText: `${distanceMiles} mi away` };
      })
      .filter((job) => job._rawKm <= radiusKm)
      .sort((a, b) => a._rawKm - b._rawKm)
      .map(({ _rawKm, ...job }) => job);

    console.log(`Found ${nearbyJobs.length} jobs within ${radius}${radiusUnit} of (${lat}, ${lng})`);

    const enrichedNearby = await enrichJobsWithRatings(nearbyJobs, userId);
    return res.json({
      jobs: enrichedNearby,
      meta: { lat, lng, radius, unit: radiusUnit, total: nearbyJobs.length },
    });
  } catch (err) {
    console.error("GET /jobs/nearby error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /jobs — Job erstellen (Arbeitgeber)
// ─────────────────────────────────────────────
router.post("/", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const { title, category, location } = req.body;
    const status = req.body.status ?? "published";

    if (!title || !category) {
      return res.status(400).json({ error: "title and category are required." });
    }

    const invalid = validateJobBody(req.body);
    if (invalid) return res.status(400).json({ error: invalid });

    const data = buildJobData(req.body);

    // Koordinaten: direkt aus dem Request nutzen (vom iOS Location-Picker),
    // sonst Geocoding als Fallback (z.B. bei API-Calls ohne Picker)
    if (data.lat == null && location) {
      const coords = await geocodeLocation(location);
      if (coords) {
        data.lat = coords.lat;
        data.lng = coords.lng;
        console.log(`geocode fallback: "${location}" → lat=${data.lat}, lng=${data.lng}`);
      } else {
        console.warn(`geocode: Keine Koordinaten für "${location}" — Job wird ohne lat/lng gespeichert`);
      }
    } else if (data.lat != null) {
      console.log(`geocode: lat/lng vom Client übernommen (${data.lat}, ${data.lng})`);
    }

    const newJob = await prisma.job.create({
      data: { ...data, status, employerId: req.auth.sub },
    });

    console.log(`POST /jobs — neuer Job: "${title}" (${status}), ID: ${newJob.id}`);
    return res.status(201).json({ job: newJob });
  } catch (err) {
    console.error("POST /jobs error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /jobs/:id/apply
// ─────────────────────────────────────────────
router.post("/:id/apply", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const jobId  = req.params.id;

    const job = await prisma.job.findUnique({
      where: { id: jobId },
      select: { id: true, title: true, employerId: true, status: true, openSpots: true, startTime: true, endTime: true },
    });
    if (!job) return res.status(404).json({ error: "Job not found" });

    // Pausiertes Worker-Konto: keine Bewerbungen (Einstellungen → Privacy & Data)
    const applicant = await prisma.user.findUnique({ where: { id: userId }, select: { pausedAt: true } });
    if (applicant?.pausedAt) {
      return res.status(403).json({ error: "ACCOUNT_PAUSED", message: "Your account is paused. Resume it in Settings to apply." });
    }

    // Job muss published sein — und der Arbeitgeber darf nicht pausiert sein
    let employerPaused = false;
    if (job.employerId) {
      const employer = await prisma.user.findUnique({ where: { id: job.employerId }, select: { pausedAt: true } });
      employerPaused = !!employer?.pausedAt;
    }
    if (job.status !== "published" || employerPaused) {
      return res.status(400).json({ error: "JOB_UNAVAILABLE" });
    }

    // Block zwischen Worker und Arbeitgeber (beide Richtungen) → Bewerbung abgelehnt
    if (job.employerId) {
      const blocks = await prisma.userBlock.findMany({
        where: { OR: [
          { blockerId: userId, blockedId: job.employerId },
          { blockerId: job.employerId, blockedId: userId },
        ] },
        select: { blockerId: true, blockedId: true },
      });
      if (isBlockedBetween(blocks, userId, job.employerId)) {
        return res.status(403).json({ error: "You can't apply to this employer.", code: "BLOCKED" });
      }
    }

    // Keine offenen Stellen mehr
    if (job.openSpots != null && job.openSpots <= 0) {
      return res.status(409).json({ error: "SHIFT_TAKEN" });
    }

    // Scheduling-Konflikt: Worker hat bereits einen angenommenen Job zur gleichen Zeit
    if (job.startTime && job.endTime) {
      const conflict = await prisma.apply.findFirst({
        where: {
          userId,
          status: "accepted",
          job: {
            startTime: { lt: job.endTime },
            endTime:   { gt: job.startTime },
          },
        },
      });
      if (conflict) return res.status(409).json({ error: "SCHEDULING_CONFLICT" });
    }

    // Apply + Conversation in einer Transaktion
    const result = await prisma.$transaction(async (tx) => {
      const apply = await tx.apply.upsert({
        where:  { userId_jobId: { userId, jobId } },
        create: { userId, jobId },
        update: {},
      });

      // Conversation nur anlegen wenn noch keine existiert
      const existing = await tx.conversation.findUnique({
        where: { applyId: apply.id },
      });
      if (existing) return { apply, conversation: existing, isNew: false };

      const employerId = job.employerId ?? null;

      const conversation = await tx.conversation.create({
        data: {
          applyId:    apply.id,
          jobId,
          workerId:   userId,
          employerId,
        },
      });

      // System-Message: Bewerbung eingegangen
      await tx.message.create({
        data: {
          conversationId: conversation.id,
          senderId:       userId,
          text:           `Your application for "${job.title}" has been submitted. The employer will review your profile and get back to you.`,
          isSystem:       true,
          isRead:         true,
        },
      });

      return { apply, conversation, isNew: true };
    });

    return res.json({ ok: true, conversationId: result.conversation.id });
  } catch (err) {
    console.error("POST /jobs/:id/apply error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /jobs/:id/skip
// ─────────────────────────────────────────────
router.post("/:id/skip", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const jobId  = req.params.id;

    await prisma.skip.upsert({
      where:  { userId_jobId: { userId, jobId } },
      create: { userId, jobId },
      update: {},
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /jobs/:id/skip error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /jobs/:id/save
// ─────────────────────────────────────────────
router.post("/:id/save", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const jobId  = req.params.id;

    await prisma.save.upsert({
      where:  { userId_jobId: { userId, jobId } },
      create: { userId, jobId },
      update: {},
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /jobs/:id/save error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /jobs/:id/save
// ─────────────────────────────────────────────
router.delete("/:id/save", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const jobId  = req.params.id;
    await prisma.save.deleteMany({ where: { userId, jobId } });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /jobs/:id/save error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /jobs/mine — alle Jobs des eingeloggten Arbeitgebers
// ─────────────────────────────────────────────
router.get("/mine", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const jobs = await prisma.job.findMany({
      where: { employerId },
      orderBy: { createdAt: "desc" },
      include: {
        _count: { select: { applies: true } },
      },
    });

    // applicantCount mitsenden
    const result = jobs.map(({ _count, ...job }) => ({
      ...job,
      applicantCount: _count.applies,
    }));

    return res.json({ jobs: result });
  } catch (err) {
    console.error("GET /jobs/mine error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// PATCH /jobs/:id/status — Status ändern (publish draft, cancel)
// ─────────────────────────────────────────────
router.patch("/:id/status", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const jobId      = req.params.id;
    const { status, reason } = req.body;

    const allowed = ["published", "draft", "cancelled", "completed", "inProgress"];
    if (!allowed.includes(status)) {
      return res.status(400).json({ error: `Invalid status. Allowed: ${allowed.join(", ")}` });
    }

    const job = await prisma.job.findUnique({ where: { id: jobId } });
    if (!job)                        return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const updated = await prisma.job.update({
      where: { id: jobId },
      // Grund nur beim Stornieren speichern; bei jedem anderen Status zuruecksetzen
      data:  { status, cancellationReason: status === "cancelled" ? normalizeCancellationReason(reason) : null },
    });

    console.log(`PATCH /jobs/${jobId}/status → ${status}`);
    return res.json({ job: updated });
  } catch (err) {
    console.error("PATCH /jobs/:id/status error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// Helper: Fehler fuer PUT/DELETE auf Nicht-Drafts (404/403/409) beantworten
// ─────────────────────────────────────────────
async function respondDraftError(req, res) {
  const job = await prisma.job.findUnique({ where: { id: req.params.id } });
  const denied = checkDraftAccess(job, req.auth.sub);
  if (denied) {
    const { status, ...body } = denied;
    return res.status(status).json(body);
  }
  // Zwischenzeitlich geaendert (Race): sicherheitshalber als Konflikt melden
  return res.status(409).json({ error: "Only drafts can be edited or deleted.", code: "NOT_DRAFT" });
}

// ─────────────────────────────────────────────
// PUT /jobs/:id — Draft bearbeiten (optional direkt veroeffentlichen via status: "published")
// Atomar: updateMany mit id + employerId + status "draft" im where.
// ─────────────────────────────────────────────
router.put("/:id", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const { title, category, location, status } = req.body;
    if (!title || !category) {
      return res.status(400).json({ error: "title and category are required." });
    }
    if (status != null && status !== "draft" && status !== "published") {
      return res.status(400).json({ error: "status must be 'draft' or 'published'." });
    }
    const invalid = validateJobBody(req.body);
    if (invalid) return res.status(400).json({ error: invalid });

    const existing = await prisma.job.findUnique({ where: { id: req.params.id } });
    const denied = checkDraftAccess(existing, req.auth.sub);
    if (denied) {
      const { status: code, ...body } = denied;
      return res.status(code).json(body);
    }

    const data = buildJobData(req.body);
    // company nur uebernehmen, wenn mitgeschickt
    if (!req.body.company) delete data.company;

    // Geocoding nur, wenn der Ort geaendert wurde und der Client keine Koordinaten schickt
    if (data.lat == null) {
      if (location && location === existing.location && existing.lat != null) {
        data.lat = existing.lat;
        data.lng = existing.lng;
      } else if (location) {
        const coords = await geocodeLocation(location);
        if (coords) { data.lat = coords.lat; data.lng = coords.lng; }
      }
    }

    const result = await prisma.job.updateMany({
      where: { id: existing.id, employerId: req.auth.sub, status: "draft" },
      data: { ...data, status: status ?? "draft", updatedAt: new Date() },
    });
    if (result.count === 0) return respondDraftError(req, res);

    const updated = await prisma.job.findUnique({ where: { id: existing.id } });
    // Zwischen Update und Lesen geloescht (sehr unwahrscheinlich)
    if (!updated) return res.status(404).json({ error: "Job not found" });
    console.log(`PUT /jobs/${existing.id} — "${title}" (${updated.status})`);
    return res.json({ job: updated });
  } catch (err) {
    console.error("PUT /jobs/:id error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /jobs/:id — Draft endgueltig loeschen
// Atomar via deleteMany (id + employerId + status "draft"), damit ein zwischenzeitlich
// veroeffentlichter Job nie per Cascade samt Bewerbungen/Chats geloescht wird.
// ─────────────────────────────────────────────
router.delete("/:id", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const result = await prisma.job.deleteMany({
      where: { id: req.params.id, employerId: req.auth.sub, status: "draft" },
    });
    if (result.count === 0) return respondDraftError(req, res);
    console.log(`DELETE /jobs/${req.params.id}`);
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /jobs/:id error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /jobs/:id — Single job detail
// ─────────────────────────────────────────────
router.get("/:id", requireAuth, requireVerifiedEmail, async (req, res) => {
  const { id } = req.params;
  const userId  = req.auth.sub;
  try {
    const job = await prisma.job.findUnique({ where: { id } });
    if (!job) return res.status(404).json({ error: "Job not found" });
    const [enriched] = await enrichJobsWithRatings([job], userId);

    // Firmenblock: Branche/Business Areas (Employer-Profil) + abgeschlossene Schichten der Firma
    // (gleiche Zaehlung wie completedJobs im Firmenprofil, utils/companyStats.js)
    const [employer, companyJobs] = await Promise.all([
      job.employerId
        ? prisma.employer.findFirst({ where: { userId: job.employerId }, select: { industry: true, businessAreas: true } })
        : null,
      prisma.job.findMany({ where: companyJobsWhere(job.company), select: { status: true } }),
    ]);
    return res.json({
      job: {
        ...enriched,
        companyIndustry:       employer?.industry || null,
        companyBusinessAreas:  employer?.businessAreas ?? [],
        companyCompletedJobs:  countCompletedJobs(companyJobs),
      },
    });
  } catch (err) {
    console.error("GET /jobs/:id error:", err);
    return res.status(500).json({ error: "Server error" });
  }
});

// ─────────────────────────────────────────────
// GET /jobs/:id/applicants — Bewerber für einen Job
// ─────────────────────────────────────────────
router.get("/:id/applicants", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const jobId      = req.params.id;

    const job = await prisma.job.findUnique({ where: { id: jobId } });
    if (!job)                        return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const statusFilter = req.query.status; // optional: "pending" | "accepted" | "declined"

    const applies = await prisma.apply.findMany({
      where: {
        jobId,
        ...(statusFilter ? { status: statusFilter } : {}),
      },
      orderBy: { createdAt: "desc" },
    });

    const userIds = applies.map((a) => a.userId);
    const users   = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: {
        id: true, firstName: true, lastName: true, location: true,
        worker: { select: { profilePhotoUrl: true } },
      },
    });
    const userMap = Object.fromEntries(users.map((u) => [u.id, u]));

    // Ratings pro Worker aggregieren
    const reviews = await prisma.review.findMany({
      where: { workerId: { in: userIds } },
      select: { workerId: true, communication: true, teamwork: true, reliability: true, underPressure: true, workQuality: true },
    });
    const ratingMap = {};
    for (const r of reviews) {
      const avg = reviewOverall(r); // Mittel der vorhandenen Kategorien (workQuality kann null sein)
      if (avg === null) continue;
      if (!ratingMap[r.workerId]) ratingMap[r.workerId] = { sum: 0, count: 0 };
      ratingMap[r.workerId].sum   += avg;
      ratingMap[r.workerId].count += 1;
    }

    const applicants = applies.map((a) => {
      const u = userMap[a.userId];
      const r = ratingMap[a.userId];
      const name = [u?.firstName, u?.lastName].filter(Boolean).join(" ") || "Unknown";
      return {
        applyId:         a.id,
        userId:          a.userId,
        status:          a.status,
        appliedAt:       a.createdAt,
        workerName:      name,
        profilePhotoUrl: u?.worker?.profilePhotoUrl ?? null,
        rating:          r ? Math.round((r.sum / r.count) * 10) / 10 : 0,
        location:        u?.location ?? null,
      };
    });

    return res.json({ applicants });
  } catch (err) {
    console.error("GET /jobs/:id/applicants error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
