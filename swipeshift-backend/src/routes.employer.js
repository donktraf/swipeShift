// src/routes.employer.js

const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");

const router = express.Router();

// ─────────────────────────────────────────────
// GET /employer/applicants
// Alle Bewerber über alle Jobs des eingeloggten Arbeitgebers
// ─────────────────────────────────────────────
router.get("/applicants", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    // Alle Jobs des Arbeitgebers
    const myJobs = await prisma.job.findMany({
      where: { employerId },
      select: { id: true, title: true, payText: true, shiftText: true, location: true, logoEmoji: true },
    });
    const jobIds  = myJobs.map((j) => j.id);
    const jobMap  = Object.fromEntries(myJobs.map((j) => [j.id, j]));

    if (!jobIds.length) return res.json({ applicants: [] });

    // Alle Bewerbungen für diese Jobs
    const applies = await prisma.apply.findMany({
      where:   { jobId: { in: jobIds } },
      orderBy: { createdAt: "desc" },
    });

    // User-Daten laden
    const userIds = [...new Set(applies.map((a) => a.userId))];
    const users   = await prisma.user.findMany({
      where:  { id: { in: userIds } },
      select: { id: true, firstName: true, lastName: true, location: true, profilePhotoUrl: true },
      // profilePhotoUrl kommt aus Worker-Relation
    });

    // Worker-Profil (für profilePhotoUrl)
    const workers = await prisma.worker.findMany({
      where:  { userId: { in: userIds } },
      select: { userId: true, profilePhotoUrl: true },
    });
    const workerPhotoMap = Object.fromEntries(workers.map((w) => [w.userId, w.profilePhotoUrl]));

    const userMap = Object.fromEntries(users.map((u) => [u.id, u]));

    const applicants = applies.map((a) => ({
      applyId:       a.id,
      userId:        a.userId,
      appliedAt:     a.createdAt,
      status:        a.status,
      job:           jobMap[a.jobId] ?? null,
      user:          userMap[a.userId]
        ? {
            ...userMap[a.userId],
            profilePhotoUrl: workerPhotoMap[a.userId] ?? null,
          }
        : null,
    }));

    return res.json({ applicants });
  } catch (err) {
    console.error("GET /employer/applicants error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/applicants/:applyId/accept
// ─────────────────────────────────────────────
router.post("/applicants/:applyId/accept", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    await prisma.apply.update({ where: { id: applyId }, data: { status: "accepted" } });
    console.log(`ACCEPT apply ${applyId} by employer ${employerId}`);
    return res.json({ ok: true, applyId, action: "accepted" });
  } catch (err) {
    console.error("POST /employer/applicants/:id/accept error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/applicants/:applyId/decline
// ─────────────────────────────────────────────
router.post("/applicants/:applyId/decline", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    await prisma.apply.update({ where: { id: applyId }, data: { status: "declined" } });
    console.log(`DECLINE apply ${applyId} by employer ${employerId}`);
    return res.json({ ok: true, applyId, action: "declined" });
  } catch (err) {
    console.error("POST /employer/applicants/:id/decline error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/stats
// Dashboard-Kennzahlen für den eingeloggten Arbeitgeber
// ─────────────────────────────────────────────
router.get("/stats", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const now        = new Date();
    const weekAgo    = new Date(now.getTime() - 7 * 24 * 3_600_000);
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const myJobs = await prisma.job.findMany({
      where:  { employerId },
      select: { id: true, status: true, payAmount: true, openSpots: true, category: true, startTime: true },
    });
    const myJobIds = myJobs.map((j) => j.id);

    const activeJobs = myJobs.filter((j) => j.status === "published").length;

    const allApplies = myJobIds.length
      ? await prisma.apply.findMany({
          where:  { jobId: { in: myJobIds } },
          select: { id: true, createdAt: true },
        })
      : [];

    const newApplicants    = allApplies.length;
    const applicationsWeek = allApplies.filter((a) => a.createdAt >= weekAgo).length;

    const completedThisMonth = myJobs.filter(
      (j) => j.status === "completed" && j.startTime && new Date(j.startTime) >= monthStart
    );
    const monthlySpend = completedThisMonth.reduce(
      (sum, j) => sum + (j.payAmount ?? 0) * (j.openSpots ?? 1), 0
    );

    const jobsFilledWeek = myJobs.filter(
      (j) => j.status === "completed" && j.startTime && new Date(j.startTime) >= weekAgo
    ).length;

    const catCount = {};
    myJobs.forEach((j) => { if (j.category) catCount[j.category] = (catCount[j.category] ?? 0) + 1; });
    const topCategory = Object.entries(catCount).sort((a, b) => b[1] - a[1])[0]?.[0] ?? "—";

    return res.json({
      activeJobs,
      newApplicants,
      monthlySpend,
      applicationsThisWeek: applicationsWeek,
      jobsFilledThisWeek:   jobsFilledWeek,
      topCategory,
    });
  } catch (err) {
    console.error("GET /employer/stats error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/financials
// Finanzübersicht: Gesamtausgaben, Upcoming Payments, abgeschlossene Jobs
// ─────────────────────────────────────────────
router.get("/financials", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const now        = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const myJobs = await prisma.job.findMany({
      where:  { employerId },
      select: {
        id: true, title: true, status: true, payAmount: true,
        openSpots: true, startTime: true, endTime: true,
        shiftText: true, logoEmoji: true, category: true,
      },
    });

    const completedJobs = myJobs.filter(j => j.status === "completed");
    const upcomingJobs  = myJobs.filter(j => j.status === "published" && j.startTime && new Date(j.startTime) > now);

    const calcCost = (j) => (j.payAmount ?? 0) * (j.openSpots ?? 1);

    const totalSpending     = completedJobs.reduce((s, j) => s + calcCost(j), 0);
    const upcomingPayments  = upcomingJobs.reduce((s, j) => s + calcCost(j), 0);
    const monthlySpend      = completedJobs
      .filter(j => j.startTime && new Date(j.startTime) >= monthStart)
      .reduce((s, j) => s + calcCost(j), 0);

    // Letzte 7 Tage für Chart
    const days = Array.from({ length: 7 }, (_, i) => {
      const d = new Date(now);
      d.setDate(d.getDate() - (6 - i));
      d.setHours(0, 0, 0, 0);
      return d;
    });

    const chartData = days.map(day => {
      const dayEnd = new Date(day); dayEnd.setHours(23, 59, 59, 999);
      const label  = day.toLocaleDateString("en-US", { weekday: "short" });
      const dayJobs = myJobs.filter(j => j.startTime && new Date(j.startTime) >= day && new Date(j.startTime) <= dayEnd);
      return {
        day:       label,
        upcoming:  dayJobs.filter(j => j.status === "published").reduce((s, j) => s + calcCost(j), 0),
        completed: dayJobs.filter(j => j.status === "completed").reduce((s, j) => s + calcCost(j), 0),
        paidOut:   0, // Kein echtes Zahlungsmodell im MVP
      };
    });

    // Kategorien-Aufschlüsselung
    const byCategory = {};
    completedJobs.forEach(j => {
      const cat = j.category ?? "Other";
      byCategory[cat] = (byCategory[cat] ?? 0) + calcCost(j);
    });

    return res.json({
      totalSpending,
      upcomingPayments,
      completedJobsCount: completedJobs.length,
      paidOut:            0,
      monthlySpend,
      chartData,
      byCategory,
      upcomingJobs: upcomingJobs.slice(0, 10).map(j => ({
        id:        j.id,
        title:     j.title,
        logoEmoji: j.logoEmoji,
        shiftText: j.shiftText,
        amount:    calcCost(j),
        status:    "upcoming",
      })),
      completedJobsList: completedJobs.slice(0, 10).map(j => ({
        id:        j.id,
        title:     j.title,
        logoEmoji: j.logoEmoji,
        shiftText: j.shiftText,
        amount:    calcCost(j),
        status:    "completed",
      })),
    });
  } catch (err) {
    console.error("GET /employer/financials error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/applicants/:applyId/unassign
// Accepted Worker wieder auf "pending" zurücksetzen
// ─────────────────────────────────────────────
router.post("/applicants/:applyId/unassign", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    await prisma.apply.update({ where: { id: applyId }, data: { status: "pending" } });
    return res.json({ ok: true, applyId, action: "unassigned" });
  } catch (err) {
    console.error("POST /employer/applicants/:id/unassign error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/assigned-workers
// Jobs des Arbeitgebers mit ihren akzeptierten Bewerbern
// ─────────────────────────────────────────────
router.get("/assigned-workers", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const jobs = await prisma.job.findMany({
      where:   { employerId, status: { in: ["published", "inProgress"] } },
      orderBy: { startTime: "asc" },
      select: {
        id: true, title: true, logoEmoji: true, category: true,
        location: true, openSpots: true, shifts: true,
        applies: {
          where:  { status: "accepted" },
          select: {
            id:     true,
            userId: true,
            user: {
              select: { id: true, firstName: true, lastName: true },
            },
          },
        },
      },
    });

    const result = jobs.map((job) => ({
      id:          job.id,
      title:       job.title,
      logoEmoji:   job.logoEmoji,
      category:    job.category ?? "",
      location:    job.location,
      openSpots:   job.openSpots,
      shifts:      Array.isArray(job.shifts) ? job.shifts : [],
      assignedWorkers: job.applies.map((a) => ({
        applyId:     a.id,
        userId:      a.userId,
        name:        `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim(),
        photoEmoji:  "👤",
        rating:      0.0,
      })),
    }));

    return res.json({ jobs: result });
  } catch (err) {
    console.error("GET /employer/assigned-workers error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
