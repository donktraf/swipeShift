// src/utils/moderation.js
// Reine, DB-freie Entscheidungslogik fuer die Report-Moderation (Admin bereich in der App).

const ACTIONS = ["warn", "suspend", "ban", "dismiss"];
const SUSPEND_DAYS = [7, 30];
const AUTO_SUSPEND_THRESHOLD = 3; // verschiedene Melder mit offenen Reports
const MAX_NOTE_LENGTH = 500;
const DAY_MS = 24 * 60 * 60 * 1000;
// Auto-Sperre "bis zur Pruefung" hat kein festes Ende → Zeitpunkt weit in der Zukunft
const FAR_FUTURE = new Date("9999-12-31T00:00:00.000Z");
const PENDING_REVIEW = "pending_review";

function toMs(d) {
  if (d == null) return null;
  const t = d instanceof Date ? d.getTime() : new Date(d).getTime();
  return Number.isNaN(t) ? null : t;
}

// user: { bannedAt, suspendedUntil, suspensionReason } → { state: "none"|"suspended"|"banned", until, pendingReview, reason }
function restrictionState(user, now = new Date()) {
  if (user?.bannedAt) return { state: "banned", until: null, pendingReview: false, reason: user.suspensionReason ?? null };
  const until = toMs(user?.suspendedUntil);
  if (until !== null && until > toMs(now)) {
    const pendingReview = user.suspensionReason === PENDING_REVIEW;
    return { state: "suspended", until: pendingReview ? null : new Date(until), pendingReview, reason: user.suspensionReason ?? null };
  }
  return { state: "none", until: null, pendingReview: false, reason: null };
}

function isRestricted(user, now = new Date()) {
  return restrictionState(user, now).state !== "none";
}

// Prisma-where fuer "aktuell gesperrt oder gebannt"
function restrictedWhere(now = new Date()) {
  return { OR: [{ bannedAt: { not: null } }, { suspendedUntil: { gt: now } }] };
}

// Antwort fuer Login/Requests gesperrter Konten (kein Leak von Details ausser Enddatum)
function restrictionResponse(user, now = new Date()) {
  const s = restrictionState(user, now);
  if (s.state === "banned") {
    return { status: 403, body: { error: "This account has been permanently banned. Contact support@swipeshift.app if you think this is a mistake.", code: "ACCOUNT_BANNED" } };
  }
  if (s.state === "suspended") {
    return {
      status: 403,
      body: {
        error: s.pendingReview
          ? "This account is temporarily suspended while we review a report. Contact support@swipeshift.app if you think this is a mistake."
          : `This account is suspended until ${s.until.toISOString().slice(0, 10)}. Contact support@swipeshift.app if you think this is a mistake.`,
        code: "ACCOUNT_SUSPENDED",
        until: s.until ? s.until.toISOString() : null,
        pendingReview: s.pendingReview,
      },
    };
  }
  return null;
}

// Body → { ok, value: { action, durationDays|null, note|null } }
function validateAction(body) {
  const { action, durationDays, note } = body || {};
  if (typeof action !== "string" || !ACTIONS.includes(action)) return { ok: false, error: "Invalid action" };
  if (note !== undefined && note !== null && typeof note !== "string") return { ok: false, error: "Invalid note" };
  const trimmed = typeof note === "string" ? note.trim() : "";
  if (trimmed.length > MAX_NOTE_LENGTH) return { ok: false, error: `Note too long (max ${MAX_NOTE_LENGTH} characters)` };
  let days = null;
  if (action === "suspend") {
    if (!SUSPEND_DAYS.includes(durationDays)) return { ok: false, error: "durationDays must be 7 or 30" };
    days = durationDays;
  }
  return { ok: true, value: { action, durationDays: days, note: trimmed || null } };
}

// Darf `admin` auf `target` reagieren? (nicht auf sich selbst, nicht auf andere Admins)
function canModerate(adminId, target) {
  if (!target) return { ok: false, status: 404, error: "User not found" };
  if (target.id === adminId) return { ok: false, status: 400, error: "You can't take action on yourself" };
  if (target.isAdmin) return { ok: false, status: 403, error: "You can't take action on another admin" };
  return { ok: true };
}

// Plan fuer eine Aktion: { ok:true, update|null } oder { ok:false, status, code, error }.
// warn/dismiss aendern am Konto nichts — ausser sie beenden eine Auto-Sperre "pending_review" (Pruefung abgeschlossen).
// suspend hebt nie einen Bann auf und verkuerzt nie eine laengere Admin-Sperre (die spaetere Frist gilt);
// eine Auto-Sperre (kein festes Ende) wird durch die explizite Frist ersetzt. ban behaelt ein bestehendes bannedAt.
function planUserUpdate(value, now = new Date(), target = null) {
  const state = restrictionState(target, now);
  switch (value.action) {
    case "suspend": {
      if (state.state === "banned") {
        return { ok: false, status: 409, code: "ALREADY_BANNED", error: "This user is already banned. Lift the ban first if you want to suspend instead." };
      }
      let until = toMs(now) + value.durationDays * DAY_MS;
      if (state.state === "suspended" && !state.pendingReview && toMs(state.until) > until) until = toMs(state.until);
      return { ok: true, update: { suspendedUntil: new Date(until), suspensionReason: "admin", bannedAt: null } };
    }
    case "ban":
      return { ok: true, update: { bannedAt: target?.bannedAt ? new Date(toMs(target.bannedAt)) : new Date(toMs(now)), suspendedUntil: null, suspensionReason: "admin" } };
    default:
      return { ok: true, update: state.pendingReview ? { suspendedUntil: null, suspensionReason: null } : null };
  }
}

