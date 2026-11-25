// src/routes.admin.js — Moderation der User-Reports (nur Admin-Konten, siehe middlewares/requireAdmin.js)
//   GET  /admin/reports?status=open|closed   Liste (open: ein Eintrag pro gemeldetem User, closed: flach)
//   GET  /admin/reports/:id                  Detail inkl. Melder-Notizen, Chat-Verlauf (letzte 100), Historie
//   POST /admin/reports/:id/actions          { action: warn|suspend|ban|dismiss, durationDays?, note? }
//   POST /admin/deleted-accounts/:id/unban   E-Mail eines geloeschten, gebannten Kontos entbannen
//   POST /admin/users/:id/lift               Sperre/Bann aufheben
//   GET  /admin/reliability                  Auffaellige Worker (>= 2 No-Shows / >= 3 kurzfristige Stornos in 90 Tagen) + offene Anwesenheits-Einsprueche
//   POST /admin/attendance/:applyId/resolve  { uphold: true } | { attendance: attended|late|no_show }
// Interessenkonflikte: Meldungen gegen den Admin sind fuer ihn unsichtbar (404), eigene Meldungen darf er nicht bearbeiten,
// eigene No-Show-Einsprueche / Einsprueche auf eigenen Jobs entscheidet ein anderer Admin (siehe utils/moderation.js).
const express = require("express");
const rateLimit = require("express-rate-limit");
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const { requireAdmin } = require("./middlewares/requireAdmin");
const { describeBlockedUser } = require("./utils/blockedUsers");
const m = require("./utils/moderation");
const { applyReportAction, applyDeletedReportAction, unbanDeletedAccount, liftRestriction } = require("./moderation");
const rel = require("./utils/reliability");
const events = require("./notifyEvents");

const router = express.Router();

const adminLimiter = rateLimit({
  windowMs: 60 * 1000, max: 120, keyGenerator: (req) => req.auth?.sub || req.ip, validate: { keyGeneratorIpFallback: false },
  standardHeaders: true, legacyHeaders: false,
  message: { error: "Too many requests, try again later.", code: "RATE_LIMITED" },
});
router.use(requireAuth, requireAdmin, adminLimiter);

function handle(label, fn) {
  return async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      console.error(`${label} error:`, err);
      if (!res.headersSent) res.status(500).json({ error: "Internal server error" });
    }
  };
}

const USER_SELECT = {
  id: true, role: true, isAdmin: true, firstName: true, lastName: true,
  bannedAt: true, suspendedUntil: true, suspensionReason: true,
  employer: { select: { companyName: true, companyLogoUrl: true } },
  worker: { select: { profilePhotoUrl: true } },
};

async function loadBriefs(ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  const users = unique.length ? await prisma.user.findMany({ where: { id: { in: unique } }, select: USER_SELECT }) : [];
  return new Map(users.map((u) => [u.id, u]));
}

// Tombstones geloeschter Konten (id → { displayName, role, deletedAt, bannedAt })
async function loadTombstones(ids) {
  const unique = [...new Set(ids.filter(Boolean))];
  const rows = unique.length ? await prisma.deletedAccount.findMany({ where: { id: { in: unique } } }) : [];
  return new Map(rows.map((t) => [t.id, t]));
}

function brief(u, id, tombs) {
  if (!u && tombs?.has(id)) {
    const t = tombs.get(id);
    return { id, name: "Deleted account", role: t.role, photoUrl: null, deleted: true, deletedAt: t.deletedAt };
  }
  if (!u) return { id, name: "Deleted user", role: null, photoUrl: null };
  const d = describeBlockedUser(u, u.employer, u.worker);
  return { id: u.id, name: d.name, role: d.role, photoUrl: d.photoUrl };
}

function restrictionOf(u) {
  const s = m.restrictionState(u);
  return { state: s.state, until: s.until ? s.until.toISOString() : null, pendingReview: s.pendingReview };
}

// Gemeldeter: geloeschtes Konto → "Deleted account", deleted:true, canBan nur mit Tombstone (Ban braucht die E-Mail-Spur).
// displayName ("Anna M.") nur fuer Admins. Altfaelle ohne Tombstone: nur dismiss.
function reportedBrief(u, id, tombs) {
  if (u) return brief(u, id, tombs);
  const t = tombs?.get(id);
  return {
    id, name: "Deleted account", role: t?.role ?? null, photoUrl: null,
    deleted: true, deletedAt: t?.deletedAt ?? null, deletedName: t?.displayName ?? null, canBan: !!t, banned: !!t?.bannedAt, emailVerified: t ? t.emailVerified : null,
  };
}

