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
      // Status: kein separates accepted/declined-Feld im MVP → immer "pending"
      status:        "pending",
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

    // MVP: Status-Feld auf Apply-Ebene noch nicht im Schema → Antwort reicht fürs MVP
    // TODO: Apply-Modell um status-Feld erweitern wenn Accept/Decline persistent gespeichert werden soll
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

    // MVP: Apply löschen = ablehnen
    await prisma.apply.delete({ where: { id: applyId } });
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

module.exports = router;
