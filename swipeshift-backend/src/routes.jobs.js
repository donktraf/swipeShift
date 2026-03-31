// src/routes.jobs.js

const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { haversineDistance } = require("./utils/haversine");
const { geocodeLocation }  = require("./utils/geocode");

const router = express.Router();

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
        orderBy: { openSpots: "desc" },
      });

    } else if (type === "recommended") {
      jobs = await prisma.job.findMany({
        where: baseWhere,
        orderBy: { payAmount: "desc" },
      });

    } else {
      jobs = await prisma.job.findMany({
        where: baseWhere,
        orderBy: { createdAt: "desc" },
      });
    }

    return res.json({ jobs });
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

    return res.json({
      jobs: nearbyJobs,
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
        company:     company || "Unbekannt",
        location:    location || "",
        lat,
        lng,
        category:    category || null,
        tags:        tags || [],
        payText:     payText || (payAmount ? `€${payAmount} / hour` : "Auf Anfrage"),
        payAmount:   payAmount ? parseFloat(payAmount) : null,
        shiftText:   shifts?.[0] ? `${shifts[0].date}, ${shifts[0].timeRange}` : "",
        startTime:   null,
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

    await prisma.apply.upsert({
      where:  { userId_jobId: { userId, jobId } },
      create: { userId, jobId },
      update: {},
    });

    return res.json({ ok: true });
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
    const { status } = req.body;

    const allowed = ["published", "draft", "cancelled", "completed", "inProgress"];
    if (!allowed.includes(status)) {
      return res.status(400).json({ error: `Invalid status. Allowed: ${allowed.join(", ")}` });
    }

    const job = await prisma.job.findUnique({ where: { id: jobId } });
    if (!job)                        return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const updated = await prisma.job.update({
      where: { id: jobId },
      data:  { status },
    });

    console.log(`PATCH /jobs/${jobId}/status → ${status}`);
    return res.json({ job: updated });
  } catch (err) {
    console.error("PATCH /jobs/:id/status error:", err);
    return res.status(500).json({ error: "Internal server error" });
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

    const applies = await prisma.apply.findMany({
      where: { jobId },
      orderBy: { createdAt: "desc" },
      include: {
        // Worker-Profildaten aus User-Tabelle
        job: false,
      },
    });

    // User-Daten für jeden Bewerber laden
    const userIds = applies.map((a) => a.userId);
    const users   = await prisma.user.findMany({
      where: { id: { in: userIds } },
      select: { id: true, firstName: true, lastName: true, location: true, lat: true, lng: true },
    });
    const userMap = Object.fromEntries(users.map((u) => [u.id, u]));

    const applicants = applies.map((a) => ({
      applyId:   a.id,
      userId:    a.userId,
      appliedAt: a.createdAt,
      user:      userMap[a.userId] ?? null,
    }));

    return res.json({ applicants });
  } catch (err) {
    console.error("GET /jobs/:id/applicants error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
