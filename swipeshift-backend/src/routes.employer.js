// src/routes.employer.js

const express = require("express");
const events = require("./notifyEvents");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { resolvePeriod, isInPeriod, buildBuckets } = require("./utils/period");
const { jobCosts, shiftHours } = require("./utils/jobCost");
const { bookedShifts, bookedSpan, describeBooked, fullShiftIds, jobShifts, shiftCoverage } = require("./utils/shiftBooking");
const fees = require("./utils/fees");
const { roundMoney } = fees;
const { mergeConsents, allowedKeysForRole } = require("./utils/consents");
const { validateDraftData, validateReviewSubmission, reviewOverall } = require("./utils/reviewLogic");
const { validateEmployerProfileFields, cleanExperience, cleanWhitelist, AVAILABLE_TIMES, SHIFT_TYPES } = require("./utils/profileFields");
const { Prisma } = require("@prisma/client");
const { loadApplicantSummaries } = require("./applicantSummaries");
const { countEmployerApplies } = require("./utils/applyCounts");
const { averageRating } = require("./utils/applicantSummary");
const { truncateText } = require("./utils/companyStats");
const { computeScheduleConflicts } = require("./utils/scheduleConflict");
const { buildPastJobs, buildAccountStatus, buildMatchHint } = require("./utils/workerDetail");
const { ageFromBirthDate, availableDays, summarizeReviews, summarizeCompletedJobs, cleanSelfRatedSkills, stringList } = require("./utils/workerProfile");

