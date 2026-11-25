// src/moderation.js
// DB-seitige Moderation: Aktionen anwenden, Auto-Sperre bei Mehrfach-Meldungen, Sessions widerrufen, Safety-Mails.
// Entscheidungslogik steckt rein in utils/moderation.js. Mails sind Sicherheits-Mails: laufen NICHT durch notify()
// (also unabhaengig von Benachrichtigungs-Einstellungen). Mail-Fehler werden geloggt, brechen aber nie eine Aktion ab.

const { prisma } = require("./prisma.js");
const { sendMail } = require("./mailer");
const { removeDevicesForSessions } = require("./pushDevices");
const { renderEmail, plainLine } = require("./utils/emailTemplate");
const m = require("./utils/moderation");
const tomb = require("./utils/tombstones");

const SAFETY_FOOTER = "You are receiving this email because of an account safety matter. Questions? support@swipeshift.app";

function supportEmail() {
  return process.env.SUPPORT_EMAIL || "support@swipeshift.app";
}

async function sendSafetyMail(to, { subject, heading, paragraphs }) {
  try {
    const { html, text } = renderEmail({ heading, paragraphs, footer: SAFETY_FOOTER });
    await sendMail({ to, subject: plainLine(subject, 200), html, text });
  } catch (err) {
    console.error("moderation mail failed:", err);
  }
}

// Alle Sitzungen beenden + Push-Geraete entfernen (wie Logout, nur fuer alle Sitzungen)
async function revokeAllSessions(userId) {
  await prisma.userSession.updateMany({ where: { userId, revokedAt: null }, data: { revokedAt: new Date() } });
  await removeDevicesForSessions({ userId });
}

async function notifyTarget(targetEmail, kind, ctx) {
  const notice = m.targetNotice(kind, ctx);
  if (notice && targetEmail) await sendSafetyMail(targetEmail, notice);
}

// Melder erhalten je einmal die kurze Entscheidung (ohne Details)
async function notifyReporters(reporterIds, resolution) {
  if (!reporterIds.length) return;
  const users = await prisma.user.findMany({ where: { id: { in: reporterIds } }, select: { email: true } });
  const feedback = m.reporterFeedback(resolution);
  for (const u of users) {
    await sendSafetyMail(u.email, {
      subject: "Update on your SwipeShift report",
      heading: "Update on your report",
      paragraphs: [feedback, "Thank you for helping keep SwipeShift safe."],
    });
  }
}

async function mailAdmins({ target, reporterCount }) {
  const admins = await prisma.user.findMany({ where: { isAdmin: true }, select: { email: true } });
  const recipients = [...new Set([...admins.map((a) => a.email), supportEmail()].map((e) => e.toLowerCase()))];
  const name = [target.firstName, target.lastName].filter(Boolean).join(" ") || target.email;
  for (const to of recipients) {
    await sendSafetyMail(to, {
      subject: "[SwipeShift] Account auto-suspended pending review",
      heading: "Account suspended pending review",
      paragraphs: [
        `${name} (${target.id}) received open reports from ${reporterCount} different users and was suspended automatically.`,
        "Open the Admin area in the SwipeShift app to review the reports and decide on warn, suspend, ban or dismiss.",
      ],
    });
  }
}

// Nach dem Anlegen eines Reports aufrufen. Idempotent: der bedingte updateMany entscheidet, wer die Sperre "gewinnt".
async function autoSuspendIfNeeded(targetId, now = new Date()) {
  const [target, reports, lastLift] = await Promise.all([
    prisma.user.findUnique({
      where: { id: targetId },
      select: { id: true, email: true, firstName: true, lastName: true, isAdmin: true, bannedAt: true, suspendedUntil: true, suspensionReason: true },
    }),
    prisma.userReport.findMany({ where: { reportedUserId: targetId, status: "open" }, select: { reporterId: true, createdAt: true, status: true } }),
    prisma.moderationAction.findFirst({ where: { targetUserId: targetId, action: "lift" }, orderBy: { createdAt: "desc" }, select: { createdAt: true } }),
  ]);
  if (!m.shouldAutoSuspend(reports, target, { lastLiftAt: lastLift?.createdAt ?? null, now })) return false;

  const claimed = await prisma.user.updateMany({
    where: {
      id: targetId, isAdmin: false, bannedAt: null,
      OR: [{ suspendedUntil: null }, { suspendedUntil: { lte: now } }],
    },
    data: { suspendedUntil: m.FAR_FUTURE, suspensionReason: m.PENDING_REVIEW },
  });
  if (claimed.count !== 1) return false;

  const reporterCount = m.distinctOpenReporters(reports, lastLift?.createdAt ?? null).size;
  await prisma.moderationAction.create({
    data: { targetUserId: targetId, adminId: null, action: "auto_suspend", note: `${reporterCount} different reporters` },
  });
  await revokeAllSessions(targetId);
  await notifyTarget(target.email, "auto_suspend", {});
  await mailAdmins({ target, reporterCount });
  return true;
}

