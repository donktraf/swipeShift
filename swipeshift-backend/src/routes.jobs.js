// src/routes.jobs.js

const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { haversineDistance } = require("./utils/haversine");
const { geocodeLocation }  = require("./utils/geocode");
const { normalizeCancellationReason } = require("./utils/applicationStatus");

const router = express.Router();

// Pausierte Arbeitgeber: ihre Jobs sind fuer Worker unsichtbar und nicht bewerbbar
async function pausedEmployerFilter() {
  const paused = await prisma.user.findMany({
    where: { pausedAt: { not: null }, role: "employer" },
    select: { id: true },
  });
  if (!paused.length) return {};
  // OR noetig: NOT IN wuerde Jobs ohne employerId (Seed-Daten) mit ausschliessen
  return { OR: [{ employerId: null }, { employerId: { notIn: paused.map((u) => u.id) } }] };
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
      ...(await pausedEmployerFilter()),
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
// GET /jobs/nearby?lat=48.77&lng=9.18&radius=100
// ─────────────────────────────────────────────
router.get("/nearby", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const lat    = parseFloat(req.query.lat);
    const lng    = parseFloat(req.query.lng);
    const radius = parseFloat(req.query.radius) || 100;

    if (isNaN(lat) || isNaN(lng)) {
      return res.status(400).json({ error: "Missing or invalid lat/lng query params." });
    }

    // Radar zeigt immer alle Jobs — unabhängig von apply/skip
    const allJobs = await prisma.job.findMany({
      where: {
        ...(await pausedEmployerFilter()),
        status: "published",
        lat: { not: null },
        lng: { not: null },
      },
    });

    const nearbyJobs = allJobs
      .map((job) => {
        const distanceKm = haversineDistance(lat, lng, job.lat, job.lng);
        return { ...job, distanceKm: Math.round(distanceKm * 10) / 10, distanceText: `${Math.round(distanceKm * 10) / 10} km away` };
      })
      .filter((job) => job.distanceKm <= radius)
      .sort((a, b) => a.distanceKm - b.distanceKm);

    console.log(`Found ${nearbyJobs.length} jobs within ${radius}km of (${lat}, ${lng})`);

    const enrichedNearby = await enrichJobsWithRatings(nearbyJobs, userId);
    return res.json({
      jobs: enrichedNearby,
      meta: { lat, lng, radius, total: nearbyJobs.length },
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
    const {
      title, company, location, lat: bodyLat, lng: bodyLng, category, tags,
      shifts, openSpots, payAmount, payText,
      jobDescription, tasks, dressCode, languages,
      experienceLevel, minAge, paymentMethod, contractType,
      status = "published",
    } = req.body;

    if (!title || !category) {
      return res.status(400).json({ error: "title and category are required." });
    }

    // Koordinaten: direkt aus dem Request nutzen (vom iOS Location-Picker),
    // sonst Geocoding als Fallback (z.B. bei API-Calls ohne Picker)
    let lat = bodyLat != null ? parseFloat(bodyLat) : null;
    let lng = bodyLng != null ? parseFloat(bodyLng) : null;

    if (lat == null && location) {
      const coords = await geocodeLocation(location);
      if (coords) {
        lat = coords.lat;
        lng = coords.lng;
        console.log(`geocode fallback: "${location}" → lat=${lat}, lng=${lng}`);
      } else {
        console.warn(`geocode: Keine Koordinaten für "${location}" — Job wird ohne lat/lng gespeichert`);
      }
    } else if (lat != null) {
      console.log(`geocode: lat/lng vom Client übernommen (${lat}, ${lng})`);
    }

    const newJob = await prisma.job.create({
      data: {
        title,
        company:     company || "Unknown",
        location:    location || "",
        lat,
        lng,
        category:    category || null,
        tags:        tags || [],
        payText:     payText || (payAmount ? `€${payAmount} / hour` : "On request"),
        payAmount:   payAmount ? parseFloat(payAmount) : null,
        shiftText:   shifts?.[0] ? `${shifts[0].date}, ${shifts[0].timeRange}` : "",
        startTime:   shifts?.[0]?.startTimeISO ? new Date(shifts[0].startTimeISO) : null,
        endTime:     shifts?.[0]?.endTimeISO   ? new Date(shifts[0].endTimeISO)   : null,
        duration:    shifts?.[0]?.duration || null,
        shortInfo:   jobDescription ? jobDescription.slice(0, 120) : "",
        jobDescription: jobDescription || null,
        tasks:       tasks || [],
        openSpots:   openSpots || 1,
        shifts:      shifts || [],
        dressCode:   dressCode || null,
        languages:   languages || [],
        experienceLevel: experienceLevel || null,
        minAge:      minAge ? parseInt(minAge) : null,
        paymentMethod: paymentMethod || null,
        contractType:  contractType || null,
        logoEmoji:   "🏢",
        status,
        employerId:  req.auth.sub,
      },
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
// GET /jobs/:id — Single job detail
// ─────────────────────────────────────────────
router.get("/:id", requireAuth, requireVerifiedEmail, async (req, res) => {
  const { id } = req.params;
  const userId  = req.auth.sub;
  try {
    const job = await prisma.job.findUnique({ where: { id } });
    if (!job) return res.status(404).json({ error: "Job not found" });
    const [enriched] = await enrichJobsWithRatings([job], userId);
    return res.json({ job: enriched });
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
      select: { workerId: true, communication: true, teamwork: true, reliability: true, underPressure: true },
    });
    const ratingMap = {};
    for (const r of reviews) {
      const avg = (r.communication + r.teamwork + r.reliability + r.underPressure) / 4;
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
