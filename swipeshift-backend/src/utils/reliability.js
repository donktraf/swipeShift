// src/utils/reliability.js
// Zuverlaessigkeit eines Workers (Anwesenheit, No-Shows, kurzfristige Stornos). Rein und DB-frei → testbar.
//
// Regeln (Produktentscheidung):
//   - Der EMPLOYER erfasst nach Schichtende je angenommenem Worker: attended | late | no_show.
//     "Late" = mehr als 15 Minuten nach Schichtbeginn eingetroffen.
//   - Erfasst er innerhalb von 48 h nach Schichtende nichts, zaehlt es automatisch als "attended" (Scheduler).
//   - Der Worker kann EINMAL widersprechen (Notiz <= 300 Zeichen); bis zur Admin-Entscheidung zaehlt der Eintrag nicht.
//   - Kurzfristige Stornierung = angenommene Schicht < 24 h vor Beginn storniert.
//   - Prozentwert erst ab 3 abgeschlossenen Schichten, davor "New".

const LATE_AFTER_MINUTES = 15;
const LATE_CANCEL_HOURS = 24;
const AUTO_ATTEND_HOURS = 48;
const WINDOW_DAYS = 365;          // Worker-/Employer-Ansicht: letzte 12 Monate
const ADMIN_WINDOW_DAYS = 90;     // Admin-Hinweis: letzte 90 Tage
const MIN_SHIFTS_FOR_RATE = 3;
const MAX_NOTE_LENGTH = 300;
const DISPUTE_WINDOW_DAYS = 14;   // Einspruch nur bis 14 Tage nach der Erfassung
const ATTENDANCE_REMINDER_AFTER_HOURS = 24; // Employer-Erinnerung, wenn danach noch Eintraege fehlen
const ADMIN_NO_SHOW_THRESHOLD = 2;
const ADMIN_LATE_CANCEL_THRESHOLD = 3;

const HOUR_MS = 3_600_000;
const DAY_MS = 24 * HOUR_MS;

const ATTENDANCE_VALUES = ["attended", "late", "no_show"];
const CANCELLED_BY_WORKER = "cancelled_by_worker";
// Status, die in Bewerberlisten des Employers erscheinen (storniert-vom-Worker ist dort nicht mehr relevant)
const LISTED_STATUSES = ["pending", "accepted", "declined"];

const GUIDANCE_TEXT = "Late = arrived more than 15 minutes after the start";