class ModerationError extends Error {
  constructor(status, error, code) { super(code || error); this.status = status; this.error = error; this.code = code; }
}

// Wendet eine Admin-Aktion an und schliesst ALLE offenen Reports gegen den User — atomar: schlaegt etwas fehl
// (Report schon erledigt, Bann-Konflikt), wird die Transaktion zurueckgerollt (keine Reports ohne ModerationAction).
// Rueckgabe: { ok:true, closedCount } | { ok:false, status, error, code? }
async function applyReportAction({ report, target: targetHint, adminId, value, now = new Date() }) {
  const resolution = m.resolutionFor(value.action);
  let update = null;
  let target = targetHint;

  let result;
  try {
    result = await prisma.$transaction(async (tx) => {
      // Zeilensperre (wie DELETE /auth/me): Ban und Konto-Loeschung serialisieren. Fehlende Zeile = Konto schon geloescht.
      const locked = await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${targetHint.id} FOR UPDATE`;
      if (!locked.length) throw new ModerationError(409, "This account was deleted.", "ACCOUNT_DELETED_RACE");
      // Zustand frisch lesen (Race mit parallelem Admin/Auto-Sperre)
      target = await tx.user.findUnique({
        where: { id: targetHint.id },
        select: { id: true, email: true, isAdmin: true, bannedAt: true, suspendedUntil: true, suspensionReason: true },
      });
      const can = m.canModerate(adminId, target);
      if (!can.ok) throw new ModerationError(can.status, can.error);
      const plan = m.planUserUpdate(value, now, target);
      if (!plan.ok) throw new ModerationError(plan.status, plan.error, plan.code);
      update = plan.update;

      const open = await tx.userReport.findMany({
        where: { reportedUserId: target.id, status: "open" },
        select: { id: true, reporterId: true },
      });
      const handleCheck = m.canHandleReport(adminId, report, open);
      if (!handleCheck.ok) throw new ModerationError(handleCheck.status, handleCheck.error);
      if (!open.some((r) => r.id === report.id)) throw new ModerationError(409, "This report was already handled.", "ALREADY_RESOLVED");
      // Claim: nur noch offene Reports schliessen (zwei Admins gleichzeitig → der zweite bekommt weniger/0)
      const claimed = await tx.userReport.updateMany({
        where: { id: { in: open.map((r) => r.id) }, status: "open" },
        data: { status: "closed", resolution, resolvedAt: now, resolvedById: adminId },
      });
      if (claimed.count !== open.length) throw new ModerationError(409, "This report was already handled.", "ALREADY_RESOLVED");

      if (update) await tx.user.update({ where: { id: target.id }, data: update });
      await tx.moderationAction.create({
        data: { reportId: report.id, targetUserId: target.id, adminId, action: value.action, durationDays: value.durationDays, note: value.note },
      });
      if (update && !update.bannedAt && !update.suspendedUntil) {
        await tx.moderationAction.create({
          data: { reportId: report.id, targetUserId: target.id, adminId, action: "lift", note: "Pending review ended" },
        });
      }
      return { reporterIds: [...new Set(open.map((r) => r.reporterId))], closedCount: claimed.count };
    });
  } catch (err) {
    if (err instanceof ModerationError) return { ok: false, status: err.status, error: err.error, code: err.code, gone: err.code === "ACCOUNT_DELETED_RACE" };
    if (err?.code === "P2025") return { ok: false, status: 409, error: "This account was deleted.", code: "ACCOUNT_DELETED_RACE", gone: true };
    throw err;
  }

  if (value.action === "suspend" || value.action === "ban") await revokeAllSessions(target.id);

  if (value.action === "warn" || value.action === "suspend" || value.action === "ban") {
    await notifyTarget(target.email, value.action, { reason: report.reason, until: update?.suspendedUntil ?? null });
  }
  // warn/dismiss, die eine Auto-Sperre ("pending_review") beenden, melden zusaetzlich: Konto wieder aktiv
  if ((value.action === "warn" || value.action === "dismiss") && update) {
    await notifyTarget(target.email, "lift", {});
  }
  await notifyReporters(result.reporterIds, resolution);
  return { ok: true, closedCount: result.closedCount };
}

// Aktion gegen ein GELOESCHTES Konto (nur dismiss/ban, siehe m.planDeletedAction). Schliesst alle offenen Reports
// gegen die alte ID; ban setzt DeletedAccount.bannedAt (greift ueber isBannedEmailAlias auf die E-Mail samt Aliasen).
async function applyDeletedReportAction({ report, adminId, value, now = new Date() }) {
  const resolution = m.resolutionFor(value.action);
  let result;
  try {
    result = await prisma.$transaction(async (tx) => {
      const tomb = await tx.deletedAccount.findUnique({ where: { id: report.reportedUserId } });
      const plan = m.planDeletedAction(value, tomb, now);
      if (!plan.ok) throw new ModerationError(plan.status, plan.error, plan.code);
      const open = await tx.userReport.findMany({
        where: { reportedUserId: report.reportedUserId, status: "open" },
        select: { id: true, reporterId: true },
      });
      const handleCheck = m.canHandleReport(adminId, report, open);
      if (!handleCheck.ok) throw new ModerationError(handleCheck.status, handleCheck.error);
      if (!open.some((r) => r.id === report.id)) throw new ModerationError(409, "This report was already handled.", "ALREADY_RESOLVED");
      const claimed = await tx.userReport.updateMany({
        where: { id: { in: open.map((r) => r.id) }, status: "open" },
        data: { status: "closed", resolution, resolvedAt: now, resolvedById: adminId },
      });
      if (claimed.count !== open.length) throw new ModerationError(409, "This report was already handled.", "ALREADY_RESOLVED");
      if (plan.banUpdate) {
        // updateMany statt update: wurde der Tombstone parallel entfernt, sauber abbrechen statt P2025/500
        const banned = await tx.deletedAccount.updateMany({ where: { id: tomb.id }, data: plan.banUpdate });
        if (banned.count !== 1) throw new ModerationError(409, "This account was deleted.", "ACCOUNT_DELETED");
      }
      await tx.moderationAction.create({
        data: { reportId: report.id, targetUserId: report.reportedUserId, adminId, action: value.action, note: value.note },
      });
      return { reporterIds: [...new Set(open.map((r) => r.reporterId))], closedCount: claimed.count };
    });
  } catch (err) {
    if (err instanceof ModerationError) return { ok: false, status: err.status, error: err.error, code: err.code };
    throw err;
  }
  await notifyReporters(result.reporterIds, resolution);
  return { ok: true, closedCount: result.closedCount };
}

// Retention: abgelaufene Tombstones loeschen (siehe utils/tombstones.js). Rueckgabe: Anzahl geloeschter Eintraege.
async function purgeExpiredTombstones(now = new Date()) {
  const cutoff = tomb.retentionCutoff(now);
  const candidates = await prisma.deletedAccount.findMany({
    // Vorfilter wie selectExpiredTombstones, damit dauerhaft nicht loeschbare Eintraege nicht die ersten 1000 Plaetze belegen
    where: {
      bannedAt: null,
      deletedAt: { lte: cutoff },
      AND: [
        { OR: [{ unbannedAt: null }, { unbannedAt: { lte: cutoff } }] },
        { OR: [{ suspendedUntil: null }, { suspendedUntil: { lte: now } }] },
      ],
    },
    select: { id: true, deletedAt: true, unbannedAt: true, bannedAt: true, suspendedUntil: true },
    orderBy: { deletedAt: "asc" },
    take: 1000,
  });
  if (!candidates.length) return 0;
  const open = await prisma.userReport.findMany({
    where: { status: "open", reportedUserId: { in: candidates.map((c) => c.id) } },
    select: { reportedUserId: true },
  });
  const ids = tomb.selectExpiredTombstones(candidates, open.map((o) => o.reportedUserId), now);
  if (!ids.length) return 0;
  // bannedAt-Guard erneut in der DB (parallel gesetzter Bann gewinnt)
  const res = await prisma.deletedAccount.deleteMany({ where: { id: { in: ids }, bannedAt: null } });
  return res.count;
}

// Admin entbannt die E-Mail eines geloeschten Kontos: bannedAt = null, unbannedAt = jetzt, ModerationAction "lift".
async function unbanDeletedAccount({ id, adminId, now = new Date() }) {
  try {
    await prisma.$transaction(async (tx) => {
      const t = await tx.deletedAccount.findUnique({ where: { id } });
      const reporters = t ? await tx.userReport.findMany({ where: { reportedUserId: id }, select: { reporterId: true } }) : [];
      const can = tomb.canUnbanDeleted(adminId, t, reporters.map((r) => r.reporterId));
      if (!can.ok) throw new ModerationError(can.status, can.error, can.code);
      const upd = await tx.deletedAccount.updateMany({ where: { id, bannedAt: { not: null } }, data: { bannedAt: null, unbannedAt: now } });
      if (upd.count !== 1) throw new ModerationError(409, "This email address is not banned.", "NOT_BANNED");
      await tx.moderationAction.create({ data: { targetUserId: id, adminId, action: "lift", note: "Email unbanned (deleted account)" } });
    });
  } catch (err) {
    if (err instanceof ModerationError) return { ok: false, status: err.status, error: err.error, code: err.code };
    throw err;
  }
  return { ok: true };
}

async function liftRestriction({ target, adminId }) {
  await prisma.$transaction([
    prisma.user.update({ where: { id: target.id }, data: { suspendedUntil: null, bannedAt: null, suspensionReason: null } }),
    prisma.moderationAction.create({ data: { targetUserId: target.id, adminId, action: "lift" } }),
  ]);
  await notifyTarget(target.email, "lift", {});
}

module.exports = { revokeAllSessions, autoSuspendIfNeeded, applyReportAction, applyDeletedReportAction, purgeExpiredTombstones, unbanDeletedAccount, liftRestriction, sendSafetyMail };