function reportCard(r, briefs, openCount, openReporterCount, tombs) {
  return {
    id: r.id, status: r.status, reason: r.reason, details: r.details, createdAt: r.createdAt,
    resolvedAt: r.resolvedAt, resolution: r.resolution, conversationId: r.conversationId,
    reporter: brief(briefs.get(r.reporterId), r.reporterId, tombs),
    reported: { ...reportedBrief(briefs.get(r.reportedUserId), r.reportedUserId, tombs), isAdmin: !!briefs.get(r.reportedUserId)?.isAdmin, restriction: restrictionOf(briefs.get(r.reportedUserId)) },
    openReportCount: openCount, openReporterCount,
  };
}

router.get("/reports", handle("GET /admin/reports", async (req, res) => {
  const status = req.query.status === "closed" ? "closed" : "open";
  // Meldungen gegen den Admin selbst sowie Ziel-Gruppen mit eigener offener Meldung bearbeitet nur ein anderer Admin
  const own = status === "open"
    ? await prisma.userReport.findMany({ where: { status: "open", reporterId: req.auth.sub }, select: { reportedUserId: true } })
    : [];
  const rows = await prisma.userReport.findMany({
    where: m.reportsVisibleWhere(req.auth.sub, status, [...new Set(own.map((o) => o.reportedUserId))]),
    orderBy: status === "open" ? { createdAt: "desc" } : { resolvedAt: "desc" },
    take: 300,
  });

  // offene Reports pro gemeldetem User (gesamt, nicht nur im Ausschnitt)
  const targetIds = [...new Set(rows.map((r) => r.reportedUserId))];
  const openRows = targetIds.length
    ? await prisma.userReport.findMany({ where: { status: "open", reportedUserId: { in: targetIds } }, select: { reportedUserId: true, reporterId: true } })
    : [];
  const counts = new Map();
  for (const o of openRows) {
    const c = counts.get(o.reportedUserId) ?? { total: 0, reporters: new Set() };
    c.total += 1; c.reporters.add(o.reporterId);
    counts.set(o.reportedUserId, c);
  }

  let list = rows;
  if (status === "open") {
    const seen = new Set();
    list = rows.filter((r) => (seen.has(r.reportedUserId) ? false : (seen.add(r.reportedUserId), true)));
  }
  const ids = list.flatMap((r) => [r.reporterId, r.reportedUserId]);
  const [briefs, tombs] = await Promise.all([loadBriefs(ids), loadTombstones(ids)]);
  return res.json({
    reports: list.slice(0, 100).map((r) => {
      const c = counts.get(r.reportedUserId);
      return reportCard(r, briefs, c?.total ?? 0, c?.reporters.size ?? 0, tombs);
    }),
  });
}));

router.get("/reports/:id", handle("GET /admin/reports/:id", async (req, res) => {
  const report = await prisma.userReport.findUnique({ where: { id: String(req.params.id) } });
  if (!report || m.isReportHiddenFrom(req.auth.sub, report)) return res.status(404).json({ error: "Report not found" });

  const [openReports, history, convo] = await Promise.all([
    prisma.userReport.findMany({ where: { reportedUserId: report.reportedUserId, status: "open" }, orderBy: { createdAt: "desc" } }),
    prisma.moderationAction.findMany({ where: { targetUserId: report.reportedUserId }, orderBy: { createdAt: "desc" }, take: 50 }),
    report.conversationId
      ? prisma.conversation.findUnique({
          where: { id: report.conversationId },
          select: { id: true, workerId: true, employerId: true, job: { select: { title: true } } },
        })
      : null,
  ]);
  const notes = report.status === "open" ? openReports : [report];

  let messages = [];
  if (convo) {
    const rows = await prisma.message.findMany({
      where: { conversationId: convo.id }, orderBy: { createdAt: "desc" }, take: 100,
      select: { id: true, senderId: true, text: true, isSystem: true, createdAt: true },
    });
    messages = rows.reverse();
  }

  const briefIds = [
    report.reportedUserId, ...notes.map((r) => r.reporterId), ...history.map((h) => h.adminId),
    convo?.workerId, convo?.employerId,
  ];
  const [briefs, tombs] = await Promise.all([loadBriefs(briefIds), loadTombstones(briefIds)]);
  const card = reportCard(report, briefs, openReports.length, new Set(openReports.map((r) => r.reporterId)).size, tombs);

  return res.json({
    report: card,
    reports: notes.map((r) => ({ id: r.id, reason: r.reason, details: r.details, createdAt: r.createdAt, reporter: brief(briefs.get(r.reporterId), r.reporterId, tombs) })),
    conversation: convo
      ? {
          id: convo.id, jobTitle: convo.job?.title ?? null,
          participants: [convo.workerId, convo.employerId].filter(Boolean).map((id) => brief(briefs.get(id), id, tombs)),
          messages: messages.map((x) => ({ id: x.id, senderId: x.senderId, text: x.text, isSystem: x.isSystem, createdAt: x.createdAt })),
        }
      : null,
    history: history.map((h) => ({
      id: h.id, action: h.action, durationDays: h.durationDays, note: h.note, createdAt: h.createdAt,
      admin: h.adminId ? brief(briefs.get(h.adminId), h.adminId, tombs) : null, // null = System
    })),
  });
}));

