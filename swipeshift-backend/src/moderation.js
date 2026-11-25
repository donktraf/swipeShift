// src/moderation.js
// DB-seitige Moderation: Aktionen anwenden, Auto-Sperre bei Mehrfach-Meldungen, Sessions widerrufen, Safety-Mails.
// Entscheidungslogik steckt rein in utils/moderation.js. Mails sind Sicherheits-Mails: laufen NICHT durch notify()
// (also unabhaengig von Benachrichtigungs-Einstellungen). Mail-Fehler werden geloggt, brechen aber nie eine Aktion ab.

const { prisma } = require("./prisma.js");
const { sendMail } = require("./mailer");
const { removeDevicesForSessions } = require("./pushDevices");
const { renderEmail, plainLine } = require("./utils/emailTemplate");
const m = require("./utils/moderation");

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
    if (err instanceof ModerationError) return { ok: false, status: err.status, error: err.error, code: err.code };
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

async function liftRestriction({ target, adminId }) {
  await prisma.$transaction([
    prisma.user.update({ where: { id: target.id }, data: { suspendedUntil: null, bannedAt: null, suspensionReason: null } }),
    prisma.moderationAction.create({ data: { targetUserId: target.id, adminId, action: "lift" } }),
  ]);
  await notifyTarget(target.email, "lift", {});
}

module.exports = { revokeAllSessions, autoSuspendIfNeeded, applyReportAction, liftRestriction, sendSafetyMail };
