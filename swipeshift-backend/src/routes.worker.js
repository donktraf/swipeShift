// src/routes.worker.js

const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { resolvePeriod, prismaRange } = require("./utils/period");

const router = express.Router();

// ─────────────────────────────────────────────
// GET /worker/applications
// Alle Bewerbungen des eingeloggten Workers
// ─────────────────────────────────────────────
router.get("/applications", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const now      = new Date();

    const applies = await prisma.apply.findMany({
      where:   { userId: workerId },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            location: true, payText: true, shiftText: true,
            startTime: true, endTime: true, category: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const applications = applies.map((a) => {
      const job = a.job;
      // Determine display status
      let displayStatus;
      if (a.status === "declined") {
        displayStatus = "cancelled";
      } else if (a.status === "accepted") {
        displayStatus = job?.endTime && new Date(job.endTime) < now ? "completed" : "confirmed";
      } else {
        displayStatus = "applied";
      }

      return {
        id:            a.id,
        jobId:         a.jobId,
        jobTitle:      job?.title     ?? "—",
        company:       job?.company   ?? "—",
        logoEmoji:     job?.logoEmoji ?? "🏢",
        location:      job?.location  ?? "—",
        payText:       job?.payText   ?? "—",
        shiftText:     job?.shiftText ?? "—",
        category:      job?.category  ?? "—",
        startTime:     job?.startTime ?? null,
        endTime:       job?.endTime   ?? null,
        appliedAt:     a.createdAt,
        displayStatus,
      };
    });

    return res.json({ applications });
  } catch (err) {
    console.error("GET /worker/applications error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /worker/applications/:applyId
// Bewerbung zurückziehen (nur pending)
// ─────────────────────────────────────────────
router.delete("/applications/:applyId", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId  = req.auth.sub;
    const { applyId } = req.params;

    const apply = await prisma.apply.findUnique({ where: { id: applyId } });

    if (!apply)                    return res.status(404).json({ error: "Application not found" });
    if (apply.userId !== workerId) return res.status(403).json({ error: "Forbidden" });
    if (apply.status !== "pending") return res.status(400).json({ error: "Can only withdraw pending applications" });

    await prisma.apply.delete({ where: { id: applyId } });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /worker/applications/:id error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /worker/saved
// Gespeicherte Jobs des eingeloggten Workers
// ─────────────────────────────────────────────
router.get("/saved", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;

    const saves = await prisma.save.findMany({
      where:   { userId: workerId },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            location: true, payText: true, shiftText: true, category: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    // Prüfen ob der Worker sich beworben hat
    const jobIds = saves.map((s) => s.jobId);
    const applies = jobIds.length
      ? await prisma.apply.findMany({
          where:  { userId: workerId, jobId: { in: jobIds } },
          select: { jobId: true, status: true },
        })
      : [];
    const applyMap = Object.fromEntries(applies.map((a) => [a.jobId, a.status]));

    const saved = saves.map((s) => {
      const applyStatus = applyMap[s.jobId];
      let appliedStatus = null;
      if (applyStatus === "pending")   appliedStatus = "Applied";
      if (applyStatus === "accepted")  appliedStatus = "Confirmed";

      return {
        id:            s.id,
        jobId:         s.jobId,
        title:         s.job?.title     ?? "—",
        company:       s.job?.company   ?? "—",
        logoEmoji:     s.job?.logoEmoji ?? "🏢",
        location:      s.job?.location  ?? "—",
        payText:       s.job?.payText   ?? "—",
        shiftText:     s.job?.shiftText ?? "—",
        savedAt:       s.createdAt,
        appliedStatus,
      };
    });

    return res.json({ saved });
  } catch (err) {
    console.error("GET /worker/saved error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /worker/reviews
// Bewertungen die Arbeitgeber über diesen Worker abgegeben haben
// ─────────────────────────────────────────────
router.get("/reviews", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;

    const reviews = await prisma.review.findMany({
      where:   { workerId },
      include: {
        apply: {
          include: {
            job: {
              select: { title: true, category: true, startTime: true, logoEmoji: true },
            },
            user: {
              include: {
                employer: { select: { companyName: true } },
              },
            },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const mapped = reviews.map((r) => ({
      id:            r.id,
      companyName:   r.apply.user?.employer?.companyName ?? "Unknown Company",
      jobType:       r.apply.job?.category ?? "—",
      date:          r.createdAt,
      communication: r.communication,
      teamwork:      r.teamwork,
      reliability:   r.reliability,
      underPressure: r.underPressure,
      feedback:      r.comment ?? "",
      wouldRehire:   r.wouldRehire,
    }));

    const avg = (arr) => arr.length ? arr.reduce((a, b) => a + b, 0) / arr.length : 0;
    const overallRating = mapped.length
      ? avg(mapped.map((r) => (r.communication + r.teamwork + r.reliability + r.underPressure) / 4))
      : 0;

    return res.json({
      reviews:       mapped,
      overallRating: Math.round(overallRating * 10) / 10,
      totalJobs:     mapped.length,
    });
  } catch (err) {
    console.error("GET /worker/reviews error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /worker/reviews
// Worker bewertet Arbeitgeber nach abgeschlossenem Job
// ─────────────────────────────────────────────
router.post("/reviews", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const {
      applyId,
      communication,
      paymentFairness,
      workEnvironment,
      jobDescriptionAccuracy,
      overallExperience,
      comment,
    } = req.body;

    if (
      !applyId ||
      communication == null || paymentFairness == null ||
      workEnvironment == null || jobDescriptionAccuracy == null ||
      overallExperience == null
    ) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    const apply = await prisma.apply.findFirst({
      where:   { id: applyId, userId: workerId },
      include: { job: { select: { employerId: true } } },
    });
    if (!apply) return res.status(404).json({ error: "Application not found" });

    const review = await prisma.workerReview.upsert({
      where:  { applyId },
      create: {
        applyId,
        employerId:            apply.job?.employerId ?? "",
        workerId,
        jobId:                 apply.jobId,
        communication,
        paymentFairness,
        workEnvironment,
        jobDescriptionAccuracy,
        overallExperience,
        comment:               comment ?? null,
      },
      update: {
        communication,
        paymentFairness,
        workEnvironment,
        jobDescriptionAccuracy,
        overallExperience,
        comment: comment ?? null,
      },
    });

    return res.json({ ok: true, review });
  } catch (err) {
    console.error("POST /worker/reviews error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /worker/financials
// Finanzübersicht des Workers (aus akzeptierten Bewerbungen)
// ─────────────────────────────────────────────
router.get("/financials", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const now      = new Date();
    // period = thisMonth | last3Months | thisYear | allTime | custom (&from&to=YYYY-MM-DD)
    const range = resolvePeriod(req.query, now);
    if (range.error) return res.status(400).json({ error: range.error });
    const startTimeRange = prismaRange(range);

    const applies = await prisma.apply.findMany({
      where: {
        userId: workerId,
        status: "accepted",
        ...(startTimeRange ? { job: { startTime: startTimeRange } } : {}),
      },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            payAmount: true, startTime: true, endTime: true, shiftText: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const calcEarning = (a) => {
      const job = a.job;
      if (!job) return 0;
      const hours = job.startTime && job.endTime
        ? (new Date(job.endTime) - new Date(job.startTime)) / 3_600_000
        : 8;
      return (job.payAmount ?? 0) * hours;
    };

    const upcoming   = applies.filter((a) => a.job?.startTime && new Date(a.job.startTime) > now);
    const completed  = applies.filter((a) => a.job?.endTime   && new Date(a.job.endTime)   <= now);
    const paidOutArr = completed.filter((a) => a.isPaid);

    const upcomingEarnings   = upcoming.reduce((s, a) => s + calcEarning(a), 0);
    const completedEarnings  = completed.reduce((s, a) => s + calcEarning(a), 0);
    const paidOut            = paidOutArr.reduce((s, a) => s + calcEarning(a), 0);

    const earningsList = applies.slice(0, 20).map((a) => ({
      id:        a.id,
      jobTitle:  a.job?.title     ?? "—",
      company:   a.job?.company   ?? "—",
      logoEmoji: a.job?.logoEmoji ?? "🏢",
      shiftText: a.job?.shiftText ?? "—",
      amount:    calcEarning(a),
      status:    a.job?.startTime && new Date(a.job.startTime) > now ? "upcoming" : "completed",
    }));

    return res.json({ upcomingEarnings, completedEarnings, paidOut, earningsList });
  } catch (err) {
    console.error("GET /worker/financials error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /worker/saved-companies
// Gespeicherte Unternehmen des eingeloggten Workers
// ─────────────────────────────────────────────
router.get("/saved-companies", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;

    const savedList = await prisma.savedCompany.findMany({
      where:   { userId },
      orderBy: { savedAt: "desc" },
    });

    const enriched = await Promise.all(
      savedList.map(async (sc) => {
        const [jobs, reviews] = await Promise.all([
          prisma.job.findMany({
            where:  { company: { equals: sc.companyName, mode: "insensitive" } },
            select: { logoEmoji: true, isVerified: true, status: true },
          }),
          prisma.workerReview.findMany({
            where:  { job: { company: { equals: sc.companyName, mode: "insensitive" } } },
            select: { overallExperience: true },
          }),
        ]);

        const openJobs  = jobs.filter((j) => j.status === "published").length;
        const logoEmoji = jobs[0]?.logoEmoji ?? "🏢";
        const isVerified = jobs[0]?.isVerified ?? false;
        const rating = reviews.length
          ? Math.round((reviews.reduce((s, r) => s + r.overallExperience, 0) / reviews.length) * 10) / 10
          : null;

        return {
          id:          sc.id,
          companyName: sc.companyName,
          logoEmoji,
          isVerified,
          openJobs,
          rating,
          savedAt:     sc.savedAt,
        };
      })
    );

    return res.json({ savedCompanies: enriched });
  } catch (err) {
    console.error("GET /worker/saved-companies error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /worker/saved-companies
// Unternehmen speichern (idempotent)
// ─────────────────────────────────────────────
router.post("/saved-companies", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const { companyName } = req.body;

    if (!companyName) return res.status(400).json({ error: "companyName required" });

    await prisma.savedCompany.upsert({
      where:  { userId_companyName: { userId, companyName } },
      create: { userId, companyName },
      update: {},
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /worker/saved-companies error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /worker/saved-companies/:name
// Unternehmen entfernen
// ─────────────────────────────────────────────
router.delete("/saved-companies/:name", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const userId      = req.auth.sub;
    const companyName = decodeURIComponent(req.params.name);

    await prisma.savedCompany.deleteMany({ where: { userId, companyName } });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /worker/saved-companies/:name error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
