const express = require("express");
const router = express.Router();
const { requireAuth } = require("./auth");
const { prisma } = require("./prisma");
const { visibleApplyFilter } = require("./utils/moderation");
const { countUnread } = require("./utils/unreadNotifications");
const { acceptedTimestamp, paidTimestamp, reviewDueTimestamp, nextSeenAt } = require("./utils/notificationTimestamps");

// GET /notifications — dynamic notifications from existing DB data
// Zeitstempel = Zeitpunkt des Ereignisses (acceptedAt/paidAt/Job-Ende), siehe utils/notificationTimestamps.js
async function buildNotifications(userId, userRole) {
  const notifications = [];
  if (userRole === "worker") {
    // 1. Accepted applications → "You got the job!"
    const accepted = await prisma.apply.findMany({
      where: { userId, status: "accepted" },
      include: { job: { select: { title: true, company: true } } },
      orderBy: [{ acceptedAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: 10,
    });
    for (const a of accepted) {
      notifications.push({
        id: `accepted-${a.id}`,
        category: "jobActivity",
        title: "Application accepted!",
        body: `Congrats! You got the job at ${a.job.company} — ${a.job.title}`,
        timestamp: acceptedTimestamp(a),
        actionLabel: "View Job",
        actionPayload: { jobId: a.jobId },
      });
    }

    // 1b. Zuverlaessigkeit: erfasster No-Show / eigene kurzfristige Stornierung (letzte 30 Tage)
    const sinceReliability = new Date(Date.now() - 30 * 24 * 3_600_000);
    const reliabilityEvents = await prisma.apply.findMany({
      where: {
        userId,
        OR: [
          { status: "accepted", attendance: "no_show", attendanceSetAt: { gte: sinceReliability } },
          { status: "cancelled_by_worker", lateCancellation: true, cancelledAt: { gte: sinceReliability } },
        ],
      },
      include: { job: { select: { title: true, company: true } } },
      take: 10,
    });
    for (const a of reliabilityEvents) {
      const noShow = a.status === "accepted";
      notifications.push({
        id: `${noShow ? "no-show" : "late-cancel"}-${a.id}`,
        category: "jobActivity",
        title: noShow ? "We missed you at your shift" : "Late cancellation noted",
        body: noShow
          ? `${a.job.company} marked you as not showing up for ${a.job.title}. You can dispute this once under Job Applications.`
          : `You cancelled ${a.job.title} less than 24 hours before it started.`,
        timestamp: (noShow ? a.attendanceSetAt : a.cancelledAt) ?? a.createdAt,
        actionLabel: null,
        actionPayload: null,
      });
    }

    // 2. Reviews received
    const reviews = await prisma.review.findMany({
      where: { workerId: userId },
      include: { apply: { include: { job: { select: { title: true, company: true } } } } },
      orderBy: { createdAt: "desc" },
      take: 10,
    });
    for (const r of reviews) {
      notifications.push({
        id: `review-${r.id}`,
        category: "reviews",
        title: "New review received",
        body: `You received a review for your last job at ${r.apply.job.company}`,
        timestamp: r.createdAt,
        actionLabel: null,
        actionPayload: null,
      });
    }

    // 3. Completed jobs without worker review (nudge to leave review — for workers this is inverse)
    // Workers don't leave reviews in MVP; skip.

    // 4. Payment received (isPaid flipped)
    const paid = await prisma.apply.findMany({
      where: { userId, isPaid: true },
      include: { job: { select: { title: true, company: true, payAmount: true } } },
      orderBy: [{ paidAt: { sort: "desc", nulls: "last" } }, { createdAt: "desc" }],
      take: 10,
    });
    for (const p of paid) {
      notifications.push({
        id: `paid-${p.id}`,
        category: "payments",
        title: "Payment received",
        body: `Money for ${p.job.title} at ${p.job.company} was sent to your account`,
        timestamp: paidTimestamp(p),
        actionLabel: null,
        actionPayload: null,
      });
    }
  } else if (userRole === "employer") {
    // 1. New pending applicants
    const applicants = await prisma.apply.findMany({
      where: {
        job: { employerId: userId },
        status: "pending",
        autoAccepted: false, // Instant-Match-Bewerbungen brauchen keine Antwort
        ...visibleApplyFilter(), // nicht von gesperrten/gebannten Workern
      },
      include: {
        user: { select: { firstName: true, lastName: true } },
        job: { select: { title: true } },
      },
      orderBy: { createdAt: "desc" },
      take: 10,
    });
    for (const a of applicants) {
      const name = [a.user.firstName, a.user.lastName].filter(Boolean).join(" ") || "Someone";
      notifications.push({
        id: `applicant-${a.id}`,
        category: "jobActivity",
        title: "New applicant",
        body: `${name} applied for your job: ${a.job.title}`,
        timestamp: a.createdAt,
        actionLabel: "View Applicant",
        actionPayload: { applyId: a.id },
      });
    }

    // 1b. Worker hat eine bestaetigte Schicht storniert (letzte 14 Tage)
    const cancelledByWorker = await prisma.apply.findMany({
      where: { job: { employerId: userId }, status: "cancelled_by_worker", cancelledAt: { gte: new Date(Date.now() - 14 * 24 * 3_600_000) } },
      include: { user: { select: { firstName: true, lastName: true } }, job: { select: { title: true } } },
      orderBy: { cancelledAt: "desc" },
      take: 10,
    });
    for (const a of cancelledByWorker) {
      const name = [a.user.firstName, a.user.lastName].filter(Boolean).join(" ") || "A worker";
      notifications.push({
        id: `worker-cancelled-${a.id}`,
        category: "jobActivity",
        title: "Worker cancelled a shift",
        body: `${name} cancelled their shift for ${a.job.title}. The spot is open again.`,
        timestamp: a.cancelledAt,
        actionLabel: null,
        actionPayload: null,
      });
    }

    // 2. Reviews to leave (accepted workers with completed jobs, no review yet)
    const needsReview = await prisma.apply.findMany({
      where: {
        job: { employerId: userId, status: "completed" },
        status: "accepted",
        review: null,
      },
      include: {
        user: { select: { firstName: true, lastName: true } },
        job: { select: { title: true, endTime: true, updatedAt: true } },
      },
      orderBy: { job: { endTime: "desc" } },
      take: 10,
    });
    for (const a of needsReview) {
      const name = [a.user.firstName, a.user.lastName].filter(Boolean).join(" ") || "Worker";
      notifications.push({
        id: `review-due-${a.id}`,
        category: "reviews",
        title: "Please review your worker",
        body: `Leave a review for ${name} — ${a.job.title}`,
        timestamp: reviewDueTimestamp(a),
        actionLabel: null,
        actionPayload: null,
      });
    }

    // 3. Reviews received from workers (future feature placeholder — skip for now)
  }

  // Verwarnungen durch das Moderationsteam (alle Rollen); Details/Notiz bleiben intern
  const warnings = await prisma.moderationAction.findMany({
    where: { targetUserId: userId, action: "warn" },
    orderBy: { createdAt: "desc" },
    take: 10,
    select: { id: true, createdAt: true },
  });
  for (const w of warnings) {
    notifications.push({
      id: `warning-${w.id}`,
      category: "system",
      title: "Warning from SwipeShift",
      body: "Our team reviewed a report about your account and issued a warning. Please follow our community guidelines — further violations can lead to a suspension.",
      timestamp: w.createdAt,
      actionLabel: null,
      actionPayload: null,
    });
  }

  // Sort all by timestamp descending
  notifications.sort((a, b) => new Date(b.timestamp) - new Date(a.timestamp));
  return notifications;
}

// GET /notifications
router.get("/", requireAuth, async (req, res) => {
  try {
    res.json(await buildNotifications(req.auth.sub, req.auth.role));
  } catch (err) {
    console.error("GET /notifications error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// GET /notifications/unread-count — Badge an der Glocke ({ unreadCount })
router.get("/unread-count", requireAuth, async (req, res) => {
  try {
    const me = await prisma.user.findUnique({ where: { id: req.auth.sub }, select: { notificationsSeenAt: true } });
    const list = await buildNotifications(req.auth.sub, req.auth.role);
    res.json({ unreadCount: countUnread(list, me?.notificationsSeenAt) });
  } catch (err) {
    console.error("GET /notifications/unread-count error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

// POST /notifications/seen — Glocke geoeffnet: alles bis jetzt gilt als gelesen
router.post("/seen", requireAuth, async (req, res) => {
  try {
    const upTo = req.body?.upTo;
    if (upTo !== undefined && upTo !== null && (typeof upTo !== "string" || Number.isNaN(new Date(upTo).getTime()))) {
      return res.status(400).json({ error: "upTo must be an ISO date string" });
    }
    const me = await prisma.user.findUnique({ where: { id: req.auth.sub }, select: { notificationsSeenAt: true } });
    const next = nextSeenAt(me?.notificationsSeenAt, req.body?.upTo, new Date());
    if (next) await prisma.user.update({ where: { id: req.auth.sub }, data: { notificationsSeenAt: next } });
    const list = await buildNotifications(req.auth.sub, req.auth.role);
    res.json({ unreadCount: countUnread(list, next ?? me?.notificationsSeenAt) });
  } catch (err) {
    console.error("POST /notifications/seen error:", err);
    res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