function toDate(value) {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

function normalizeAttendance(value) {
  return typeof value === "string" && ATTENDANCE_VALUES.includes(value) ? value : null;
}

// Weniger als 24 h bis zum Schichtbeginn (und noch nicht begonnen) → kurzfristig
function isLateCancellation(startTime, now = new Date()) {
  const start = toDate(startTime);
  if (!start) return false;
  const ms = start.getTime() - new Date(now).getTime();
  return ms < LATE_CANCEL_HOURS * HOUR_MS;
}

// Darf der Worker diese Schicht stornieren? → { ok } | { ok:false, status, code, error }
function evaluateWorkerCancel(apply, job, now = new Date()) {
  if (!apply || apply.status !== "accepted") {
    return { ok: false, status: 400, code: "NOT_ACCEPTED", error: "Only confirmed shifts can be cancelled." };
  }
  if (!job || job.status === "cancelled" || job.status === "completed") {
    return { ok: false, status: 409, code: "JOB_CLOSED", error: "This job is already closed." };
  }
  const start = toDate(job.startTime);
  if (!start || start.getTime() <= new Date(now).getTime()) {
    return { ok: false, status: 409, code: "SHIFT_STARTED", error: "This shift has already started." };
  }
  return { ok: true, lateCancellation: isLateCancellation(start, now) };
}

function canWorkerCancel(apply, job, now = new Date()) {
  return evaluateWorkerCancel(apply, job, now).ok;
}

function attendanceDeadline(endTime) {
  const end = toDate(endTime);
  return end ? new Date(end.getTime() + AUTO_ATTEND_HOURS * HOUR_MS) : null;
}

// Zustand der Anwesenheitserfassung einer angenommenen Bewerbung
//   ended       Schicht ist vorbei
//   canRecord   Employer darf eintragen/aendern (vorbei, < 48 h, kein offener Einspruch, Job nicht storniert)
//   pending     noch kein Eintrag, Frist laeuft (Employer soll handeln)
//   autoDue     kein Eintrag und Frist abgelaufen → Scheduler setzt "attended"
function attendanceState(apply, job, now = new Date()) {
  const nowMs = new Date(now).getTime();
  const end = toDate(job?.endTime);
  const deadline = attendanceDeadline(job?.endTime);
  const base = { ended: false, canRecord: false, pending: false, autoDue: false, deadline };
  if (!apply || apply.status !== "accepted" || !end) return base;
  if (job?.status === "cancelled" || job?.status === "draft") return base;
  if (end.getTime() > nowMs) return base;
  const inWindow = nowMs < deadline.getTime();
  const hasEntry = !!apply.attendance;
  return {
    ended: true,
    canRecord: inWindow && !apply.disputedAt,
    pending: inWindow && !hasEntry,
    autoDue: !inWindow && !hasEntry,
    deadline,
  };
}

// "pending" (Admin muss entscheiden) | "resolved" | null
function disputeStatus(apply) {
  if (!apply?.disputedAt) return null;
  return apply.disputeResolvedAt ? "resolved" : "pending";
}

// Einspruch nur gegen "late"/"no_show", nur einmal, nur bei angenommener Schicht, nur bis 14 Tage nach der Erfassung
function canDispute(apply, now = new Date()) {
  if (!apply || apply.status !== "accepted") return false;
  if (apply.attendance !== "late" && apply.attendance !== "no_show") return false;
  if (apply.disputedAt) return false;
  const setAt = toDate(apply.attendanceSetAt);
  if (!setAt) return false;
  return new Date(now).getTime() - setAt.getTime() <= DISPUTE_WINDOW_DAYS * DAY_MS;
}

// ── Abrechnung: No-Shows werden nicht bezahlt/berechnet ──
// Einspruch offen gegen einen No-Show → noch nicht bezahlbar ("Under review"); bei Entscheidung
// auf attended/late wird der Worker wieder normal bezahlbar.
function isNoShowUnderReview(apply) {
  return apply?.attendance === "no_show" && !!apply.disputedAt && !apply.disputeResolvedAt;
}
// Endgueltiger No-Show: weder bezahlbar noch in den Kosten
function isFinalNoShow(apply) {
  return apply?.attendance === "no_show" && !isNoShowUnderReview(apply);
}
function isPayable(apply) {
  return apply?.attendance !== "no_show";
}
// Zeilen, die in Kosten/Verdienst zaehlen: alles ausser No-Shows. Ein No-Show unter Einspruch wird
// ebenfalls noch NICHT berechnet ("On hold", getrennt ausgewiesen) — erst nach Entscheidung (attended/late → berechnet).
function billable(applies) {
  return (Array.isArray(applies) ? applies : []).filter(isPayable);
}
// Zeilen "On hold": No-Show unter Einspruch
function onHold(applies) {
  return (Array.isArray(applies) ? applies : []).filter(isNoShowUnderReview);
}
// Zahlungsstatus fuer den Payment-Screen: paid | no_show | under_review | pending
function paymentState(apply) {
  if (isNoShowUnderReview(apply)) return "under_review";
  if (isFinalNoShow(apply)) return "no_show";
  return apply?.isPaid ? "paid" : "pending";
}

// → { ok, note } | { ok:false, error }
function validateDisputeNote(value) {
  if (typeof value !== "string") return { ok: false, error: "Please add a short note." };
  const note = value.replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/g, "").trim();
  if (!note) return { ok: false, error: "Please add a short note." };
  if (note.length > MAX_NOTE_LENGTH) return { ok: false, error: `The note can have at most ${MAX_NOTE_LENGTH} characters.` };
  return { ok: true, note };
}

// Admin-Entscheidung: { uphold: true } | { attendance: "attended"|"late"|"no_show" }
function parseDisputeResolution(body) {
  if (body?.uphold === true) return { ok: true, resolution: "upheld", attendance: null };
  const attendance = normalizeAttendance(body?.attendance);
  if (attendance) return { ok: true, resolution: "changed", attendance };
  return { ok: false, error: "Send { uphold: true } or { attendance: attended|late|no_show }." };
}

function pluralize(n, one, many) {
  return `${n} ${n === 1 ? one : many}`;
}

/**
 * @param {Array} rows { status, attendance, disputedAt, disputeResolvedAt, lateCancellation, cancelledAt, job: { endTime } }
 * @returns {{ finishedShifts, attended, late, noShows, lateCancellations, showUpRate, isNew, text }}
 */
