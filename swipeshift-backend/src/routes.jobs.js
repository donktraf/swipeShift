// src/routes.jobs.js

const { reviewOverall } = require("./utils/reviewLogic");
const express = require("express");
const events = require("./notifyEvents");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { haversineDistance, kmToMiles, milesToKm } = require("./utils/haversine");
const { geocodeLocation }  = require("./utils/geocode");
const { summarizeJobApplies } = require("./utils/applyCounts");
const { buildJobData, validateJobBody, checkDraftAccess, publishGate, resolveCreateStatus, evaluateStatusChange, shouldAutoAccept } = require("./utils/jobData");
const { isBlockedBetween } = require("./utils/safety");
const { normalizeCancellationReason } = require("./utils/applicationStatus");
const { companyJobsWhere, countCompletedJobs } = require("./utils/companyStats");
const { countNewMatches, pickInlineApplies, inlineScheduleConflicts } = require("./utils/employerJobCard");
const { loadApplicantSummaries } = require("./applicantSummaries");

const { restrictedEmployerIds } = require("./restrictedUsers");
const { restrictedWhere, isRestricted, visibleApplyFilter } = require("./utils/moderation");

const router = express.Router();

// Pausierte Arbeitgeber: ihre Jobs sind fuer Worker unsichtbar und nicht bewerbbar
// Mit userId zusaetzlich: Arbeitgeber, die mit diesem User einen Block haben (beide Richtungen).
// Bewusst nur im Feed (GET /jobs, /jobs/nearby) ausgeblendet; Direktaufrufe (Job-Detail, Firmenprofil,
// Gespeichert, Deep Link) bleiben sichtbar – Bewerben ist dort per BLOCKED-Check in POST /:id/apply gesperrt.
async function pausedEmployerFilter(userId) {
  const paused = await prisma.user.findMany({
    where: { role: "employer", OR: [{ pausedAt: { not: null } }, ...restrictedWhere().OR] },
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

// Jobs, die der User explizit mit "Not interested" markiert hat — werden in ALLEN Feeds ausgeblendet
// (normale Swipe-Skips nur im Swipe-Feed, siehe GET /jobs)
async function getNotInterestedJobIds(userId) {
  const rows = await prisma.skip.findMany({ where: { userId, notInterested: true }, select: { jobId: true } });
  return rows.map((r) => r.jobId);
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
    } else {
      // Dashboard-Sektionen/Kategorien: nur "Not interested"-Jobs ausblenden
      seenIds = await getNotInterestedJobIds(userId);
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
        // Dringende Jobs zuerst (alphabetisch "urgent" > "normal", daher desc)
        orderBy: [{ urgency: "desc" }, { startTime: "asc" }],
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
    const notInterestedIds = await getNotInterestedJobIds(userId);
    const allJobs = await prisma.job.findMany({
      where: {
        ...(await pausedEmployerFilter(userId)),
        status: "published",
        lat: { not: null },
        lng: { not: null },
        ...(notInterestedIds.length > 0 && { id: { notIn: notInterestedIds } }),
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
    const resolved = resolveCreateStatus(req.body.status);
    if (resolved.error) return res.status(400).json({ error: resolved.error });
    const status = resolved.status;

    if (!title || !category) {
      return res.status(400).json({ error: "title and category are required." });
    }

    const invalid = validateJobBody(req.body);
    if (invalid) return res.status(400).json({ error: invalid });

    const data = buildJobData(req.body);

    // Veroeffentlichen: Employer-AGB + Vollstaendigkeit (Drafts duerfen unvollstaendig sein)
    if (status === "published") {
      const denied = publishGate(req.body, data);
      if (denied) return res.status(denied.status).json(denied.body);
      data.termsAcceptedAt = new Date();
    }

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
      select: { id: true, title: true, employerId: true, status: true, openSpots: true, startTime: true, endTime: true, instantMatch: true, minAge: true, workAuthorizationRequired: true },
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
      const employer = await prisma.user.findUnique({ where: { id: job.employerId }, select: { pausedAt: true, bannedAt: true, suspendedUntil: true, suspensionReason: true } });
      employerPaused = !!employer?.pausedAt || isRestricted(employer);
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

    // Apply + Conversation in einer Transaktion.
    // Instant Match: Zaehlen der angenommenen Bewerbungen + Insert muessen atomar sein, sonst koennten
    // zwei parallele Bewerbungen den letzten freien Platz beide bekommen. Daher Isolation Serializable
    // (nur bei instantMatch) — bei Konflikt wirft Postgres/Prisma P2034, dann wird die Transaktion
    // wiederholt (max. 3 Versuche); der Retry sieht den neuen Count und faellt ggf. auf "pending" zurueck.
    const runApply = () => prisma.$transaction(async (tx) => {
      let apply = await tx.apply.findUnique({ where: { userId_jobId: { userId, jobId } } });
      const isNewApply = !apply;
      if (!apply) {
        let autoAccept = false;
        if (job.instantMatch) {
          const accepted = await tx.apply.count({ where: { jobId, status: "accepted" } });
          const worker = await tx.worker.findUnique({
            where: { userId }, select: { dateOfBirth: true, workAuthorization: true },
          });
          autoAccept = shouldAutoAccept({ job, worker, acceptedCount: accepted });
        }
        apply = await tx.apply.create({
          data: autoAccept
            ? { userId, jobId, status: "accepted", autoAccepted: true } // respondedAt bewusst nicht gesetzt
            : { userId, jobId },
        });
      }

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

      // System-Message nur bei neuer Bewerbung (kein Duplikat bei erneutem Apply)
      if (isNewApply) await tx.message.create({
        data: {
          conversationId: conversation.id,
          senderId:       userId,
          text:           apply.autoAccepted && apply.status === "accepted"
            ? `You're booked for "${job.title}"! This job uses Instant Match, so your application was accepted automatically.`
            : `Your application for "${job.title}" has been submitted. The employer will review your profile and get back to you.`,
          isSystem:       true,
          isRead:         true,
        },
      });

      return { apply, conversation, isNew: isNewApply };
    }, job.instantMatch ? { isolationLevel: "Serializable" } : undefined);

    let result;
    for (let attempt = 1; ; attempt++) {
      try {
        result = await runApply();
        break;
      } catch (err) {
        // P2034 = Serialisierungskonflikt/Deadlock; P2002 = parallele Doppel-Bewerbung desselben Users
        if (err.code === "P2034" || err.code === "P2002") {
          if (attempt < 3) {
            await new Promise((r) => setTimeout(r, 20 + Math.random() * 30)); // kleiner Jitter-Backoff
            continue;
          }
          if (err.code === "P2034") {
            return res.status(409).json({ error: "Too many applications at once. Please try again.", code: "TRY_AGAIN" });
          }
        }
        throw err;
      }
    }

    // Employer benachrichtigen (nur bei neuer Bewerbung, nicht bei erneutem Apply); fire-and-forget
    if (result.isNew) {
      events.workerApplied({
        employerId: job.employerId, workerId: userId, jobId, jobTitle: job.title,
        autoAccepted: result.apply.autoAccepted === true && result.apply.status === "accepted",
      });
    }
    return res.json({ ok: true, conversationId: result.conversation.id, autoAccepted: result.apply.autoAccepted === true });
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

    // notInterested: true → "Not interested" aus Gespeichert: entfernt zusaetzlich den Save und blendet den Job
    // in allen Feeds aus (nicht nur im Swipe-Feed)
    const notInterested = req.body?.notInterested === true;

    // hadSkip: es gab schon einen normalen Swipe-Skip → Undo darf ihn nicht loeschen (siehe DELETE unten)
    const before = await prisma.skip.findUnique({ where: { userId_jobId: { userId, jobId } }, select: { notInterested: true } });
    await prisma.skip.upsert({
      where:  { userId_jobId: { userId, jobId } },
      create: { userId, jobId, notInterested },
      update: notInterested ? { notInterested: true } : {},
    });
    if (notInterested) await prisma.save.deleteMany({ where: { userId, jobId } });

    return res.json({ ok: true, hadSkip: !!before && before.notInterested === false });
  } catch (err) {
    console.error("POST /jobs/:id/skip error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /jobs/:id/skip — Skip zurueknehmen (Undo von "Not interested")
// ─────────────────────────────────────────────
router.delete("/:id/skip", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const where = { userId: req.auth.sub, jobId: req.params.id };
    // ?restoreSkip=1: der Skip existierte vorher als normaler Swipe-Skip → nur "Not interested" zuruecknehmen
    if (req.query.restoreSkip === "1") await prisma.skip.updateMany({ where, data: { notInterested: false } });
    else await prisma.skip.deleteMany({ where });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /jobs/:id/skip error:", err);
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
        // Offene Bewerbungen gesperrter/gebannter Worker zaehlen/erscheinen nicht (angenommene bleiben)
        applies: { where: visibleApplyFilter(), select: { id: true, userId: true, status: true, autoAccepted: true, createdAt: true, conversation: { select: { id: true } } } },
      },
    });

    // Inline-Bewerber (max. 2 pro Job) – Profildaten fuer ALLE Jobs gebuendelt (kein N+1)
    const inlineByJob = new Map(jobs.map(({ id, status, applies }) =>
      [id, status === "published" ? pickInlineApplies(applies) : []]));
    const inlineUserIds = [...new Set([...inlineByJob.values()].flat().map((a) => a.userId))];
    const [summaries, users, acceptedApplies] = inlineUserIds.length
      ? await Promise.all([
          loadApplicantSummaries(inlineUserIds),
          prisma.user.findMany({
            where: { id: { in: inlineUserIds } },
            select: { id: true, firstName: true, lastName: true, worker: { select: { profilePhotoUrl: true } } },
          }),
          // Andere angenommene Jobs aller Inline-Bewerber (eine Query fuer alle Jobs) → Zeitkonflikt
          prisma.apply.findMany({
            where: { userId: { in: inlineUserIds }, status: "accepted" },
            select: { id: true, userId: true, jobId: true, job: { select: { startTime: true, endTime: true, status: true } } },
          }),
        ])
      : [new Map(), [], []];
    const inlineConflicts = inlineScheduleConflicts(jobs, inlineByJob, acceptedApplies);
    const userById = new Map(users.map((u) => [u.id, u]));

    // Zaehler siehe utils/applyCounts.js (applicantCount = nur unbeantwortete manuelle Bewerbungen)
    const result = jobs.map(({ applies, ...job }) => ({
      ...job,
      ...summarizeJobApplies(applies),
      newMatchCount: countNewMatches(applies, job.applicantsSeenAt),
      inlineApplicants: inlineByJob.get(job.id).map((a) => {
        const u = userById.get(a.userId);
        return {
          applyId: a.id,
          userId: a.userId,
          // Conversation entsteht schon beim Bewerben; die App zeigt "Message" erst nach Annahme
          conversationId: a.conversation?.id ?? null,
          name: [u?.firstName, u?.lastName].filter(Boolean).join(" ") || "Unknown",
          profilePhotoUrl: u?.worker?.profilePhotoUrl ?? null,
          ratingAverage: summaries.get(a.userId)?.ratingAverage ?? null,
          reviewCount: summaries.get(a.userId)?.reviewCount ?? 0,
          // Shift-Fit-Hinweis (wie auf der Bewerberkarte)
          availableDays: summaries.get(a.userId)?.availableDays ?? [],
          availableTimes: summaries.get(a.userId)?.availableTimes ?? [],
          hasScheduleConflict: inlineConflicts.has(a.id),
        };
      }),
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

    const job = await prisma.job.findUnique({ where: { id: jobId } });
    if (!job)                        return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    // Statuswechsel-Map, Terms und Vollstaendigkeit (gespeicherter Draft) — siehe utils/jobData.js
    const applicationCount = job.status === "published" && status === "draft"
      ? await prisma.apply.count({ where: { jobId } })
      : 0;
    const decision = evaluateStatusChange(job.status, status, req.body, { applicationCount, job });
    if (!decision.ok) return res.status(decision.status).json(decision.body);
    if (decision.noop) return res.json({ job }); // idempotent: gleicher Status, nichts zu tun

    // Bedingtes Update gegen Races: Status und updatedAt wie gelesen (ein paralleles PUT/Status-Update
    // macht den Vollstaendigkeits-Check hinfaellig); zurueck zu draft zusaetzlich nur ohne Bewerbungen.
    const toDraft = status === "draft";
    const result = await prisma.job.updateMany({
      where: { id: jobId, status: job.status, // Postgres speichert evtl. Mikrosekunden (Altzeilen), JS nur Millisekunden → 1-ms-Fenster
        updatedAt: { gte: job.updatedAt, lt: new Date(job.updatedAt.getTime() + 1) }, ...(toDraft ? { applies: { none: {} } } : {}) },
      // Grund nur beim Stornieren speichern; bei jedem anderen Status zuruecksetzen
      data:  {
        status,
        cancellationReason: status === "cancelled" ? normalizeCancellationReason(reason) : null,
        ...(decision.publishing ? { termsAcceptedAt: new Date() } : {}),
      },
    });
    if (result.count === 0) {
      // Neu lesen und den Grund anhand des aktuellen Zustands melden
      const current = await prisma.job.findUnique({ where: { id: jobId }, select: { status: true } });
      if (!current) return res.status(404).json({ error: "Job not found" });
      if (toDraft && current.status === "published") {
        const applyCount = await prisma.apply.count({ where: { jobId } });
        if (applyCount > 0) {
          return res.status(409).json({ error: "This job already has applications and can't be moved back to draft.", code: "HAS_APPLICANTS" });
        }
      }
      return res.status(409).json({ error: "The job was changed in the meantime. Please reload and try again.", code: "INVALID_TRANSITION" });
    }
    const updated = await prisma.job.findUnique({ where: { id: jobId } });

    if (status === "cancelled") events.jobCancelled(jobId);      // fire-and-forget
    if (status === "completed") events.paymentOpen(jobId);       // fire-and-forget (einmal pro Job)
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
    if (status === "published") {
      const gate = publishGate(req.body, data);
      if (gate) return res.status(gate.status).json(gate.body);
      data.termsAcceptedAt = new Date();
    }

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
    // Job eines gesperrten/gebannten Employers: nur noch sichtbar, wenn der Nutzer bereits eine Bewerbung darauf hat
    // (Kalender/Verlauf bleiben heil) bzw. selbst der Employer ist
    if (job.employerId && job.employerId !== userId) {
      const hidden = await restrictedEmployerIds();
      if (hidden.has(job.employerId)) {
        const mine = await prisma.apply.findFirst({ where: { userId, jobId: id }, select: { id: true } });
        if (!mine) return res.status(404).json({ error: "JOB_UNAVAILABLE", code: "JOB_UNAVAILABLE" });
      }
    }
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
router.post("/:id/applicants/seen", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const job = await prisma.job.findUnique({ where: { id: req.params.id }, select: { employerId: true } });
    if (!job) return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== req.auth.sub) return res.status(403).json({ error: "Forbidden" });
    // Raw-UPDATE nur dieser Spalte: ein Prisma-update wuerde Job.updatedAt (@updatedAt) anheben und damit
    // den optimistischen Lock in PATCH /jobs/:id/status + die "Last saved"-Anzeige verfaelschen
    await prisma.$executeRaw`UPDATE "Job" SET "applicantsSeenAt" = NOW() WHERE "id" = ${req.params.id}`;
    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /jobs/:id/applicants/seen error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

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
        // Offene Bewerbungen gesperrter/gebannter Worker sind ausgeblendet
        ...visibleApplyFilter(),
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
        autoAccepted:    a.autoAccepted === true,
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