const { visibleApplyFilter, isRestricted } = require("./utils/moderation");
const rel = require("./utils/reliability");
const { loadReliability, recordEmployerAttendance } = require("./reliability");
const RESTRICTION_FIELDS = { bannedAt: true, suspendedUntil: true, suspensionReason: true };

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
      select: { id: true, title: true, payText: true, shiftText: true, location: true, logoEmoji: true, startTime: true, endTime: true, shifts: true },
    });
    // Optional: nur ein Job (Schnellaktion "View Applicants"). Nur eigene Jobs → fremde jobId liefert nichts.
    const onlyJobId = typeof req.query.jobId === "string" && req.query.jobId ? req.query.jobId : null;
    const jobIds  = myJobs.filter((j) => !onlyJobId || j.id === onlyJobId).map((j) => j.id);
    const jobMap  = Object.fromEntries(myJobs.map((j) => [j.id, j]));

    if (!jobIds.length) return res.json({ applicants: [] });

    // Alle Bewerbungen für diese Jobs
    const applies = await prisma.apply.findMany({
      // Offene Bewerbungen gesperrter/gebannter Worker sind ausgeblendet
      // (vom Worker stornierte Schichten erscheinen hier nicht mehr)
      where:   { jobId: { in: jobIds }, status: { in: rel.LISTED_STATUSES }, ...visibleApplyFilter() },
      orderBy: { createdAt: "desc" },
      include: { conversation: { select: { id: true } } },
    });

    // User-Daten laden
    const userIds = [...new Set(applies.map((a) => a.userId))];
    const users   = await prisma.user.findMany({
      where:  { id: { in: userIds } },
      select: { id: true, firstName: true, lastName: true, location: true },
      // profilePhotoUrl liegt nur am Worker (siehe workerPhotoMap unten)
    });

    // Worker-Profil (für profilePhotoUrl)
    const workers = await prisma.worker.findMany({
      where:  { userId: { in: userIds } },
      select: { userId: true, profilePhotoUrl: true },
    });
    const workerPhotoMap = Object.fromEntries(workers.map((w) => [w.userId, w.profilePhotoUrl]));

    const userMap = Object.fromEntries(users.map((u) => [u.id, u]));

    // Bewertungen/Jobzahlen/Profilfelder aller Bewerber gebuendelt (kein N+1)
    const summaries = await loadApplicantSummaries(userIds);

    // Zeitkonflikt: hat der Bewerber einen anderen angenommenen Job zur selben Zeit? (eine Query fuer alle)
    const acceptedApplies = await prisma.apply.findMany({
      where:  { userId: { in: userIds }, status: "accepted" },
      select: { id: true, userId: true, jobId: true, shiftIds: true, job: { select: { startTime: true, endTime: true, shifts: true, status: true } } },
    });
    // Nur fuer offene (pending) Bewerbungen relevant
    const conflicts = computeScheduleConflicts(
      applies.filter((a) => a.status === "pending").map((a) => ({ id: a.id, userId: a.userId, jobId: a.jobId, shiftIds: a.shiftIds, job: jobMap[a.jobId] })),
      acceptedApplies,
    );

    const applicants = applies.map((a) => ({
      applyId:       a.id,
      hasScheduleConflict: conflicts.has(a.id),
      userId:        a.userId,
      appliedAt:     a.createdAt,
      status:        a.status,
      autoAccepted:  a.autoAccepted === true,
      // Conversation entsteht schon beim Bewerben; die App zeigt den Chat-Button erst nach Annahme
      conversationId: a.conversation?.id ?? null,
      summary:       summaries.get(a.userId) ?? null,
      // Gebuchte Schichten dieses Bewerbers (Altbestand ohne Auswahl = alle Schichten des Jobs)
      bookedShifts:  jobMap[a.jobId] ? describeBooked(jobMap[a.jobId], a.shiftIds) : [],
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

    // Optionaler Job-Kontext fuer den Match-Hinweis — nur, wenn der Job diesem Arbeitgeber gehoert
    const jobId = typeof req.query.jobId === "string" ? req.query.jobId : null;
    const contextJob = jobId
      ? await prisma.job.findFirst({
          where: { id: jobId, employerId },
          select: { category: true, requiredSkills: true, workAuthorizationRequired: true, minAge: true, startTime: true, endTime: true, shifts: true },
        })
      : null;

    const hasApplied = await prisma.apply.findFirst({
      where: { userId, job: { employerId } },
      select: { id: true },
    });
    const contextApply = jobId && contextJob
      ? await prisma.apply.findFirst({ where: { userId, jobId, job: { employerId } }, select: { shiftIds: true } })
      : null;
    if (!hasApplied) return res.status(404).json({ error: "Worker not found" });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: {
        id: true, firstName: true, lastName: true, location: true, emailVerifiedAt: true,
        pausedAt: true, createdAt: true, bannedAt: true,
        worker: {
          select: {
            dateOfBirth: true, bio: true, profilePhotoUrl: true, jobInterests: true, availability: true,
            willingToRelocate: true, maxTravelDistance: true, transport: true, availableForSameDay: true,
            preferredCategories: true, payRangeMin: true, payRangeMax: true, skills: true,
            workAuthorization: true, availableTimes: true, shiftTypes: true, experience: true,
          },
        },
      },
    });
    if (!user || user.bannedAt) return res.status(404).json({ error: "Worker not found" }); // gebannt = nicht mehr abrufbar

    const [reviews, applies, reliabilityMap] = await Promise.all([
      prisma.review.findMany({
        where: { workerId: userId },
        orderBy: { createdAt: "desc" },
        select: {
          communication: true, teamwork: true, reliability: true, underPressure: true, workQuality: true,
          topWorker: true, wouldRehire: true, comment: true, createdAt: true,
          apply: { select: { job: { select: { title: true } } } },
        },
      }),
      prisma.apply.findMany({
        where: { userId },
        select: {
          status: true, isPaid: true, shiftIds: true,
          // fuer Past Jobs: Firma/Titel/Datum + die Bewertung, die der Employer dieses Jobs vergeben hat (ohne Kommentar)
          review: { select: { communication: true, teamwork: true, reliability: true, underPressure: true, workQuality: true } },
          job: { select: { title: true, company: true, startTime: true, category: true, endTime: true, shifts: true, status: true, cancellationReason: true } },
        },
      }),
      loadReliability([userId]), // Anwesenheit / No-Shows / kurzfristige Stornos
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
        availableTimes: cleanWhitelist(w?.availableTimes, AVAILABLE_TIMES),
        shiftTypes: cleanWhitelist(w?.shiftTypes, SHIFT_TYPES),
        experience: cleanExperience(w?.experience),
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
      pastJobs: buildPastJobs(applies.filter((a) => a.status === "accepted")),
      reliability: reliabilityMap.get(userId) ?? null,
      account: buildAccountStatus(user),
      matchHint: buildMatchHint(contextJob, w)?.text ?? null,
      // Mit ?jobId: die Schichten, die dieser Worker fuer genau diesen Job gebucht hat
      bookedShifts: contextJob && contextApply ? describeBooked(contextJob, contextApply.shiftIds) : null,
      recentReviews: reviews
        .filter((r) => r.comment && r.comment.trim())
        .slice(0, 3)
        .map((r) => ({
          comment: r.comment.trim(),
          jobTitle: r.apply?.job?.title ?? null,
          createdAt: r.createdAt,
          rating: summarizeReviews([r]).overallRating,
          wouldRehire: r.wouldRehire,
          topWorker: r.topWorker,
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
    const now = new Date();

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { employerId: true } }, user: { select: RESTRICTION_FIELDS } },
    });

    if (!apply)                              return res.status(404).json({ error: "Application not found" });
    if (apply.job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });
    if (isRestricted(apply.user))            return res.status(409).json({ error: "This worker is no longer available.", code: "WORKER_UNAVAILABLE" });
    if (apply.status === rel.CANCELLED_BY_WORKER) return res.status(409).json({ error: "The worker cancelled this shift.", code: "CANCELLED_BY_WORKER" });

    // Kapazitaet pro Schicht (openSpots gilt je Schicht): ist eine der gebuchten Schichten schon voll → 409 SHIFT_FULL,
    // keine Teil-Annahme. Serializable, damit zwei parallele Annahmen nicht beide den letzten Platz bekommen.
    if (apply.status !== "accepted") {
      const full = await prisma.$transaction(async (tx) => {
        const job = await tx.job.findUnique({ where: { id: apply.jobId }, select: { openSpots: true, startTime: true, endTime: true, shifts: true } });
        const accepted = await tx.apply.findMany({ where: { jobId: apply.jobId, status: "accepted" }, select: { id: true, shiftIds: true } });
        const booked = bookedShifts(job, apply.shiftIds);
        // Alle gebuchten Schichten haben schon begonnen → nicht mehr annehmbar
        if (booked.every((s) => s.startMs !== null && s.startMs <= now.getTime())) return { unavailable: true };
        const fullIds = fullShiftIds(job, booked.map((s) => s.id), accepted, applyId);
        if (fullIds.length) return { shifts: describeBooked(job, fullIds) };
        await tx.apply.update({
          where: { id: applyId },
          // respondedAt nur bei der ERSTEN Antwort setzen (Response Time = Zeit bis zur ersten Reaktion)
          data:  { status: "accepted", autoAccepted: false, ...(apply.respondedAt ? {} : { respondedAt: new Date() }) },
        });
        return null;
      }, { isolationLevel: "Serializable" }).catch((err) => {
        if (err?.code === "P2034") return { tryAgain: true };
        throw err;
      });
      if (full?.unavailable) return res.status(409).json({ error: "All booked shifts of this worker have already started.", code: "SHIFT_UNAVAILABLE" });
      if (full?.tryAgain) return res.status(409).json({ error: "Please try again.", code: "TRY_AGAIN" });
      if (full) {
        return res.status(409).json({ error: "One of this worker's shifts is already fully staffed.", code: "SHIFT_FULL", shifts: full.shifts });
      }
    } else {
      // Bereits angenommen (z.B. Instant Match): Annahme bestaetigen → nicht mehr "auto"
      await prisma.apply.update({
        where: { id: applyId },
        data:  { status: "accepted", autoAccepted: false, ...(apply.respondedAt ? {} : { respondedAt: new Date() }) },
      });
    }
    if (apply.status !== "accepted") events.applicationDecided(applyId, "accepted"); // fire-and-forget
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
    if (apply.status === rel.CANCELLED_BY_WORKER) return res.status(409).json({ error: "The worker cancelled this shift.", code: "CANCELLED_BY_WORKER" });

    await prisma.apply.update({
      where: { id: applyId },
      data:  { status: "declined", autoAccepted: false, ...(apply.respondedAt ? {} : { respondedAt: new Date() }) },
    });
    if (apply.status !== "declined") events.applicationDecided(applyId, "declined"); // fire-and-forget
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
        startTime: true, endTime: true, shifts: true, platformFeePercent: true,
        applies: { where: { status: "accepted" }, select: { isPaid: true, shiftIds: true, attendance: true, disputedAt: true, disputeResolvedAt: true } },
      },
    });
    const myJobIds = myJobs.map((j) => j.id);

    const activeJobs = myJobs.filter((j) => j.status === "published").length;

    const allApplies = myJobIds.length
      ? await prisma.apply.findMany({
          where:  { jobId: { in: myJobIds }, ...visibleApplyFilter() },
          select: { id: true, createdAt: true, status: true, autoAccepted: true },
        })
      : [];

    // Auto-angenommene (Instant Match) zaehlen nicht als "zu beantworten" (siehe utils/applyCounts.js)
    const { newApplicants, applicationsThisWeek: applicationsWeek, instantMatchesThisWeek } =
      countEmployerApplies(allApplies, now);

    const completedThisMonth = myJobs.filter(
      (j) => j.status === "completed" && j.startTime && new Date(j.startTime) >= monthStart
    );
    // Gleiche Formel wie Finanz-Uebersicht + Payment-Screen (Stundenlohn × Stunden × Worker);
    // monthlySpend = Gesamt inkl. Plattform-Gebuehr (was der Employer tatsaechlich zahlt)
    const monthCosts = completedThisMonth.map((j) => jobCosts(j, j.applies));
    const monthlySpend      = roundMoney(monthCosts.reduce((s, c) => s + c.completedTotal, 0));
    const monthlySpendWages = roundMoney(monthCosts.reduce((s, c) => s + c.completed, 0));
    const monthlySpendFees  = roundMoney(monthCosts.reduce((s, c) => s + c.completedFee, 0));

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
      monthlySpendWages,
      monthlySpendFees,
      applicationsThisWeek: applicationsWeek,
      instantMatchesThisWeek,
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
        openSpots: true, startTime: true, endTime: true, shifts: true, platformFeePercent: true,
        shiftText: true, logoEmoji: true, category: true,
        applies: { where: { status: "accepted" }, select: { isPaid: true, shiftIds: true, attendance: true, disputedAt: true, disputeResolvedAt: true } },
      },
      orderBy: { startTime: "desc" },
    });

    // Kosten pro Job: Stundenlohn × Stunden × Worker (siehe utils/jobCost.js)
    const costOf = new Map(myJobs.map(j => [j.id, jobCosts(j, j.applies)]));
    const cost   = (j) => costOf.get(j.id);
    const sum    = (jobs, key) => roundMoney(jobs.reduce((s, j) => s + cost(j)[key], 0));

    // Alle Betraege inkl. Plattform-Gebuehr ("…Total") — Lohn und Gebuehr zusaetzlich getrennt (…Wages/…Fees)
    const monthJobs = myJobs.filter(j => j.status === "completed" && j.startTime && new Date(j.startTime) >= monthStart);
    // Monthly Spend unabhaengig vom gewaehlten Zeitraum (wie im Dashboard)
    const monthlySpend      = sum(monthJobs, "completedTotal");
    const monthlySpendWages = sum(monthJobs, "completed");
    const monthlySpendFees  = sum(monthJobs, "completedFee");

    // "Upcoming" = veroeffentlicht UND Schicht in der Zukunft — gleiche Regel fuer Kachel,
    // Liste und Diagramm (vergangene, nie abgeschlossene Jobs zaehlen nicht als offene Zahlung)
    const isUpcoming = (j) => j.status === "published" && j.startTime && new Date(j.startTime) > now;

    const periodJobs    = myJobs.filter(j => isInPeriod(j.startTime, range));
    const completedJobs = periodJobs.filter(j => j.status === "completed");
    const upcomingJobs  = periodJobs.filter(isUpcoming).reverse(); // naechste zuerst

    // "Total Spending" = Gesamt inkl. Gebuehr (inkl. bereits bezahlter Worker)
    const totalSpending    = sum(completedJobs, "completedTotal");
    const totalWages       = sum(completedJobs, "completed");
    const totalFees        = sum(completedJobs, "completedFee");
    const upcomingPayments = sum(upcomingJobs, "plannedTotal");
    const upcomingWages    = sum(upcomingJobs, "planned");
    const upcomingFees     = sum(upcomingJobs, "plannedFee");
    const paidOut          = sum(periodJobs, "paidOutTotal");
    const paidOutWages     = sum(periodJobs, "paidOut");
    const paidOutFees      = sum(periodJobs, "paidOutFee");

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
        upcoming:  sum(inBucket.filter(isUpcoming), "plannedTotal"),
        completed: Math.max(0, roundMoney(sum(done, "completedTotal") - sum(done, "paidOutTotal"))),
        paidOut:   sum(inBucket, "paidOutTotal"),
      };
    });

    // Kategorien-Aufschlüsselung
    const byCategory = {};
    completedJobs.forEach(j => {
      const cat = j.category ?? "Other";
      byCategory[cat] = roundMoney((byCategory[cat] ?? 0) + cost(j).completedTotal);
    });

    // status: upcoming | completed | paid (alle angenommenen Worker bezahlt)
    const toListItem = (kind) => (j) => {
      const payable = rel.billable(j.applies); // endgueltige No-Shows werden nicht bezahlt
      const fullyPaid = payable.length > 0 && payable.every(a => a.isPaid);
      return {
        id:        j.id,
        title:     j.title,
        logoEmoji: j.logoEmoji,
        shiftText: j.shiftText,
        amount:    kind === "upcoming" ? cost(j).plannedTotal : cost(j).completedTotal, // inkl. Gebuehr
        wages:     kind === "upcoming" ? cost(j).planned      : cost(j).completed,
        fee:       kind === "upcoming" ? cost(j).plannedFee   : cost(j).completedFee,
        status:    kind === "completed" && fullyPaid ? "paid" : kind,
      };
    };

    return res.json({
      period:             range.period,
      totalSpending,
      totalWages,
      totalFees,
      upcomingPayments,
      upcomingWages,
      upcomingFees,
      completedJobsCount: completedJobs.length,
      paidOut,
      paidOutWages,
      paidOutFees,
      monthlySpend,
      monthlySpendWages,
      monthlySpendFees,
      platformFeePercent: fees.platformFeePercent(), // aktueller Default; einzelne Jobs koennen ihren eingefrorenen Satz haben
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
    if (apply.status === rel.CANCELLED_BY_WORKER) return res.status(409).json({ error: "The worker cancelled this shift.", code: "CANCELLED_BY_WORKER" });

    await prisma.apply.update({ where: { id: applyId }, data: { status: "pending", autoAccepted: false } });
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
        payAmount: true, startTime: true, endTime: true, platformFeePercent: true,
        applies: {
          where:  { status: "accepted" },
          select: {
            id:     true,
            userId: true,
            shiftIds: true,
            autoAccepted: true,
            user: {
              select: { id: true, firstName: true, lastName: true, ...RESTRICTION_FIELDS },
            },
          },
        },
      },
    });

    const result = jobs.map((job) => {
      // Kosten fuer die zugewiesenen Worker (Lohn + Gebuehr, utils/jobCost.js)
      const costs = jobCosts(job, job.applies);
      return {
      id:          job.id,
      title:       job.title,
      logoEmoji:   job.logoEmoji,
      feePercent:        costs.feePercent,
      costPerWorker:     costs.perWorkerTotal,   // Lohn + Gebuehr je Worker/Schicht
      costPerWorkerWage: costs.perWorker,
      costPerWorkerFee:  costs.perWorkerFee,
      assignedCost:      costs.completedTotal,   // fuer die aktuell zugewiesenen Worker
      category:    job.category ?? "",
      location:    job.location,
      openSpots:   job.openSpots,
      shifts:      Array.isArray(job.shifts) ? job.shifts : [],
      // Besetzung je Schicht: openSpots gilt pro Schicht (capacity), assigned = angenommene Worker, die sie gebucht haben
      shiftStaffing: (() => {
        const cov = shiftCoverage(job, job.applies);
        return jobShifts(job).map((s) => ({ id: s.id, date: s.date, timeRange: s.timeRange, assigned: cov.get(s.id) ?? 0, capacity: job.openSpots ?? 1 }));
      })(),
      assignedWorkers: job.applies.map((a) => ({
        applyId:     a.id,
        userId:      a.userId,
        autoAccepted: a.autoAccepted === true,
        bookedShifts: describeBooked(job, a.shiftIds), // gebuchte Schichten (Altbestand = alle)
        restricted:  isRestricted(a.user), // gesperrt/gebannt: bleibt sichtbar (Bezahlung), nur markiert
        name:        `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim(),
        photoEmoji:  "👤",
        rating:      0.0,
      })),
    };
    });

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
      select: { id: true, title: true, employerId: true, payAmount: true, startTime: true, endTime: true, shifts: true, logoEmoji: true, platformFeePercent: true },
    });

    if (!job)                              return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId)     return res.status(403).json({ error: "Forbidden" });

    const applies = await prisma.apply.findMany({
      where:   { jobId, status: "accepted" },
      include: { user: { select: { id: true, firstName: true, lastName: true, ...RESTRICTION_FIELDS } } },
      orderBy: { createdAt: "asc" },
    });

    const hourlyRate  = job.payAmount ?? 0;
    const feePercent  = jobCosts(job, []).feePercent;
    // Je Worker: Stunden/Lohn/Gebuehr seiner GEBUCHTEN Schichten (Apply.shiftIds, leer = alle), gleiche Rundung wie Finanz-Uebersicht
    const costsOf = (a) => {
      const c = jobCosts(job, [{ isPaid: false, shiftIds: a.shiftIds }]); // ohne Attendance → abrechenbar
      return { hours: shiftHours(job, a.shiftIds), wage: c.completed, fee: c.completedFee };
    };
    const shortDate = (d) => new Date(d).toLocaleDateString("en-US", { month: "short", day: "numeric" });

    const workers = applies.map((a) => {
      // No-Show (endgueltig) wird nicht berechnet → 0; sonst Lohn + Gebuehr (Worker erhaelt nur den Lohn)
      // Unter Einspruch: Betrag wird gezeigt, aber noch nicht berechnet (On hold, siehe summary.onHold…)
      const mine = costsOf(a);
      const wage = rel.isFinalNoShow(a) ? 0 : mine.wage;
      const fee  = rel.isFinalNoShow(a) ? 0 : mine.fee;
      const booked = describeBooked(job, a.shiftIds);
      const firstStart = booked.find((b) => b.startTime)?.startTime ?? job.startTime;
      const shiftLabel = firstStart ? shortDate(firstStart) : "—";
      return {
      id:          a.id,
      name:        `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown",
      avatarEmoji: "👤",
      jobTitle:    job.title,
      shiftDate:   shiftLabel,
      // Gebuchte Schichten dieses Workers ("Mon 12 · Tue 13" im Client aus date/startTime gebaut)
      bookedShifts: booked,
      bookedShiftCount: booked.length,
      totalShiftCount:  jobShifts(job).length,
      hoursWorked: mine.hours,
      // No-Show (endgueltig): nicht berechnet → Stundenlohn 0; bei offenem Einspruch noch nicht bezahlbar
      hourlyRate:  rel.isFinalNoShow(a) ? 0 : hourlyRate,
      paymentState: rel.paymentState(a), // paid | pending | no_show | under_review
      isPaid:      a.isPaid,
      restricted:  isRestricted(a.user), // bleibt bezahlbar, nur markiert
      wage, fee, total: roundMoney(wage + fee),
    };
    });

    // Job-Summen; "remaining" = Betrag, den "Pay all" jetzt faellig stellt (bezahlbar und noch offen)
    const sumOf = (list, key) => roundMoney(list.reduce((s, w) => s + w[key], 0));
    const payableUnpaid = workers.filter((w) => !w.isPaid && w.paymentState === "pending");
    const paidList      = workers.filter((w) => w.isPaid);
    const billed        = workers.filter((w) => w.paymentState !== "no_show" && w.paymentState !== "under_review");
    const heldList      = workers.filter((w) => w.paymentState === "under_review"); // gleiche Regel wie utils/jobCost.js (onHold)
    const summary = {
      feePercent,
      wages: sumOf(billed, "wage"),           fees: sumOf(billed, "fee"),           total: sumOf(billed, "total"),
      paidWages: sumOf(paidList, "wage"),     paidFees: sumOf(paidList, "fee"),     paidTotal: sumOf(paidList, "total"),
      remainingWages: sumOf(payableUnpaid, "wage"), remainingFees: sumOf(payableUnpaid, "fee"), remainingTotal: sumOf(payableUnpaid, "total"),
      onHoldWages: sumOf(heldList, "wage"),   onHoldFees: sumOf(heldList, "fee"),   onHoldTotal: sumOf(heldList, "total"),
    };

    return res.json({ workers, summary });
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
    if (rel.isNoShowUnderReview(apply)) return res.status(409).json({ error: "The worker disputed the no-show. Payment is on hold until our team has reviewed it.", code: "NO_SHOW_UNDER_REVIEW" });
    if (rel.isFinalNoShow(apply))       return res.status(409).json({ error: "This worker was recorded as a no-show and is not billed.", code: "NO_SHOW" });

    await prisma.apply.update({ where: { id: applyId }, data: { isPaid: true } });
    if (!apply.isPaid) events.paymentReceived([applyId]); // fire-and-forget
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

    // Nur frisch bezahlte Worker benachrichtigen; No-Shows (endgueltig oder unter Einspruch) werden uebersprungen
    const candidates = await prisma.apply.findMany({
      where: { jobId, status: "accepted", isPaid: false },
      select: { id: true, attendance: true, disputedAt: true, disputeResolvedAt: true },
    });
    const unpaid = candidates.filter(rel.isPayable);
    const { count } = await prisma.apply.updateMany({
      where: { jobId, status: "accepted", id: { in: unpaid.map((a) => a.id) } },
      data:  { isPaid: true },
    });
    events.paymentReceived(unpaid.map((a) => a.id)); // fire-and-forget

    return res.json({ ok: true, updatedCount: count });
  } catch (err) {
    console.error("POST /employer/jobs/:jobId/pay-all error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/jobs/:jobId/attendance
// Angenommene Worker eines Jobs mit Anwesenheits-Status (Erfassung nach Schichtende, 48-h-Fenster).
// Regeln: utils/reliability.js
// ─────────────────────────────────────────────
router.get("/jobs/:jobId/attendance", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { jobId }  = req.params;
    const now = new Date();

    const job = await prisma.job.findUnique({
      where:  { id: jobId },
      select: { id: true, title: true, employerId: true, status: true, startTime: true, endTime: true, shifts: true },
    });
    if (!job)                          return res.status(404).json({ error: "Job not found" });
    if (job.employerId !== employerId) return res.status(403).json({ error: "Forbidden" });

    const applies = await prisma.apply.findMany({
      where:   { jobId, status: "accepted" },
      include: { user: { select: { id: true, firstName: true, lastName: true } } },
      orderBy: { createdAt: "asc" },
    });

    const workers = applies.map((a) => {
      const state = rel.attendanceState(a, job, now);
      return {
        applyId:          a.id,
        userId:           a.userId,
        name:             `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown",
        attendance:       a.attendance ?? null,
        attendanceSource: a.attendanceSource ?? null,
        // Fenster richtet sich nach dem Ende der GEBUCHTEN Schichten dieses Workers
        ended:            state.ended,
        canRecord:        state.canRecord,
        pending:          state.pending,
        bookedShifts:     describeBooked(job, a.shiftIds),
        disputeStatus:    rel.disputeStatus(a),
        disputeNote:      a.disputedAt ? a.disputeNote : null,
      };
    });
    const state = rel.attendanceState({ status: "accepted" }, job, now);

    return res.json({
      job: { id: job.id, title: job.title, startTime: job.startTime, endTime: job.endTime },
      ended: state.ended || workers.some((w) => w.ended),
      deadline: state.deadline,
      guidance: rel.GUIDANCE_TEXT,
      workers,
    });
  } catch (err) {
    console.error("GET /employer/jobs/:id/attendance error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/applicants/:applyId/attendance  { status: "attended" | "late" | "no_show" }
// Nach Schichtende, bis 48 h danach bzw. bis der Worker widerspricht.
// ─────────────────────────────────────────────
router.post("/applicants/:applyId/attendance", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const result = await recordEmployerAttendance({
      applyId: req.params.applyId, employerId: req.auth.sub, value: req.body?.status,
    });
    if (!result.ok) return res.status(result.status).json({ error: result.error, code: result.code });
    return res.json({ ok: true, applyId: req.params.applyId, attendance: result.attendance });
  } catch (err) {
    console.error("POST /employer/applicants/:id/attendance error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// Worker-/Job-Infos fuer Pending-/Draft-Eintraege
const REVIEW_APPLY_INCLUDE = {
  user: { select: { id: true, firstName: true, lastName: true } },
  job:  { select: { id: true, title: true, category: true, startTime: true, endTime: true, shifts: true, logoEmoji: true } },
};

function mapReviewApply(a) {
  return {
    applyId:     a.id,
    workerId:    a.userId,
    workerName:  `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown Worker",
    workerPhoto: null,
    jobId:       a.jobId,
    jobTitle:    a.job?.title    ?? "—",
    jobCategory: a.job?.category ?? "—",
    // Start der GEBUCHTEN Schichten dieses Workers
    shiftDate:   (a.job ? bookedSpan(a.job, a.shiftIds).start : null) ?? a.createdAt,
    logoEmoji:   a.job?.logoEmoji ?? "🏢",
  };
}

// Gemeinsame Pruefung fuer POST /reviews und PUT /reviews/drafts/:applyId:
// Apply gehoert zu einem Job dieses Arbeitgebers, wurde angenommen und hat noch keine Bewertung.
// → { apply } | { status, error }
async function loadReviewableApply(applyId, employerId) {
  const apply = await prisma.apply.findUnique({
    where:   { id: applyId },
    include: { job: { select: { employerId: true } }, review: { select: { id: true } } },
  });
  if (!apply)                              return { status: 404, error: "Application not found" };
  if (apply.job.employerId !== employerId) return { status: 403, error: "Forbidden" };
  if (apply.status !== "accepted")         return { status: 400, error: "Only accepted workers can be reviewed" };
  if (apply.review)                        return { status: 409, error: "This worker has already been reviewed" };
  return { apply };
}

// ─────────────────────────────────────────────
// GET /employer/reviews/pending
// Akzeptierte Worker ohne Bewertung UND ohne Entwurf.
// Entscheidung: Eintraege mit Entwurf erscheinen nur im Drafts-Tab (nicht doppelt).
// ─────────────────────────────────────────────
router.get("/reviews/pending", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const applies = await prisma.apply.findMany({
      where: {
        status: "accepted",
        job:    { employerId },
        review: null,
        reviewDraft: null,
      },
      include: REVIEW_APPLY_INCLUDE,
      orderBy: { createdAt: "desc" },
    });

    return res.json({ pending: applies.map(mapReviewApply) });
  } catch (err) {
    console.error("GET /employer/reviews/pending error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /employer/reviews/drafts
// Gespeicherte Entwuerfe (nur fuer Applies ohne endgueltige Bewertung)
// ─────────────────────────────────────────────
router.get("/reviews/drafts", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;

    const drafts = await prisma.reviewDraft.findMany({
      where:   { employerId, apply: { review: null, job: { employerId } } },
      include: { apply: { include: REVIEW_APPLY_INCLUDE } },
      orderBy: { updatedAt: "desc" },
    });

    return res.json({
      drafts: drafts.map((d) => {
        const parsed = validateDraftData(d.data);
        return {
          ...mapReviewApply(d.apply),
          draft:     parsed.ok ? parsed.data : {},
          updatedAt: d.updatedAt,
        };
      }),
    });
  } catch (err) {
    console.error("GET /employer/reviews/drafts error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// PUT /employer/reviews/drafts/:applyId
// Entwurf anlegen/ueberschreiben (upsert)
// ─────────────────────────────────────────────
router.put("/reviews/drafts/:applyId", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { applyId } = req.params;

    const parsed = validateDraftData(req.body);
    if (!parsed.ok) return res.status(400).json({ error: parsed.error });

    const check = await loadReviewableApply(applyId, employerId);
    if (check.error) return res.status(check.status).json({ error: check.error });

    const draft = await prisma.reviewDraft.upsert({
      where:  { applyId },
      create: { applyId, employerId, data: parsed.data },
      update: { data: parsed.data },
    });

    return res.json({ ok: true, draft: { applyId, draft: parsed.data, updatedAt: draft.updatedAt } });
  } catch (err) {
    console.error("PUT /employer/reviews/drafts/:applyId error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// DELETE /employer/reviews/drafts/:applyId
// ─────────────────────────────────────────────
router.delete("/reviews/drafts/:applyId", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const { count } = await prisma.reviewDraft.deleteMany({
      where: { applyId: req.params.applyId, employerId },
    });
    if (!count) return res.status(404).json({ error: "Draft not found" });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /employer/reviews/drafts/:applyId error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /employer/reviews
// Bewertung einreichen (loescht einen vorhandenen Entwurf in derselben Transaktion)
// ─────────────────────────────────────────────
router.post("/reviews", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const employerId = req.auth.sub;
    const applyId = req.body?.applyId;
    if (!applyId || typeof applyId !== "string") {
      return res.status(400).json({ error: "Missing required fields" });
    }

    const parsed = validateReviewSubmission(req.body);
    if (!parsed.ok) return res.status(400).json({ error: parsed.error });

    const check = await loadReviewableApply(applyId, employerId);
    if (check.error) return res.status(check.status).json({ error: check.error });
    const { apply } = check;

    const [review] = await prisma.$transaction([
      prisma.review.create({
        data: {
          employerId,
          workerId: apply.userId,
          jobId:    apply.jobId,
          applyId,
          ...parsed.data,
        },
      }),
      prisma.reviewDraft.deleteMany({ where: { applyId } }),
    ]);

    events.reviewReceived({ fromUserId: employerId, toUserId: apply.userId, jobId: apply.jobId }); // fire-and-forget
    return res.json({ ok: true, review });
  } catch (err) {
    if (err?.code === "P2002") return res.status(409).json({ error: "This worker has already been reviewed." });
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
      include: { apply: { include: REVIEW_APPLY_INCLUDE } },
      orderBy: { createdAt: "desc" },
    });

    const result = reviews.map((r) => ({
      id:            r.id,
      workerName:    `${r.apply.user?.firstName ?? ""} ${r.apply.user?.lastName ?? ""}`.trim() || "Unknown",
      workerPhoto:   null,
      jobTitle:      r.apply.job?.title    ?? "—",
      jobCategory:   r.apply.job?.category ?? "—",
      logoEmoji:     r.apply.job?.logoEmoji ?? "🏢",
      shiftDate:     (r.apply.job ? bookedSpan(r.apply.job, r.apply.shiftIds).start : null) ?? r.createdAt,
      communication: r.communication,
      teamwork:      r.teamwork,
      reliability:   r.reliability,
      underPressure: r.underPressure,
      workQuality:   r.workQuality,
      overall:       reviewOverall(r),
      topWorker:     r.topWorker,
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
      where:   { employerId, apply: visibleApplyFilter() },
      include: {
        apply: {
          include: {
            conversation: { select: { id: true } },
            user: {
              select: {
                id: true, firstName: true, lastName: true, location: true,
                worker: { select: { profilePhotoUrl: true, bio: true, jobInterests: true } },
              },
            },
            job: {
              select: { id: true, title: true, company: true, category: true,
                        logoEmoji: true, location: true, startTime: true, endTime: true, shifts: true, payText: true },
            },
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });

    const summaries = await loadApplicantSummaries(saved.map((s) => s.apply.userId));

    const result = saved.map((s) => ({
      savedId:    s.id,
      applyId:    s.applyId,
      userId:     s.apply.userId,
      savedAt:    s.createdAt,
      workerName: `${s.apply.user?.firstName ?? ""} ${s.apply.user?.lastName ?? ""}`.trim() || "Unknown",
      workerPhoto: s.apply.user?.worker?.profilePhotoUrl ?? null,
      workerCity:  s.apply.user?.location ?? null,
      bio:         s.apply.user?.worker?.bio ?? null,
      bioShort:    truncateText(s.apply.user?.worker?.bio, 140),
      jobInterests: s.apply.user?.worker?.jobInterests ?? [],
      summary:     summaries.get(s.apply.userId) ?? null,
      conversationId: s.apply.conversation?.id ?? null,
      applyStatus: s.apply.status,
      jobId:       s.apply.job?.id ?? "",
      jobTitle:    s.apply.job?.title ?? "—",
      company:     s.apply.job?.company ?? "—",
      logoEmoji:   s.apply.job?.logoEmoji ?? "🏢",
      location:    s.apply.job?.location ?? "—",
      shiftDate:   (s.apply.job ? bookedSpan(s.apply.job, s.apply.shiftIds).start : null) ?? null,
      bookedShifts: s.apply.job ? describeBooked(s.apply.job, s.apply.shiftIds) : [],
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
        category: true,
        payAmount: true,
        shifts: true, platformFeePercent: true,
        payText: true,
        shiftText: true,
        jobNotes: true,
        applies: {
          where: { status: "accepted" },
          select: {
            id: true, userId: true, shiftIds: true, isPaid: true, attendance: true, disputedAt: true, disputeResolvedAt: true,
            user: { select: { firstName: true, lastName: true, ...RESTRICTION_FIELDS, worker: { select: { profilePhotoUrl: true } } } },
          },
        },
      },
      orderBy: { startTime: "asc" },
    });

    // Bewertungen der bestaetigten Worker gebuendelt (ein Satz Queries fuer alle Jobs)
    const summaries = await loadApplicantSummaries(jobs.flatMap((j) => j.applies.map((a) => a.userId)));

    const result = jobs.map((j) => {
      const workerSummaries = j.applies.map((a) => summaries.get(a.userId)).filter(Boolean);
      // Kosten wie in /employer/financials: abgeschlossen = geschuldet, sonst geplant
      const costs = jobCosts(j, j.applies);
      return {
        id:            j.id,
        title:         j.title,
        location:      j.location,
        logoEmoji:     j.logoEmoji ?? "🏢",
        startTime:     j.startTime,
        endTime:       j.endTime,
        openSpots:     j.openSpots ?? 1,
        assignedCount: j.applies.length,
        status:        j.status,
        category:      j.category ?? null,
        payText:       j.payText ?? "",
        shiftText:     j.shiftText ?? "",
        jobNotes:      j.jobNotes?.trim() || null,
        // inkl. Plattform-Gebuehr (Lohn und Gebuehr zusaetzlich getrennt)
        shiftCost:     j.status === "completed" ? costs.completedTotal : costs.plannedTotal,
        shiftWages:    j.status === "completed" ? costs.completed : costs.planned,
        shiftFees:     j.status === "completed" ? costs.completedFee : costs.plannedFee,
        workers: j.applies.map((a) => ({
          applyId:  a.id,
          userId:   a.userId,
          name:     `${a.user?.firstName ?? ""} ${a.user?.lastName ?? ""}`.trim() || "Unknown",
          photoUrl: a.user?.worker?.profilePhotoUrl ?? null,
          restricted: isRestricted(a.user),
          summary:  summaries.get(a.userId) ?? null,
          bookedShifts: describeBooked(j, a.shiftIds),
        })),
        averageWorkerRating: averageRating(workerSummaries),
      };
    });

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
      // Legal Agreements: { key: Bool }
      legalConsents,
    } = req.body;

    // Oeffentliche Profil-Zusatzfelder validieren, bevor irgendetwas gespeichert wird
    const extra = validateEmployerProfileFields(req.body);
    if (extra.errors.length > 0) {
      return res.status(400).json({ error: extra.errors.join(" ") });
    }

    // User-Felder
    const userUpdate = {};
    if (firstName !== undefined) userUpdate.firstName = firstName;
    if (lastName  !== undefined) userUpdate.lastName  = lastName;
    if (legalConsents !== undefined) {
      const current = await prisma.user.findUnique({ where: { id: userId }, select: { role: true, legalConsents: true } });
      userUpdate.legalConsents = mergeConsents(current?.legalConsents, legalConsents, allowedKeysForRole(current?.role));
    }
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
    Object.assign(employerUpdate, extra.data);
    // Json-Spalte: "kein Wert" muss als DbNull geschrieben werden
    if ("socialLinks" in employerUpdate && employerUpdate.socialLinks === null) employerUpdate.socialLinks = Prisma.DbNull;

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