function summarizeReliability(rows, now = new Date(), { windowDays = WINDOW_DAYS } = {}) {
  const since = new Date(now).getTime() - windowDays * DAY_MS;
  let attended = 0, late = 0, noShows = 0, lateCancellations = 0;
  for (const r of Array.isArray(rows) ? rows : []) {
    if (!r) continue;
    if (r.status === CANCELLED_BY_WORKER) {
      const at = toDate(r.cancelledAt);
      if (r.lateCancellation === true && at && at.getTime() >= since) lateCancellations += 1;
      continue;
    }
    if (r.status !== "accepted" || !normalizeAttendance(r.attendance)) continue;
    if (r.disputedAt && !r.disputeResolvedAt) continue; // Einspruch offen → zaehlt noch nicht
    const end = toDate(r.job?.endTime);
    if (!end || end.getTime() < since || end.getTime() > new Date(now).getTime()) continue;
    if (r.attendance === "attended") attended += 1;
    else if (r.attendance === "late") late += 1;
    else noShows += 1;
  }
  const finishedShifts = attended + late + noShows;
  const isNew = finishedShifts < MIN_SHIFTS_FOR_RATE;
  const showUpRate = isNew ? null : Math.round(((attended + late) / finishedShifts) * 100);
  return {
    finishedShifts, attended, late, noShows, lateCancellations, showUpRate, isNew,
    text: reliabilityText({ showUpRate, isNew, late, noShows, lateCancellations }),
  };
}

// "96% showed up · 1 late · 0 late cancellations" bzw. "New" (mit auffaelligen Zaehlern, falls vorhanden)
function reliabilityText({ showUpRate, isNew, late, noShows, lateCancellations }) {
  if (isNew) {
    const notes = [];
    if (noShows > 0) notes.push(pluralize(noShows, "no-show", "no-shows"));
    if (lateCancellations > 0) notes.push(pluralize(lateCancellations, "late cancellation", "late cancellations"));
    return ["New", ...notes].join(" · ");
  }
  const parts = [`${showUpRate}% showed up`, `${late} late`];
  if (noShows > 0) parts.push(pluralize(noShows, "no-show", "no-shows"));
  parts.push(pluralize(lateCancellations, "late cancellation", "late cancellations"));
  return parts.join(" · ");
}

// Admin-Hinweis: >= 2 No-Shows ODER >= 3 kurzfristige Stornos in den letzten 90 Tagen
function isConspicuous(summary) {
  return !!summary && (summary.noShows >= ADMIN_NO_SHOW_THRESHOLD || summary.lateCancellations >= ADMIN_LATE_CANCEL_THRESHOLD);
}

// Jobs, deren Schichtende 24–48 h zurueckliegt (Employer-Erinnerung, solange das 48-h-Fenster noch offen ist)
function attendanceReminderWindow(now = new Date()) {
  const n = new Date(now).getTime();
  return { endedBefore: new Date(n - ATTENDANCE_REMINDER_AFTER_HOURS * HOUR_MS), endedAfter: new Date(n - AUTO_ATTEND_HOURS * HOUR_MS) };
}

// Prisma-where (rein positiv formuliert, kein NOT ueber nullable Spalten): Zeilen, die in die Zusammenfassung eingehen koennen
function reliabilityRowsWhere(now = new Date(), windowDays = WINDOW_DAYS) {
  const since = new Date(new Date(now).getTime() - windowDays * DAY_MS);
  return {
    OR: [
      { status: "accepted", attendance: { in: ATTENDANCE_VALUES }, job: { endTime: { gte: since, lte: new Date(now) } } },
      { status: CANCELLED_BY_WORKER, lateCancellation: true, cancelledAt: { gte: since } },
    ],
  };
}

module.exports = {
  LATE_AFTER_MINUTES, LATE_CANCEL_HOURS, AUTO_ATTEND_HOURS, WINDOW_DAYS, ADMIN_WINDOW_DAYS, MIN_SHIFTS_FOR_RATE,
  MAX_NOTE_LENGTH, DISPUTE_WINDOW_DAYS, ATTENDANCE_REMINDER_AFTER_HOURS, ADMIN_NO_SHOW_THRESHOLD, ADMIN_LATE_CANCEL_THRESHOLD,
  ATTENDANCE_VALUES, CANCELLED_BY_WORKER, LISTED_STATUSES, GUIDANCE_TEXT,
  normalizeAttendance, isLateCancellation, evaluateWorkerCancel, canWorkerCancel, attendanceDeadline, attendanceState,
  disputeStatus, canDispute, isNoShowUnderReview, isFinalNoShow, isPayable, billable, onHold, paymentState, attendanceReminderWindow, validateDisputeNote, parseDisputeResolution,
  summarizeReliability, reliabilityText, isConspicuous, reliabilityRowsWhere,
};