// Kompatibel: nur das Update (null bei Nichtstun oder abgelehnter Aktion)
function userUpdateFor(value, now = new Date(), target = null) {
  const plan = planUserUpdate(value, now, target);
  return plan.ok ? plan.update : null;
}

// Offene Bewerbungen gesperrter/gebannter Worker sind fuer Arbeitgeber unsichtbar (nicht gezaehlt, nicht gelistet).
// Angenommene bleiben sichtbar (Bezahlung!) und werden mit `restricted` markiert.
function hiddenPendingClause(now = new Date()) {
  return { status: "pending", user: restrictedWhere(now) };
}
// Relation-Filter fuer apply-Selects: { where: visibleApplyFilter() }.
// ACHTUNG: bewusst OHNE NOT ueber nullable Vergleiche. NOT(suspendedUntil > now) ist bei suspendedUntil NULL
// (Normalfall!) in SQL NULL → die Zeile fiele raus. Daher positiv formuliert:
// sichtbar = nicht pending ODER Worker weder gebannt noch (noch) gesperrt.
function visibleApplyFilter(now = new Date()) {
  return {
    OR: [
      { status: { not: "pending" } },
      { user: { bannedAt: null, OR: [{ suspendedUntil: null }, { suspendedUntil: { lte: now } }] } },
    ],
  };
}
// Kombiniert einen bestehenden apply-where mit dem Sichtbarkeitsfilter
function withVisibleApplicants(where = {}, now = new Date()) {
  return { AND: [where, visibleApplyFilter(now)] };
}

function resolutionFor(action) {
  return action === "dismiss" ? "dismissed" : "action_taken";
}

// Offene Reports (nach letztem Lift), distinct Melder. reports: [{ reporterId, createdAt, status? }]
function distinctOpenReporters(reports, lastLiftAt = null) {
  const lift = toMs(lastLiftAt);
  const ids = new Set();
  for (const r of reports || []) {
    if (r.status && r.status !== "open") continue;
    if (lift !== null && toMs(r.createdAt) <= lift) continue;
    ids.add(r.reporterId);
  }
  return ids;
}

// target: { isAdmin, bannedAt, suspendedUntil, suspensionReason }
function shouldAutoSuspend(reports, target, { lastLiftAt = null, now = new Date(), threshold = AUTO_SUSPEND_THRESHOLD } = {}) {
  if (!target || target.isAdmin) return false;
  if (isRestricted(target, now)) return false;
  return distinctOpenReporters(reports, lastLiftAt).size >= threshold;
}

// Feedback-Text fuer Melder (ohne Details)
function reporterFeedback(resolution) {
  return resolution === "dismissed"
    ? "We reviewed your report and didn't find a violation of our guidelines."
    : "We reviewed your report and took action.";
}

const REASON_LABELS = {
  harassment: "harassment", spam: "spam", inappropriate: "inappropriate content or behavior",
  safety: "a safety concern", payment: "a payment issue", other: "a violation of our guidelines",
};
function reasonLabel(reason) {
  return REASON_LABELS[reason] ?? REASON_LABELS.other;
}

function formatDate(d) {
  return new Date(d).toISOString().slice(0, 10);
}

// Mail-Inhalte fuer das betroffene Konto → { subject, heading, paragraphs }
function targetNotice(kind, { reason, until = null } = {}) {
  const why = `This follows a report about ${reasonLabel(reason)}.`;
  const help = "If you think this is a mistake, contact support@swipeshift.app.";
  switch (kind) {
    case "warn":
      return {
        subject: "A warning about your SwipeShift account",
        heading: "Warning about your account",
        paragraphs: [`Our team reviewed a report about your account and issued a warning. ${why}`, "Please follow our community guidelines. Further violations can lead to a suspension or a permanent ban.", help],
      };
    case "suspend":
      return {
        subject: "Your SwipeShift account is suspended",
        heading: "Your account is suspended",
        paragraphs: [`Your account is suspended until ${until ? formatDate(until) : "further notice"}. ${why}`, "You can't sign in until then, and your jobs and applications are hidden.", help],
      };
    case "auto_suspend":
      return {
        subject: "Your SwipeShift account is temporarily suspended",
        heading: "Your account is temporarily suspended",
        paragraphs: ["Several reports about your account came in, so we suspended it while our team reviews them. We'll let you know about the outcome.", help],
      };
    case "ban":
      return {
        subject: "Your SwipeShift account has been banned",
        heading: "Your account has been banned",
        paragraphs: [`Your account has been permanently banned. ${why}`, help],
      };
    case "lift":
      return {
        subject: "Your SwipeShift account is active again",
        heading: "Your account is active again",
        paragraphs: ["The suspension on your account has been lifted. You can sign in again."],
      };
    default:
      return null;
  }
}

module.exports = {
  ACTIONS, SUSPEND_DAYS, AUTO_SUSPEND_THRESHOLD, MAX_NOTE_LENGTH, FAR_FUTURE, PENDING_REVIEW,
  restrictionState, isRestricted, restrictedWhere, restrictionResponse,
  validateAction, canModerate, planUserUpdate, userUpdateFor, hiddenPendingClause, visibleApplyFilter, withVisibleApplicants, resolutionFor,
  distinctOpenReporters, shouldAutoSuspend, reporterFeedback, reasonLabel, targetNotice,
};
