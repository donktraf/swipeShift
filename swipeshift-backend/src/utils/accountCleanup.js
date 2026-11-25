// src/utils/accountCleanup.js — Konto-Loeschung: Job-Storno-Auswahl (rein)

const OPEN_JOB_STATUSES = ["draft", "published", "inProgress"];
const ACCOUNT_CLOSED_REASON = "The employer closed their account.";
const ACCOUNT_CLOSED_CHAT_NOTE = "The employer closed their account. This job was cancelled.";

// Jobs, die beim Loeschen des Arbeitgebers storniert werden (offen = draft/published/inProgress)
function jobsToCancel(jobs) {
  return jobs.filter((j) => OPEN_JOB_STATUSES.includes(j.status)).map((j) => j.id);
}

module.exports = { OPEN_JOB_STATUSES, ACCOUNT_CLOSED_REASON, ACCOUNT_CLOSED_CHAT_NOTE, jobsToCancel };

// ── Konto-Loeschung eines Arbeitgebers: unbezahlte Posten + Abschluss-Plan (rein, DB-frei) ──
// Regeln (Entscheidung Produkt):
//   - Blockiert wird, solange ein ANGENOMMENER Worker mindestens eine BEENDETE gebuchte Schicht hat, nicht bezahlt
//     ist (isPaid=false) und bezahlbar ist (rel.isPayable). Gilt unabhaengig vom Job-Status (auch completed).
//   - Endgueltiger No-Show: nicht bezahlbar → blockiert nicht. Offener Widerspruch gegen einen No-Show ("On hold")
//     blockiert KONSERVATIV nicht: ueber die Zahlung entscheidet ein Admin, der Employer kann sie nicht ausloesen.
//   - Cancelled Jobs zaehlen nicht.
//   - Alles bezahlt: Jobs mit beendeter gebuchter Schicht werden "completed", nur zukuenftige Schichten entfallen.

const { bookedShifts } = require("./shiftBooking");
const { isPayable } = require("./reliability");

const HOUR_MS = 3_600_000;
const FUTURE_SHIFTS_CHAT_NOTE = "The employer closed their account. Upcoming shifts of this job were cancelled.";
const COMPLETED_CHAT_NOTE = "The employer closed their account. This job is completed.";
// Grund an der Bewerbung (Apply.cancelReason) → applicationStatus zeigt ihn im Cancelled-Tab
const FUTURE_SHIFTS_REASON = "The employer closed their account.";

const toMs = (v) => { const t = v ? new Date(v).getTime() : NaN; return Number.isNaN(t) ? null : t; };

// Ende einer (aufgeloesten) Schicht in ms, Reihenfolge wie bookedEnd/bookedSpan: Schicht-endTimeISO, dann job.endTime,
// erst danach start + Dauer; unbekannt → null (gilt als nicht beendet)
function shiftEndMs(shift, job) {
  if (shift.endMs != null) return shift.endMs;
  const jobEnd = toMs(job?.endTime);
  if (jobEnd !== null) return jobEnd;
  if (shift.startMs != null) return shift.startMs + (shift.hours ?? 0) * HOUR_MS;
  return null;
}

// Aufgeteilt in beendete / zukuenftige gebuchte Schichten (shiftIds leer = alle Schichten des Jobs)
function splitBookedShifts(job, shiftIds, now = new Date()) {
  const nowMs = new Date(now).getTime();
  const ended = [], upcoming = [];
  for (const s of bookedShifts(job, shiftIds)) {
    const end = shiftEndMs(s, job);
    (end !== null && end <= nowMs ? ended : upcoming).push(s);
  }
  return { ended, upcoming };
}

/**
 * Unbezahlte Posten: [{ jobId, title, unpaidWorkers, applyIds }] je Job (nur Jobs mit Posten).
 * jobs: [{ id, title, status, shifts, startTime, endTime, applies: [{ id, status, isPaid, shiftIds, attendance, disputedAt, disputeResolvedAt }] }]
 */
function unpaidByJob(jobs, now = new Date()) {
  const out = [];
  for (const job of jobs ?? []) {
    if (job.status === "cancelled") continue;
    const items = (job.applies ?? []).filter((a) =>
      a.status === "accepted" && !a.isPaid && isPayable(a) && splitBookedShifts(job, a.shiftIds, now).ended.length > 0);
    if (items.length) out.push({ jobId: job.id, title: job.title, unpaidWorkers: items.length, applyIds: items.map((a) => a.id) });
  }
  return out;
}

// Hinweis No-Show: Ein Job, dessen beendete Schicht nur einen No-Show hat, wird trotzdem "completed" (nicht cancelled),
// damit die Zuverlaessigkeits-Historie des Workers sichtbar bleibt. Ein No-Show-Widerspruch nach der Loeschung kann
// u.U. nie mehr bezahlt werden (Employer fehlt) → Admin-Ansicht zeigt "Employer account deleted".
/**
 * Plan fuer EINEN offenen Job (draft/published/inProgress) beim Loeschen (alles bezahlt):
 *   finalStatus "completed" (mind. eine angenommene Bewerbung mit beendeter gebuchter Schicht) sonst "cancelled".
 *   Bei cancelled: applyPlans leer (bisheriges Verhalten, events.jobCancelled).
 *   Bei completed, je pending/accepted Bewerbung:
 *     pending                      → decline
 *     accepted, nur Zukunft        → decline (Schichten entfallen, Chat cancelled)
 *     accepted, gemischt           → trim (shiftIds = beendete), Chat completed
 *     accepted, nur beendete       → keep, Chat completed
 * applies: [{ id, userId, status, shiftIds }]
 */
function planJobClosure(job, applies, now = new Date()) {
  const open = (applies ?? []).filter((a) => a.status === "accepted" || a.status === "pending");
  const parts = open.map((a) => ({ a, ...splitBookedShifts(job, a.shiftIds, now) }));
  const completed = parts.some((p) => p.a.status === "accepted" && p.ended.length > 0);
  if (!completed) return { finalStatus: "cancelled", applyPlans: [] };
  const applyPlans = parts.map(({ a, ended, upcoming }) => {
    if (a.status === "pending") return { applyId: a.id, userId: a.userId, action: "decline", notify: true, kind: "pending" };
    if (!ended.length) return { applyId: a.id, userId: a.userId, action: "decline", notify: true, kind: "shifts" };
    if (upcoming.length) return { applyId: a.id, userId: a.userId, action: "trim", shiftIds: ended.map((s) => s.id), notify: true, kind: "shifts" };
    return { applyId: a.id, userId: a.userId, action: "keep", notify: false };
  });
  return { finalStatus: "completed", applyPlans };
}

module.exports.splitBookedShifts = splitBookedShifts;
module.exports.unpaidByJob = unpaidByJob;
module.exports.planJobClosure = planJobClosure;
module.exports.FUTURE_SHIFTS_CHAT_NOTE = FUTURE_SHIFTS_CHAT_NOTE;
module.exports.FUTURE_SHIFTS_REASON = FUTURE_SHIFTS_REASON;
module.exports.COMPLETED_CHAT_NOTE = COMPLETED_CHAT_NOTE;
