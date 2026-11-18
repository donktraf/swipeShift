// src/routes.worker.js

const express = require("express");
const events = require("./notifyEvents");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { resolvePeriod, prismaRange, currentWeekRange } = require("./utils/period");
const { payPerWorker, shiftHours } = require("./utils/jobCost");
const { distanceMilesBetween } = require("./utils/haversine");
const { companyJobsWhere, truncateText } = require("./utils/companyStats");
const { jobNotesForApply } = require("./utils/jobNotes");
const { lastCompanyActivity } = require("./utils/savedCompanyDates");
const { deriveApplicationStatus } = require("./utils/applicationStatus");
const { reviewOverall, summarizeEmployerReviews, computeWouldWorkAgain, validateWorkerReviewBody } = require("./utils/reviewLogic");

const EARNINGS_LIST_LIMIT = 100;

const router = express.Router();

// ─────────────────────────────────────────────
// GET /worker/applications
// Alle Bewerbungen des eingeloggten Workers
// ─────────────────────────────────────────────
router.get("/applications", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const now      = new Date();

    // Worker-Standort fuer die Entfernungsangabe (Kalender-Detail)
    const me = await prisma.user.findUnique({ where: { id: workerId }, select: { lat: true, lng: true } });

    const applies = await prisma.apply.findMany({
      where:   { userId: workerId },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            location: true, payText: true, shiftText: true, lat: true, lng: true,
            startTime: true, endTime: true, category: true,
            status: true, cancellationReason: true, payAmount: true, jobNotes: true,
          },
        },
        conversation: { select: { id: true } },
      },
      orderBy: { createdAt: "desc" },
    });

    const applications = applies.map((a) => {
      const job = a.job;
      // Status inkl. storniertem Job, Stornierungsgrund und Zahlungsstatus (utils/applicationStatus.js)
      const { displayStatus, cancellationKind, cancellationReason, paymentStatus } =
        deriveApplicationStatus(a, job, now);

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
        cancellationKind,
        cancellationReason,
        paymentStatus,
        // Hinweise des Employers (nur bei offener/angenommener Bewerbung, utils/jobNotes.js)
        jobNotes:       jobNotesForApply(a.status, job?.jobNotes),
        // Verdienst fuer diese Schicht (gleiche Formel wie Finanz-Uebersicht)
        earnings:       job ? payPerWorker(job) : 0,
        // Entfernung Worker → Job in Meilen (null ohne Koordinaten)
        distanceMiles:  distanceMilesBetween(me?.lat, me?.lng, job?.lat, job?.lng),
        // Chat erst nach Annahme sinnvoll — die Conversation existiert aber ab Bewerbung
        conversationId: a.conversation?.id ?? null,
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

    const me = await prisma.user.findUnique({ where: { id: workerId }, select: { lat: true, lng: true } });

    const saves = await prisma.save.findMany({
      where:   { userId: workerId },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            location: true, payText: true, shiftText: true, category: true,
            tags: true, lat: true, lng: true, status: true, openSpots: true, startTime: true,
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

      // Bewerben nur, wenn noch nicht beworben (egal welcher Status), der Job offen ist,
      // noch freie Plaetze hat und noch nicht gestartet ist (sonst kaeme sofort SHIFT_TAKEN/JOB_UNAVAILABLE)
      const j = s.job;
      const canApply = applyStatus === undefined && j?.status === "published"
        && (j.openSpots ?? 1) > 0
        && (!j.startTime || new Date(j.startTime) > new Date());

      return {
        id:            s.id,
        jobId:         s.jobId,
        category:      s.job?.category  ?? null,
        tags:          s.job?.tags      ?? [],
        distanceMiles: distanceMilesBetween(me?.lat, me?.lng, s.job?.lat, s.job?.lng),
        canApply,
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
              select: { title: true, category: true, startTime: true, logoEmoji: true, company: true },
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
      companyName:   r.apply.job?.company ?? "Unknown Company",
      jobType:       r.apply.job?.category ?? "—",
      date:          r.createdAt,
      communication: r.communication,
      teamwork:      r.teamwork,
      reliability:   r.reliability,
      underPressure: r.underPressure,
      workQuality:   r.workQuality, // null bei Bestandsbewertungen
      overall:       reviewOverall(r),
      topWorker:     r.topWorker,
      feedback:      r.comment ?? "",
      wouldRehire:   r.wouldRehire,
    }));

    // Durchschnitte nur ueber vorhandene Werte (workQuality kann null sein)
    const summary = summarizeEmployerReviews(reviews);

    return res.json({
      reviews:        mapped,
      overallRating:  summary.overallRating ?? 0,
      totalJobs:      mapped.length,
      skillAverages:  summary.ratings, // null wenn keine Bewertungen
      topWorkerCount: summary.topWorkerCount,
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
      wouldWorkAgain,
      comment,
    } = req.body;

    const consentError = validateWorkerReviewBody(req.body);
    if (consentError) return res.status(400).json({ error: consentError });

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
      include: { job: { select: { employerId: true, status: true, endTime: true } } },
    });
    if (!apply) return res.status(404).json({ error: "Application not found" });
    // Gleiche Regel wie Job Applications/Kalender: nur angenommene, abgeschlossene Jobs sind bewertbar
    if (deriveApplicationStatus(apply, apply.job).displayStatus !== "completed") {
      return res.status(400).json({ error: "You can rate an employer once the job is completed." });
    }

    const existingReview = await prisma.workerReview.findUnique({ where: { applyId }, select: { id: true } });
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
        wouldWorkAgain,
        comment:               comment ?? null,
      },
      update: {
        communication,
        paymentFairness,
        workEnvironment,
        jobDescriptionAccuracy,
        overallExperience,
        wouldWorkAgain,
        comment: comment ?? null,
      },
    });

    // Nur bei neuer Bewertung (nicht beim Bearbeiten) benachrichtigen; fire-and-forget
    if (!existingReview) events.reviewReceived({ fromUserId: workerId, toUserId: apply.job?.employerId, jobId: apply.jobId });
    return res.json({ ok: true, review });
  } catch (err) {
    if (err?.code === "P2002") return res.status(409).json({ error: "You have already rated this employer." });
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
        // Stornierte Jobs bringen keinen Verdienst
        job: { status: { not: "cancelled" }, ...(startTimeRange ? { startTime: startTimeRange } : {}) },
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

    // "This week": Verdienst der laufenden Woche Mo–So (in SERVER-Lokalzeit, nicht Geraetezeit),
    // unabhaengig vom gewaehlten Zeitraum.
    // Gleiche Formel (payPerWorker), stornierte Jobs zaehlen nicht.
    const weekApplies = await prisma.apply.findMany({
      where: {
        userId: workerId,
        status: "accepted",
        job: { status: { not: "cancelled" }, startTime: prismaRange(currentWeekRange(now)) },
      },
      include: { job: { select: { payAmount: true, startTime: true, endTime: true } } },
    });
    const thisWeekEarnings = weekApplies.reduce((sum, a) => sum + (a.job ? payPerWorker(a.job) : 0), 0);

    // Gleiche Rechnung wie beim Employer (Stundenlohn × Schichtstunden, utils/jobCost.js)
    const calcEarning = (a) => (a.job ? payPerWorker(a.job) : 0);

    const upcoming   = applies.filter((a) => a.job?.startTime && new Date(a.job.startTime) > now);
    const completed  = applies.filter((a) => a.job?.endTime   && new Date(a.job.endTime)   <= now);
    const paidOutArr = completed.filter((a) => a.isPaid);

    const upcomingEarnings   = upcoming.reduce((s, a) => s + calcEarning(a), 0);
    const completedEarnings  = completed.reduce((s, a) => s + calcEarning(a), 0);
    const paidOut            = paidOutArr.reduce((s, a) => s + calcEarning(a), 0);

    // Neueste Schichten zuerst, max. EARNINGS_LIST_LIMIT; total = Anzahl im Zeitraum (fuer "Showing latest N")
    const sortedApplies = [...applies].sort(
      (a, b) => (b.job?.startTime ? new Date(b.job.startTime).getTime() : 0) - (a.job?.startTime ? new Date(a.job.startTime).getTime() : 0)
    );
    const earningsList = sortedApplies.slice(0, EARNINGS_LIST_LIMIT).map((a) => ({
      id:        a.id,
      // Stundenlohn × Stunden = amount (utils/jobCost.js); startTime fuer die Monatsgruppierung
      hourlyRate: a.job?.payAmount ?? null,
      hours:      a.job ? shiftHours(a.job) : null,
      startTime:  a.job?.startTime ?? null,
      isPaid:     a.isPaid,
      jobTitle:  a.job?.title     ?? "—",
      company:   a.job?.company   ?? "—",
      logoEmoji: a.job?.logoEmoji ?? "🏢",
      shiftText: a.job?.shiftText ?? "—",
      amount:    calcEarning(a),
      status:    a.job?.startTime && new Date(a.job.startTime) > now ? "upcoming" : "completed",
    }));

    return res.json({ upcomingEarnings, completedEarnings, paidOut, thisWeekEarnings, earningsTotal: applies.length, earningsList });
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
            where:  companyJobsWhere(sc.companyName),
            select: { logoEmoji: true, isVerified: true, status: true, location: true, employerId: true, createdAt: true },
            orderBy: { createdAt: "desc" },
          }),
          prisma.workerReview.findMany({
            where:  { apply: { job: companyJobsWhere(sc.companyName) } },
            select: { overallExperience: true },
          }),
        ]);
        return { sc, jobs, reviews };
      })
    );

    // Angenommene Jobs des Workers in EINER Abfrage (fuer "Last worked"), danach je Firma zugeordnet
    const acceptedApplies = savedList.length
      ? await prisma.apply.findMany({
          where:  { userId, status: "accepted" },
          select: { job: { select: { company: true, status: true, startTime: true, endTime: true } } },
        })
      : [];

    // Employer-Profile aller gespeicherten Firmen in EINER Abfrage (statt eine pro Firma)
    const employerIds = [...new Set(enriched.flatMap(({ jobs }) => {
      const id = jobs.find((j) => j.employerId)?.employerId;
      return id ? [id] : [];
    }))];
    const employers = employerIds.length
      ? await prisma.employer.findMany({
          where:  { userId: { in: employerIds } },
          select: { userId: true, industry: true, companyDescription: true },
        })
      : [];
    const employerByUser = new Map(employers.map((e) => [e.userId, e]));

    const savedCompanies = enriched.map(({ sc, jobs, reviews }) => {
      const openJobs  = jobs.filter((j) => j.status === "published").length;
      const logoEmoji = jobs[0]?.logoEmoji ?? "🏢";
      const isVerified = jobs[0]?.isVerified ?? false;
      // Standort = Ort des juengsten offenen Jobs (sonst irgendeines Jobs); Branche/Beschreibung aus dem Employer-Profil
      const location = (jobs.find((j) => j.status === "published") ?? jobs[0])?.location ?? null;
      const employer = employerByUser.get(jobs.find((j) => j.employerId)?.employerId);
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
        location,
        industry:    employer?.industry || null,
        about:       truncateText(employer?.companyDescription, 140),
        savedAt:     sc.savedAt,
        // "Last worked" (juengster vergangener Job mit angenommener Bewerbung) sonst "Last posted"
        lastActivity: lastCompanyActivity(
          acceptedApplies
            .filter((a) => a.job?.company?.toLowerCase() === sc.companyName.toLowerCase())
            .map((a) => a.job),
          jobs,
        ),
      };
    });

    return res.json({ savedCompanies });
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
