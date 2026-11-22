// src/routes.worker.js

const express = require("express");
const events = require("./notifyEvents");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");
const { resolvePeriod, isInPeriod, bookingPeriodPrefilter, currentWeekRange } = require("./utils/period");
const { payPerWorker, shiftHours } = require("./utils/jobCost");
const { bookedSpan, withBookedTimes, describeBooked } = require("./utils/shiftBooking");
const { distanceMilesBetween } = require("./utils/haversine");
const { companyJobsWhere, truncateText } = require("./utils/companyStats");
const { jobNotesForApply } = require("./utils/jobNotes");
const { restrictedEmployerIds } = require("./restrictedUsers");
const { lastCompanyActivity } = require("./utils/savedCompanyDates");
const { deriveApplicationStatus, normalizeCancellationReason } = require("./utils/applicationStatus");
const rel = require("./utils/reliability");
const { loadReliability } = require("./reliability");
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
            startTime: true, endTime: true, shifts: true, category: true,
            status: true, cancellationReason: true, payAmount: true, jobNotes: true,
          },
        },
        conversation: { select: { id: true } },
      },
      orderBy: { createdAt: "desc" },
    });

    const applications = applies.map((a) => {
      const fullJob = a.job;
      // Aus Worker-Sicht zaehlen nur die GEBUCHTEN Schichten (Start = erste, Ende = letzte gebuchte; Altbestand = alle)
      const job = fullJob ? withBookedTimes(fullJob, a.shiftIds) : fullJob;
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
        earnings:       job && rel.isPayable(a) ? payPerWorker(job, a.shiftIds) : 0, // No-Show (auch unter Einspruch) noch nicht bezahlt; nur gebuchte Schichten
        // Gebuchte Schichten (Kalender/Job Applications zeigen nur diese)
        bookedShifts:   fullJob ? describeBooked(fullJob, a.shiftIds) : [],
        // Entfernung Worker → Job in Meilen (null ohne Koordinaten)
        distanceMiles:  distanceMilesBetween(me?.lat, me?.lng, job?.lat, job?.lng),
        // Chat erst nach Annahme sinnvoll — die Conversation existiert aber ab Bewerbung
        conversationId: a.conversation?.id ?? null,
        // Schicht stornieren (nur angenommen + in der Zukunft); lateIfCancelledNow = Warnung < 24 h vor Start
        canCancel:         rel.canWorkerCancel(a, job, now),
        lateIfCancelledNow: rel.isLateCancellation(job?.startTime, now),
        cancelledAt:       a.cancelledAt ?? null,
        lateCancellation:  a.lateCancellation === true,
        // Anwesenheit (vom Employer erfasst, sonst automatisch) + einmaliger Einspruch
        attendance:        a.attendance ?? null,
        attendanceSource:  a.attendanceSource ?? null,
        canDispute:        rel.canDispute(a, now),
        disputeStatus:     rel.disputeStatus(a),
        disputeResolution: a.disputeResolution ?? null,
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
// POST /worker/applications/:applyId/cancel  { reason? }
// Angenommene, noch nicht begonnene Schicht stornieren. < 24 h vor Start = kurzfristige Stornierung
// (zaehlt in der Zuverlaessigkeit). Der Platz wird frei (Status cancelled_by_worker ist nicht "accepted").
// ─────────────────────────────────────────────
router.post("/applications/:applyId/cancel", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const { applyId } = req.params;
    const now = new Date();

    const apply = await prisma.apply.findUnique({
      where:   { id: applyId },
      include: { job: { select: { title: true, status: true, startTime: true, endTime: true, shifts: true, employerId: true } }, conversation: { select: { id: true } } },
    });
    if (!apply)                    return res.status(404).json({ error: "Application not found" });
    if (apply.userId !== workerId) return res.status(403).json({ error: "Forbidden" });

    // Start = erste GEBUCHTE Schicht (storniert wird die ganze Buchung)
    const decision = rel.evaluateWorkerCancel(apply, withBookedTimes(apply.job, apply.shiftIds), now);
    if (!decision.ok) return res.status(decision.status).json({ error: decision.error, code: decision.code });

    const reason = normalizeCancellationReason(req.body?.reason);
    const claimed = await prisma.$transaction(async (tx) => {
      // Bedingtes Update: nur der erste Request gewinnt (kein doppelter Storno / keine doppelten Nachrichten)
      const { count } = await tx.apply.updateMany({
        where: { id: applyId, userId: workerId, status: "accepted" },
        data:  { status: rel.CANCELLED_BY_WORKER, cancelledAt: now, lateCancellation: decision.lateCancellation, cancelReason: reason },
      });
      if (count !== 1) return false;
      if (apply.conversation) {
        await tx.conversation.update({ where: { id: apply.conversation.id }, data: { status: "cancelled" } });
        await tx.message.create({
          data: {
            conversationId: apply.conversation.id,
            senderId:       workerId,
            text:           `The worker cancelled this shift${decision.lateCancellation ? " less than 24 hours before the start" : ""}.${reason ? ` Reason: ${reason}` : ""}`,
            isSystem:       true,
            isRead:         false, // der Employer sieht den Hinweis als ungelesen
          },
        });
      }
      return true;
    });
    if (!claimed) return res.status(409).json({ error: "This shift was already changed.", code: "CHANGED" });

    events.workerCancelledShift(applyId); // fire-and-forget: Employer informieren, bei < 24 h den Worker erinnern
    return res.json({ ok: true, lateCancellation: decision.lateCancellation });
  } catch (err) {
    console.error("POST /worker/applications/:id/cancel error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// POST /worker/applications/:applyId/dispute  { note }
// Einmaliger Einspruch gegen "late"/"no_show". Der Eintrag zaehlt bis zur Admin-Entscheidung nicht.
// ─────────────────────────────────────────────
router.post("/applications/:applyId/dispute", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const { applyId } = req.params;

    const checked = rel.validateDisputeNote(req.body?.note);
    if (!checked.ok) return res.status(400).json({ error: checked.error });

    const apply = await prisma.apply.findUnique({ where: { id: applyId } });
    if (!apply)                    return res.status(404).json({ error: "Application not found" });
    if (apply.userId !== workerId) return res.status(403).json({ error: "Forbidden" });
    if (apply.disputedAt)          return res.status(409).json({ error: "You already disputed this entry.", code: "ALREADY_DISPUTED" });
    if (!rel.canDispute(apply)) {
      const lateOrNoShow = apply.status === "accepted" && (apply.attendance === "late" || apply.attendance === "no_show");
      return lateOrNoShow
        ? res.status(409).json({ error: `You can dispute an entry within ${rel.DISPUTE_WINDOW_DAYS} days after it was recorded.`, code: "DISPUTE_WINDOW_CLOSED" })
        : res.status(409).json({ error: "Only a late or no-show entry can be disputed.", code: "NOT_DISPUTABLE" });
    }

    const { count } = await prisma.apply.updateMany({
      where: { id: applyId, userId: workerId, status: "accepted", attendance: apply.attendance, disputedAt: null },
      data:  { disputeNote: checked.note, disputedAt: new Date() },
    });
    if (count !== 1) return res.status(409).json({ error: "This entry just changed. Please reload.", code: "CHANGED" });
    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /worker/applications/:id/dispute error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─────────────────────────────────────────────
// GET /worker/reliability — eigene Zuverlaessigkeit (letzte 12 Monate). Nur der Worker selbst und Employer
// mit Bewerbung sehen sie; andere Worker nie.
// ─────────────────────────────────────────────
router.get("/reliability", requireAuth, requireVerifiedEmail, async (req, res) => {
  try {
    const workerId = req.auth.sub;
    const map = await loadReliability([workerId]);
    return res.json({ reliability: map.get(workerId), windowDays: rel.WINDOW_DAYS, minShiftsForRate: rel.MIN_SHIFTS_FOR_RATE });
  } catch (err) {
    console.error("GET /worker/reliability error:", err);
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
            tags: true, lat: true, lng: true, status: true, openSpots: true, startTime: true, employerId: true,
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

    // Jobs gesperrter/gebannter Employer ausblenden — ausser der Worker hat sich beworben (Verlauf bleibt heil)
    const hiddenEmployers = await restrictedEmployerIds();
    const visibleSaves = saves.filter((s) => !(s.job?.employerId && hiddenEmployers.has(s.job.employerId)) || applyMap[s.jobId]);

    const saved = visibleSaves.map((s) => {
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
      include: { job: { select: { employerId: true, status: true, startTime: true, endTime: true, shifts: true } } },
    });
    if (!apply) return res.status(404).json({ error: "Application not found" });
    // Gleiche Regel wie Job Applications/Kalender: nur angenommene, abgeschlossene Jobs sind bewertbar
    if (deriveApplicationStatus(apply, withBookedTimes(apply.job, apply.shiftIds)).displayStatus !== "completed") {
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

    const allApplies = await prisma.apply.findMany({
      where: {
        userId: workerId,
        status: "accepted",
        // Stornierte Jobs bringen keinen Verdienst
        // Grobfilter; der Zeitraum gilt fuer den START DER GEBUCHTEN Schichten (unten im Speicher)
        job: { status: { not: "cancelled" }, ...bookingPeriodPrefilter(range) },
      },
      include: {
        job: {
          select: {
            id: true, title: true, company: true, logoEmoji: true,
            payAmount: true, startTime: true, endTime: true, shifts: true, shiftText: true,
          },
        },
      },
      orderBy: { createdAt: "desc" },
    });
    // No-Shows (auch unter Einspruch: on hold) werden noch nicht bezahlt → kein Verdienst (utils/reliability.js)
    const applies = rel.billable(allApplies).filter((a) => isInPeriod(a.job ? bookedSpan(a.job, a.shiftIds).start : null, range));

    // "This week": Verdienst der laufenden Woche Mo–So (in SERVER-Lokalzeit, nicht Geraetezeit),
    // unabhaengig vom gewaehlten Zeitraum.
    // Gleiche Formel (payPerWorker), stornierte Jobs zaehlen nicht.
    const weekRows = await prisma.apply.findMany({
      where: {
        userId: workerId,
        status: "accepted",
        job: { status: { not: "cancelled" }, ...bookingPeriodPrefilter(currentWeekRange(now)) },
      },
      include: { job: { select: { payAmount: true, startTime: true, endTime: true, shifts: true } } },
    });
    const week = currentWeekRange(now);
    const weekApplies = rel.billable(weekRows).filter((a) => a.job && isInPeriod(bookedSpan(a.job, a.shiftIds).start, week));
    const thisWeekEarnings = weekApplies.reduce((sum, a) => sum + (a.job ? payPerWorker(a.job, a.shiftIds) : 0), 0);

    // Gleiche Rechnung wie beim Employer (Stundenlohn × Schichtstunden, utils/jobCost.js)
    // Nur die GEBUCHTEN Schichten des Workers zaehlen (Apply.shiftIds, leer = alle)
    const calcEarning = (a) => (a.job ? payPerWorker(a.job, a.shiftIds) : 0);
    const spanOf = (a) => (a.job ? bookedSpan(a.job, a.shiftIds) : { start: null, end: null });

    const upcoming   = applies.filter((a) => { const sp = spanOf(a); return sp.start && new Date(sp.start) > now; });
    const completed  = applies.filter((a) => { const sp = spanOf(a); return sp.end   && new Date(sp.end)   <= now; });
    const paidOutArr = completed.filter((a) => a.isPaid);

    const upcomingEarnings   = upcoming.reduce((s, a) => s + calcEarning(a), 0);
    const completedEarnings  = completed.reduce((s, a) => s + calcEarning(a), 0);
    const paidOut            = paidOutArr.reduce((s, a) => s + calcEarning(a), 0);

    // Neueste Schichten zuerst, max. EARNINGS_LIST_LIMIT; total = Anzahl im Zeitraum (fuer "Showing latest N")
    const sortedApplies = [...applies].sort(
      (a, b) => (spanOf(b).start ? new Date(spanOf(b).start).getTime() : 0) - (spanOf(a).start ? new Date(spanOf(a).start).getTime() : 0)
    );
    const earningsList = sortedApplies.slice(0, EARNINGS_LIST_LIMIT).map((a) => ({
      id:        a.id,
      // Stundenlohn × Stunden = amount (utils/jobCost.js); startTime fuer die Monatsgruppierung
      hourlyRate: a.job?.payAmount ?? null,
      hours:      a.job ? shiftHours(a.job, a.shiftIds) : null,
      startTime:  spanOf(a).start ?? null,
      bookedShifts: a.job ? describeBooked(a.job, a.shiftIds) : [],
      isPaid:     a.isPaid,
      jobTitle:  a.job?.title     ?? "—",
      company:   a.job?.company   ?? "—",
      logoEmoji: a.job?.logoEmoji ?? "🏢",
      shiftText: a.job?.shiftText ?? "—",
      amount:    calcEarning(a),
      status:    spanOf(a).start && new Date(spanOf(a).start) > now ? "upcoming" : "completed",
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

    const hiddenEmployers = await restrictedEmployerIds();
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
        // Jobs gesperrter/gebannter Employer zaehlen nicht als offene Jobs
        return { sc, jobs: jobs.filter((j) => !j.employerId || !hiddenEmployers.has(j.employerId)), reviews };
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
