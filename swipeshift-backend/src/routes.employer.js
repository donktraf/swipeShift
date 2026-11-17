// src/routes.employer.js

const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { resolvePeriod, isInPeriod, buildBuckets } = require("./utils/period");
const { jobCosts, shiftHours } = require("./utils/jobCost");
const { ageFromBirthDate, availableDays, summarizeReviews, summarizeCompletedJobs, cleanSelfRatedSkills, stringList } = require("./utils/workerProfile");

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
// GET /employer/workers/:userId
// Echtes Worker-Profil fuer das Detail-Profil (ersetzt die frueheren Beispieldaten).
// Nur sichtbar, wenn sich der Worker auf einen Job DIESES Arbeitgebers beworben hat.
// Bewusst NICHT enthalten: Telefon, E-Mail, genaues Geburtsdatum (nur Alter).
// ─────────────────────────────────────────────
router.get("/workers/:userId", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { userId } = req.params;

    const hasApplied = await prisma.apply.findFirst({
      where: { userId, job: { employerId } },
      select: { id: true },
    });
    if (!hasApplied) return res.status(404).json({ error: "Worker not found" });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, firstName: true, lastName: true, location: true, emailVerifiedAt: true,
        worker: {
          select: {
            dateOfBirth: true, bio: true, profilePhotoUrl: true, jobInterests: true, availability: true,
            willingToRelocate: true, maxTravelDistance: true, transport: true, availableForSameDay: true,
            preferredCategories: true, payRangeMin: true, payRangeMax: true, skills: true,
            workAuthorization: true,
          },
        },
      },
    });
    if (!user) return res.status(404).json({ error: "Worker not found" });

    const [reviews, applies] = await Promise.all([
      prisma.review.findMany({
        where: { workerId: userId },
        orderBy: { createdAt: "desc" },
        select: {
          communication: true, teamwork: true, reliability: true, underPressure: true,
          wouldRehire: true, comment: true, createdAt: true,
          apply: { select: { job: { select: { title: true } } } },
        },
      }),
      prisma.apply.findMany({
        where: { userId },
        select: {
          status: true, isPaid: true,
          job: { select: { category: true, endTime: true, status: true, cancellationReason: true } },
        },
      }),
    ]);

    const w = user.worker;
    const age = ageFromBirthDate(w?.dateOfBirth);
    const summary = summarizeReviews(reviews);

    return res.json({
      worker: {
        id: user.id,
        firstName: user.firstName,
        lastName: user.lastName,
        location: user.location,
        isEmailVerified: !!user.emailVerifiedAt,
        profilePhotoUrl: w?.profilePhotoUrl ?? null,
        bio: w?.bio ?? null,
        age,
        isAdult: age === null ? null : age >= 18,
        availableDays: availableDays(w?.availability),
        maxTravelDistance: w?.maxTravelDistance ?? null,
        willingToRelocate: w?.willingToRelocate ?? false,
        availableForSameDay: w?.availableForSameDay ?? false,
        transport: w?.transport ?? null,
        preferredCategories: stringList(w?.preferredCategories),
        jobInterests: stringList(w?.jobInterests),
        payRangeMin: w?.payRangeMin ?? null,
        payRangeMax: w?.payRangeMax ?? null,
        selfRatedSkills: cleanSelfRatedSkills(w?.skills),
        workAuthorization: w?.workAuthorization ?? false,
      },
      stats: {
        ...summary,
        ...summarizeCompletedJobs(applies),
      },
      recentReviews: reviews
        .filter((r) => r.comment && r.comment.trim())
        .slice(0, 3)
        .map((r) => ({
          comment: r.comment.trim(),
          jobTitle: r.apply?.job?.title ?? null,
          createdAt: r.createdAt,
          rating: summarizeReviews([r]).overallRating,
          wouldRehire: r.wouldRehire,
        })),
    });
  } catch (err) {
    console.error("GET /employer/workers/:userId error:", err);
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

    await prisma.apply.update({
      where: { id: applyId },
      // respondedAt nur bei der ERSTEN Antwort setzen (Response Time = Zeit bis zur ersten Reaktion)
      data:  { status: "accepted", ...(apply.respondedAt ? {} : { respondedAt: new Date() }) },
    });
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

    await prisma.apply.update({
      where: { id: applyId },
      data:  { status: "declined", ...(apply.respondedAt ? {} : { respondedAt: new Date() }) },
    });
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
      select: {
        id: true, status: true, payAmount: true, openSpots: true, category: true,
        startTime: true, endTime: true,
        applies: { where: { status: "accepted" }, select: { isPaid: true } },
      },
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
    // Gleiche Formel wie Finanz-Uebersicht + Payment-Screen (Stundenlohn × Stunden × Worker)
    const monthlySpend = completedThisMonth.reduce((sum, j) => sum + jobCosts(j, j.applies).completed, 0);

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
// GET /employer/financials?period=thisMonth|last3Months|thisYear|allTime|custom[&from&to]
// Finanzübersicht: Gesamtausgaben, Upcoming Payments, abgeschlossene Jobs — gefiltert auf
// Jobs, deren Schicht im Zeitraum beginnt. "Monthly Spend" bleibt immer der laufende Monat.
// ─────────────────────────────────────────────
router.get("/financials", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const now        = new Date();
    const monthStart = new Date(now.getFullYear(), now.getMonth(), 1);

    const range = resolvePeriod(req.query, now);
    if (range.error) return res.status(400).json({ error: range.error });

    const myJobs = await prisma.job.findMany({
      where:  { employerId },
      select: {
        id: true, title: true, status: true, payAmount: true,
        openSpots: true, startTime: true, endTime: true,
        shiftText: true, logoEmoji: true, category: true,
        applies: { where: { status: "accepted" }, select: { isPaid: true } },
      },
      orderBy: { startTime: "desc" },
    });

    // Kosten pro Job: Stundenlohn × Stunden × Worker (siehe utils/jobCost.js)
    const costOf = new Map(myJobs.map(j => [j.id, jobCosts(j, j.applies)]));
    const cost   = (j) => costOf.get(j.id);
    const sum    = (jobs, key) => jobs.reduce((s, j) => s + cost(j)[key], 0);

    // Monthly Spend unabhaengig vom gewaehlten Zeitraum (wie im Dashboard)
    const monthlySpend = sum(
      myJobs.filter(j => j.status === "completed" && j.startTime && new Date(j.startTime) >= monthStart),
      "completed"
    );

    // "Upcoming" = veroeffentlicht UND Schicht in der Zukunft — gleiche Regel fuer Kachel,
    // Liste und Diagramm (vergangene, nie abgeschlossene Jobs zaehlen nicht als offene Zahlung)
    const isUpcoming = (j) => j.status === "published" && j.startTime && new Date(j.startTime) > now;

    const periodJobs    = myJobs.filter(j => isInPeriod(j.startTime, range));
    const completedJobs = periodJobs.filter(j => j.status === "completed");
    const upcomingJobs  = periodJobs.filter(isUpcoming).reverse(); // naechste zuerst

    const totalSpending    = sum(completedJobs, "completed"); // inkl. bereits bezahlter Worker
    const upcomingPayments = sum(upcomingJobs, "planned");
    const paidOut          = sum(periodJobs, "paidOut");

    // Diagramm-Achse: fester Zeitraum, bei "All Time" aus den tatsaechlichen Schichtdaten
    let { chartStart, chartEnd } = range;
    if (!chartStart) {
      const times = periodJobs.filter(j => j.startTime).map(j => new Date(j.startTime).getTime());
      if (times.length) {
        chartStart = new Date(Math.min(...times));
        chartEnd   = new Date(Math.max(...times, now.getTime()));
      }
    }

    const chartData = buildBuckets(chartStart, chartEnd).map(bucket => {
      const inBucket = periodJobs.filter(j => {
        if (!j.startTime) return false;
        const t = new Date(j.startTime);
        return t >= bucket.start && t <= bucket.end;
      });
      // Gestapelte Balken ohne Doppelzaehlung: completed = abgeschlossen, aber noch offen
      const done = inBucket.filter(j => j.status === "completed");
      return {
        day:       bucket.label,
        upcoming:  sum(inBucket.filter(isUpcoming), "planned"),
        completed: Math.max(0, sum(done, "completed") - sum(done, "paidOut")),
        paidOut:   sum(inBucket, "paidOut"),
      };
    });

    // Kategorien-Aufschlüsselung
    const byCategory = {};
    completedJobs.forEach(j => {
      const cat = j.category ?? "Other";
      byCategory[cat] = (byCategory[cat] ?? 0) + cost(j).completed;
    });

    // status: upcoming | completed | paid (alle angenommenen Worker bezahlt)
    const toListItem = (kind) => (j) => {
      const fullyPaid = j.applies.length > 0 && j.applies.every(a => a.isPaid);
      return {
        id:        j.id,
        title:     j.title,
        logoEmoji: j.logoEmoji,
        shiftText: j.shiftText,
        amount:    kind === "upcoming" ? cost(j).planned : cost(j).completed,
        status:    kind === "completed" && fullyPaid ? "paid" : kind,
      };
    };

    return res.json({
      period:             range.period,
      totalSpending,
      upcomingPayments,
      completedJobsCount: completedJobs.length,
      paidOut,
      monthlySpend,
      chartData,
      byCategory,
      upcomingJobs:       upcomingJobs.slice(0, 10).map(toListItem("upcoming")),
      completedJobsList:  completedJobs.slice(0, 10).map(toListItem("completed")),
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

// ─────────────────────────────────────────────
// GET /employer/jobs/:jobId/payments
// Alle akzeptierten Worker für diesen Job mit Zahlungsstatus
// ─────────────────────────────────────────────
router.get("/jobs/:jobId/payments", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { jobId }  = req.params;

    const job = await prisma.job.findUnique({
      where:  { id: jobId },
      select: { id: true, title: true, employerId: true, payAmount: true, startTime: true, endTime: true, logoEmoji: true },
    });

    if (!job)                              return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId)     return res.status(403).json({ error: "Forbidden" });

    const applies = await prisma.apply.findMany({
      where:   { jobId, status: "accepted" },
      include: { user: { select: { id: true, firstName: true, lastName: true } } },
      orderBy: { createdAt: "asc" },
    });

    const hourlyRate  = job.payAmount ?? 0;
    const hoursWorked = shiftHours(job); // gleiche Rundung wie Finanz-Uebersicht

    const shiftLabel = job.startTime
      ? new Date(job.startTime).toLocaleDateString("en-US", { month: "short", day: "numeric" })
      : "—";

    const workers = applies.map((a) => ({
      id:          a.id,
      name:        `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown",
      avatarEmoji: "👤",
      jobTitle:    job.title,
      shiftDate:   shiftLabel,
      hoursWorked,
      hourlyRate,
      isPaid:      a.isPaid,
    }));

    return res.json({ workers });
  } catch (err) {
    console.error("GET /employer/jobs/:id/payments error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/jobs/:jobId/workers/:applyId/pay
// Einzelnen Worker als bezahlt markieren
// ─────────────────────────────────────────────
router.post("/jobs/:jobId/workers/:applyId/pay", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { jobId, applyId } = req.params;

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.jobId !== jobId)               return res.status(400).json({ error: "Apply does not belong to this job" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    await prisma.apply.update({ where: { id: applyId }, data: { isPaid: true } });
    return res.json({ ok: true, applyId });
  } catch (err) {
    console.error("POST /employer/jobs/:jobId/workers/:applyId/pay error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/jobs/:jobId/pay-all
// Alle Worker eines Jobs als bezahlt markieren
// ─────────────────────────────────────────────
router.post("/jobs/:jobId/pay-all", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { jobId }  = req.params;

    const job = await prisma.job.findUnique({
      where:  { id: jobId },
      select: { employerId: true },
    });

    if (!job)                          return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const { count } = await prisma.apply.updateMany({
      where: { jobId, status: "accepted" },
      data:  { isPaid: true },
    });

    return res.json({ ok: true, updatedCount: count });
  } catch (err) {
    console.error("POST /employer/jobs/:jobId/pay-all error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/reviews/pending
// Akzeptierte Worker ohne Bewertung
// ─────────────────────────────────────────────
router.get("/reviews/pending", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const applies = await prisma.apply.findMany({
      where: {
        status: "accepted",
        job:    { employerId },
        review: null,
      },
      include: {
        user: { select: { id: true, firstName: true, lastName: true } },
        job:  { select: { id: true, title: true, category: true, startTime: true, logoEmoji: true } },
      },
      orderBy: { createdAt: "desc" },
    });

    const pending = applies.map((a) => ({
      applyId:     a.id,
      workerId:    a.userId,
      workerName:  `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown Worker",
      workerPhoto: null,
      jobId:       a.jobId,
      jobTitle:    a.job?.title    ?? "—",
      jobCategory: a.job?.category ?? "—",
      shiftDate:   a.job?.startTime ?? a.createdAt,
      logoEmoji:   a.job?.logoEmoji ?? "🏢",
    }));

    return res.json({ pending });
  } catch (err) {
    console.error("GET /employer/reviews/pending error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/reviews
// Bewertung einreichen
// ─────────────────────────────────────────────
router.post("/reviews", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId, communication, teamwork, reliability, underPressure, comment, wouldRehire } = req.body;

    if (!applyId || !communication || !teamwork || !reliability || !underPressure) {
      return res.status(400).json({ error: "Missing required fields" });
    }

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const review = await prisma.review.create({
      data: {
        employerId,
        workerId:     apply.userId,
        jobId:        apply.jobId,
        applyId,
        communication: Number(communication),
        teamwork:      Number(teamwork),
        reliability:   Number(reliability),
        underPressure: Number(underPressure),
        comment:       comment ?? null,
        wouldRehire:   wouldRehire ?? true,
      },
    });

    return res.json({ ok: true, review });
  } catch (err) {
    console.error("POST /employer/reviews error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/reviews
// Alle abgegebenen Bewertungen des Arbeitgebers
// ─────────────────────────────────────────────
router.get("/reviews", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const reviews = await prisma.review.findMany({
      where:   { employerId },
      include: {
        apply: {
          include: {
            user: { select: { id: true, firstName: true, lastName: true } },
            job:  { select: { id: true, title: true, category: true, startTime: true, logoEmoji: true } },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const result = reviews.map((r) => ({
      id:            r.id,
      workerName:    `${r.apply.user?.firstName ?? ""} ${r.apply.user?.lastName ?? ""}`.trim() || "Unknown",
      workerPhoto:   null,
      jobTitle:      r.apply.job?.title    ?? "—",
      jobCategory:   r.apply.job?.category ?? "—",
      logoEmoji:     r.apply.job?.logoEmoji ?? "🏢",
      shiftDate:     r.apply.job?.startTime ?? r.createdAt,
      communication: r.communication,
      teamwork:      r.teamwork,
      reliability:   r.reliability,
      underPressure: r.underPressure,
      comment:       r.comment,
      wouldRehire:   r.wouldRehire,
      createdAt:     r.createdAt,
    }));

    return res.json({ reviews: result });
  } catch (err) {
    console.error("GET /employer/reviews error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/applicants/:applyId/save
// Bewerber als gespeichert markieren
// ─────────────────────────────────────────────
router.post("/applicants/:applyId/save", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    const saved = await prisma.savedApplicant.upsert({
      where:  { applyId },
      create: { employerId, applyId },
      update: {},
    });

    return res.json({ saved });
  } catch (err) {
    console.error("POST /employer/applicants/:applyId/save error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /employer/applicants/:applyId/save
// Gespeicherten Bewerber entfernen
// ─────────────────────────────────────────────
router.delete("/applicants/:applyId/save", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    await prisma.savedApplicant.deleteMany({
      where: { employerId, applyId },
    });

    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /employer/applicants/:applyId/save error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/saved-applicants
// Alle gespeicherten Bewerber des Arbeitgebers
// ─────────────────────────────────────────────
router.get("/saved-applicants", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const saved = await prisma.savedApplicant.findMany({
      where:   { employerId },
      include: {
        apply: {
          include: {
            user: {
              select: {
                id: true, firstName: true, lastName: true,
                worker: { select: { profilePhotoUrl: true, bio: true, jobInterests: true } },
              },
            },
            job: {
              select: { id: true, title: true, company: true, category: true,
                        logoEmoji: true, location: true, startTime: true, payText: true },
            },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const result = saved.map((s) => ({
      savedId:    s.id,
      applyId:    s.applyId,
      savedAt:    s.createdAt,
      workerName: `${s.apply.user?.firstName ?? ""} ${s.apply.user?.lastName ?? ""}`.trim() || "Unknown",
      workerPhoto: s.apply.user?.worker?.profilePhotoUrl ?? null,
      bio:         s.apply.user?.worker?.bio ?? null,
      jobInterests: s.apply.user?.worker?.jobInterests ?? [],
      applyStatus: s.apply.status,
      jobId:       s.apply.job?.id ?? "",
      jobTitle:    s.apply.job?.title ?? "—",
      company:     s.apply.job?.company ?? "—",
      logoEmoji:   s.apply.job?.logoEmoji ?? "🏢",
      location:    s.apply.job?.location ?? "—",
      shiftDate:   s.apply.job?.startTime ?? null,
      payText:     s.apply.job?.payText ?? "—",
    }));

    return res.json(result);
  } catch (err) {
    console.error("GET /employer/saved-applicants error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/calendar
// Alle Jobs des Arbeitgebers mit Schicht-Zeiten + Staffing-Zahlen
// ─────────────────────────────────────────────
router.get("/calendar", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const jobs = await prisma.job.findMany({
      where: {
        employerId,
        status: { in: ["published", "inProgress", "completed"] },
        startTime: { not: null },
      },
      select: {
        id: true,
        title: true,
        location: true,
        logoEmoji: true,
        startTime: true,
        endTime: true,
        openSpots: true,
        status: true,
        applies: {
          where: { status: "accepted" },
          select: { id: true },
        },
      },
      orderBy: { startTime: "asc" },
    });

    const result = jobs.map((j) => ({
      id:            j.id,
      title:         j.title,
      location:      j.location,
      logoEmoji:     j.logoEmoji ?? "🏢",
      startTime:     j.startTime,
      endTime:       j.endTime,
      openSpots:     j.openSpots ?? 1,
      assignedCount: j.applies.length,
      status:        j.status,
    }));

    return res.json(result);
  } catch (err) {
    console.error("GET /employer/calendar error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// PATCH /employer/profile
// Speichert Company Info Tab + Your Profile Tab
// ─────────────────────────────────────────────
router.patch("/profile", requireAuth, async (req, res) => {
  try {
    const userId = req.auth.sub;

    const {
      // Company Info
      companyName, companySize, companyPhone, companyEmail,
      businessAreas, locations, primaryHiringLocation,
      companyBio, website, teamMembers, profilePhotoUrl,
      // Your Profile
      firstName, lastName, jobTitle, managerRole,
    } = req.body;

    // User-Felder
    const userUpdate = {};
    if (firstName !== undefined) userUpdate.firstName = firstName;
    if (lastName  !== undefined) userUpdate.lastName  = lastName;
    if (Object.keys(userUpdate).length > 0) {
      await prisma.user.update({ where: { id: userId }, data: userUpdate });
    }

    // Employer-Felder
    const employerUpdate = {};
    if (companyName           !== undefined) employerUpdate.companyName           = companyName;
    if (companySize           !== undefined) employerUpdate.companySize           = companySize;
    if (companyPhone          !== undefined) employerUpdate.companyPhone          = companyPhone ?? null;
    if (companyEmail          !== undefined) employerUpdate.companyEmail          = companyEmail ?? null;
    if (businessAreas         !== undefined) {
      employerUpdate.businessAreas = businessAreas ?? [];
      employerUpdate.industry = Array.isArray(businessAreas) && businessAreas.length > 0
        ? businessAreas.join(", ")
        : "";
    }
    if (locations             !== undefined) employerUpdate.locations             = locations ?? [];
    if (primaryHiringLocation !== undefined) employerUpdate.primaryHiringLocation = primaryHiringLocation ?? null;
    if (companyBio            !== undefined) employerUpdate.companyDescription    = companyBio ?? null;
    if (website               !== undefined) employerUpdate.websiteOrInstagram    = website ?? null;
    if (teamMembers           !== undefined) employerUpdate.teamMembers           = teamMembers ?? null;
    if (jobTitle              !== undefined) employerUpdate.jobTitle              = jobTitle ?? null;
    if (managerRole           !== undefined) employerUpdate.managerRole           = managerRole ?? null;
    if (profilePhotoUrl       !== undefined) employerUpdate.companyLogoUrl        = profilePhotoUrl ?? null;

    if (Object.keys(employerUpdate).length > 0) {
      await prisma.employer.upsert({
        where:  { userId },
        update: employerUpdate,
        create: {
          userId,
          companyName:  employerUpdate.companyName  ?? "",
          companySize:  employerUpdate.companySize  ?? "1-10",
          industry:     employerUpdate.industry     ?? "",
          ...employerUpdate,
        },
      });
    }

    return res.json({ ok: true });
  } catch (err) {
    console.error("PATCH /employer/profile error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