router.post("/reports/:id/actions", handle("POST /admin/reports/:id/actions", async (req, res) => {
  const check = m.validateAction(req.body);
  if (!check.ok) return res.status(400).json({ error: check.error });

  const report = await prisma.userReport.findUnique({ where: { id: String(req.params.id) } });
  const handle_ = m.canHandleReport(req.auth.sub, report);
  if (!handle_.ok) return res.status(handle_.status).json({ error: handle_.error });
  if (report.status !== "open") return res.status(409).json({ error: "This report was already handled.", code: "ALREADY_RESOLVED" });

  const target = await prisma.user.findUnique({
    where: { id: report.reportedUserId },
    select: { id: true, email: true, isAdmin: true, bannedAt: true, suspendedUntil: true, suspensionReason: true },
  });
  if (!target) {
    // Gemeldetes Konto wurde geloescht: nur dismiss/ban (ban nur mit Tombstone)
    const del = await applyDeletedReportAction({ report, adminId: req.auth.sub, value: check.value });
    if (!del.ok) return res.status(del.status).json({ error: del.error, code: del.code });
    return res.json({ ok: true, closedReports: del.closedCount });
  }
  const can = m.canModerate(req.auth.sub, target);
  if (!can.ok) return res.status(can.status).json({ error: can.error });

  let result = await applyReportAction({ report, target, adminId: req.auth.sub, value: check.value });
  if (!result.ok && result.gone) {
    // Konto wurde zwischen Lesen und Aktion geloescht → einmal auf den Deleted-Pfad umschwenken
    result = await applyDeletedReportAction({ report, adminId: req.auth.sub, value: check.value });
  }
  if (!result.ok) return res.status(result.status).json({ error: result.error, code: result.code });
  return res.json({ ok: true, closedReports: result.closedCount });
}));

// E-Mail eines geloeschten, gebannten Kontos entbannen (Konto selbst bleibt geloescht)
router.post("/deleted-accounts/:id/unban", handle("POST /admin/deleted-accounts/:id/unban", async (req, res) => {
  const result = await unbanDeletedAccount({ id: String(req.params.id), adminId: req.auth.sub });
  if (!result.ok) return res.status(result.status).json({ error: result.error, code: result.code });
  return res.json({ ok: true });
}));

router.post("/users/:id/lift", handle("POST /admin/users/:id/lift", async (req, res) => {
  const target = await prisma.user.findUnique({
    where: { id: String(req.params.id) },
    select: { id: true, email: true, isAdmin: true, bannedAt: true, suspendedUntil: true, suspensionReason: true },
  });
  const can = m.canModerate(req.auth.sub, target);
  if (!can.ok) return res.status(can.status).json({ error: can.error });
  if (!m.isRestricted(target)) return res.status(409).json({ error: "This account is not suspended.", code: "NOT_RESTRICTED" });
  await liftRestriction({ target, adminId: req.auth.sub });
  return res.json({ ok: true });
}));

