// src/utils/shiftCancel.js
// Einzelne gebuchte Schicht absagen: Teil- vs. Komplett-Absage, "kurzfristig" pro Schicht, Zaehlung. Rein und DB-frei.
//
// Regeln:
//   - Nur angenommene Bewerbung, Job nicht geschlossen, Schicht gebucht und noch nicht begonnen.
//   - Kurzfristig = < 24 h vor Beginn DIESER Schicht (gleiche Regel wie beim Komplett-Storno).
//   - Bleibt danach keine gebuchte Schicht → Bewerbung zurueckgezogen (cancelled_by_worker); Apply.lateCancellation =
//     diese Absage kurzfristig ODER eine fruehere Teil-Absage war es (Anzeige). Gezaehlt wird pro Schicht ueber
//     ShiftCancellation (utils/lateCancel.js); auch ein Komplett-Storno legt je gebuchter Schicht eine Zeile an.

const { bookedShifts } = require("./shiftBooking");
const { isLateCancellation, countLateCancellations } = require("./lateCancel");

const HOUR_MS = 3_600_000;

// Abgesagte Schicht samt Kennzahlen; startMs = null → Beginn unbekannt (nicht per Einzel-Absage stornierbar)
function startedOrUnknown(shift, nowMs) {
  return shift.startMs === null || shift.startMs <= nowMs;
}

/**
 * @param {{status:string, shiftIds?:string[]}} apply
 * @param {object} job  { status, shifts, startTime, endTime }
 * @param {string} shiftId
 * @param {{priorLate?: boolean, now?: Date}} opts  priorLate = frueherer kurzfristiger Teil-Absage dieser Bewerbung
 * @returns {{ok:true, shift, late:boolean, isLast:boolean, remainingIds:string[], bookedIds:string[], applyLate:boolean}
 *          |{ok:false, status:number, code:string, error:string}}
 */
function evaluateShiftCancel(apply, job, shiftId, { priorLate = false, now = new Date() } = {}) {
  if (!apply || apply.status !== "accepted") {
    return { ok: false, status: 400, code: "NOT_ACCEPTED", error: "Only confirmed shifts can be cancelled." };
  }
  if (!job || job.status === "cancelled" || job.status === "completed") {
    return { ok: false, status: 409, code: "JOB_CLOSED", error: "This job is already closed." };
  }
  const booked = bookedShifts(job, apply.shiftIds);
  const shift = booked.find((s) => s.id === shiftId);
  if (!shift) return { ok: false, status: 404, code: "SHIFT_NOT_BOOKED", error: "This shift is not part of your booking." };
  const nowMs = new Date(now).getTime();
  if (startedOrUnknown(shift, nowMs)) {
    return { ok: false, status: 409, code: "SHIFT_STARTED", error: "This shift has already started." };
  }
  const late = isLateCancellation(new Date(shift.startMs), now);
  const bookedIds = booked.map((s) => s.id);
  const remainingIds = bookedIds.filter((id) => id !== shiftId);
  return {
    ok: true, shift, late, isLast: remainingIds.length === 0, remainingIds, bookedIds,
    applyLate: late || priorLate === true,
  };
}

// Pro gebuchter Schicht fuer die Clients: canCancel + lateIfCancelledNow (Anzeige; erlaubt ist, was evaluateShiftCancel erlaubt)
function describeBookedForCancel(apply, job, now = new Date()) {
  const nowMs = new Date(now).getTime();
  const open = !!apply && apply.status === "accepted" && !!job && job.status !== "cancelled" && job.status !== "completed";
  return bookedShifts(job, apply?.shiftIds).map((s) => {
    const canCancel = open && !startedOrUnknown(s, nowMs);
    return {
      id: s.id, date: s.date, timeRange: s.timeRange,
      startTime: s.startMs !== null ? new Date(s.startMs).toISOString() : null,
      endTime: s.endMs !== null ? new Date(s.endMs).toISOString() : null,
      canCancel,
      lateIfCancelledNow: canCancel ? s.startMs - nowMs < 24 * HOUR_MS : false,
    };
  });
}

// "Thu, Nov 19 · 09:00–13:00" fuer Chat/Benachrichtigung
function shiftLabel(shift) {
  const parts = [shift?.date, shift?.timeRange].filter(Boolean);
  return parts.length ? parts.join(" ") : "a shift";
}

module.exports = { evaluateShiftCancel, describeBookedForCancel, shiftLabel, countLateCancellations };