// ─── Reliability: auffaellige Worker + offene Einsprueche (nur Hinweis, keine automatischen Einschraenkungen) ───
router.get("/reliability", handle("GET /admin/reliability", async (req, res) => {
  const now = new Date();

  // Alle relevanten Zeilen der letzten 90 Tage, je Worker gebuendelt
  const rows = await prisma.apply.findMany({
    where: rel.reliabilityRowsWhere(now, rel.ADMIN_WINDOW_DAYS),
    select: {
      userId: true, status: true, attendance: true, disputedAt: true, disputeResolvedAt: true,
      lateCancellation: true, cancelledAt: true, shiftIds: true, job: { select: { endTime: true, startTime: true, shifts: true } },
    },
    orderBy: [{ createdAt: "asc" }, { id: "asc" }], // deterministisch, falls das Limit greift
    take: 5000,
  });
  const me = req.auth.sub;
  const byUser = new Map();
  for (const row of rows) {
    if (row.userId === me) continue; // eigene Zuverlaessigkeit bewertet ein anderer Admin
    if (!byUser.has(row.userId)) byUser.set(row.userId, []);
    byUser.get(row.userId).push(row);
  }
  const flagged = [];
  for (const [userId, list] of byUser) {
    const summary = rel.summarizeReliability(list, now, { windowDays: rel.ADMIN_WINDOW_DAYS });
    if (rel.isConspicuous(summary)) flagged.push({ userId, summary });
  }
  flagged.sort((a, b) => b.summary.noShows - a.summary.noShows || b.summary.lateCancellations - a.summary.lateCancellations);

  const disputes = await prisma.apply.findMany({
    where: m.disputeVisibleWhere(me), // eigener Einspruch bzw. Einspruch auf eigenem Job: nur fuer andere Admins
    orderBy: [{ disputedAt: "asc" }, { id: "asc" }],
    take: 100,
    select: {
      id: true, userId: true, attendance: true, attendanceSource: true, attendanceSetAt: true, disputeNote: true, disputedAt: true,
      job: { select: { title: true, company: true, employerId: true, startTime: true, endTime: true } },
    },
  });

  const briefs = await loadBriefs([...flagged.slice(0, 50).map((f) => f.userId), ...disputes.map((d) => d.userId)]);
  return res.json({
    windowDays: rel.ADMIN_WINDOW_DAYS,
    thresholds: { noShows: rel.ADMIN_NO_SHOW_THRESHOLD, lateCancellations: rel.ADMIN_LATE_CANCEL_THRESHOLD },
    flagged: flagged.slice(0, 50).map(({ userId, summary }) => ({
      worker: { ...brief(briefs.get(userId), userId), restriction: restrictionOf(briefs.get(userId)) },
      finishedShifts: summary.finishedShifts, noShows: summary.noShows, late: summary.late,
      lateCancellations: summary.lateCancellations,
    })),
    disputes: disputes.map((d) => ({
      applyId: d.id,
      worker: brief(briefs.get(d.userId), d.userId),
      jobTitle: d.job.title, company: d.job.company, shiftStart: d.job.startTime, shiftEnd: d.job.endTime,
      attendance: d.attendance, attendanceSource: d.attendanceSource, attendanceSetAt: d.attendanceSetAt,
      note: d.disputeNote, disputedAt: d.disputedAt,
    })),
  });
}));

router.post("/attendance/:applyId/resolve", handle("POST /admin/attendance/:applyId/resolve", async (req, res) => {
  const parsed = rel.parseDisputeResolution(req.body);
  if (!parsed.ok) return res.status(400).json({ error: parsed.error });

  const applyId = String(req.params.applyId);
  const apply = await prisma.apply.findUnique({ where: { id: applyId }, select: { id: true, userId: true, status: true, disputedAt: true, disputeResolvedAt: true, job: { select: { employerId: true } } } });
  if (!apply || apply.status !== "accepted") return res.status(404).json({ error: "Application not found" });
  const conflict = m.disputeConflict(req.auth.sub, { userId: apply.userId, employerId: apply.job?.employerId });
  if (conflict.conflict) return res.status(403).json({ error: conflict.error, code: "CONFLICT_OF_INTEREST" });
  if (!apply.disputedAt) return res.status(409).json({ error: "This entry has no dispute.", code: "NO_DISPUTE" });
  if (apply.disputeResolvedAt) return res.status(409).json({ error: "This dispute was already handled.", code: "ALREADY_RESOLVED" });

  const now = new Date();
  const { count } = await prisma.apply.updateMany({
    where: { id: applyId, status: "accepted", disputedAt: { not: null }, disputeResolvedAt: null },
    data: {
      disputeResolvedAt: now, disputeResolution: parsed.resolution,
      ...(parsed.attendance ? { attendance: parsed.attendance, attendanceSource: "admin", attendanceSetAt: now } : {}),
    },
  });
  if (count !== 1) return res.status(409).json({ error: "This dispute was already handled.", code: "ALREADY_RESOLVED" });
  events.attendanceDisputeResolved(applyId); // fire-and-forget
  return res.json({ ok: true });
}));

module.exports = router;
