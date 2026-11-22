// src/utils/scheduleConflict.js
// Zeitkonflikt eines Bewerbers (Employer-Sicht) und beim Bewerben: hat der Worker schon einen ANDEREN angenommenen Job,
// dessen GEBUCHTE Schichten sich mit den (angefragten) Schichten dieses Jobs ueberschneiden? Verglichen werden die
// Schicht-Intervalle (utils/shiftBooking.js), nur ohne Schichtzeiten das Fenster startTime/endTime des Jobs.
// Rein und DB-frei → testbar (Vergleich in UTC genuegt).
const { bookedIntervals } = require("./shiftBooking");

function toMs(value) {
  if (!value) return null;
  const t = new Date(value).getTime();
  return Number.isNaN(t) ? null : t;
}

// Halboffene Intervalle: direkt aneinandergrenzende Schichten (Ende == Start) sind KEIN Konflikt
function timesOverlap(a, b) {
  const aStart = toMs(a?.startTime), aEnd = toMs(a?.endTime);
  const bStart = toMs(b?.startTime), bEnd = toMs(b?.endTime);
  if (aStart === null || aEnd === null || bStart === null || bEnd === null) return false;
  return aStart < bEnd && bStart < aEnd;
}

// Ueberschneiden sich zwei Intervall-Listen [{ startMs, endMs }]? (halboffen)
function intervalsOverlap(aList, bList) {
  return aList.some((a) => bList.some((b) => a.startMs < b.endMs && b.startMs < a.endMs));
}

/**
 * @param {Array} applies  zu pruefende Bewerbungen { id, userId, jobId, shiftIds?, job: { startTime, endTime, shifts? } }
 * @param {Array} accepted angenommene Bewerbungen derselben Worker { id, userId, jobId, shiftIds?, job: { startTime, endTime, shifts?, status } }
 *                         (shiftIds leer/fehlend = alle Schichten des Jobs)
 * @returns {Set<string>} IDs der Bewerbungen mit Zeitkonflikt
 */
function computeScheduleConflicts(applies, accepted) {
  const byUser = new Map();
  for (const a of Array.isArray(accepted) ? accepted : []) {
    if (!a?.job || a.job.status === "cancelled") continue;
    if (!byUser.has(a.userId)) byUser.set(a.userId, []);
    byUser.get(a.userId).push(a);
  }
  const conflicts = new Set();
  for (const apply of Array.isArray(applies) ? applies : []) {
    const others = byUser.get(apply?.userId) ?? [];
    const mine = bookedIntervals(apply?.job, apply?.shiftIds);
    if (others.some((o) => o.id !== apply.id && o.jobId !== apply.jobId && intervalsOverlap(mine, bookedIntervals(o.job, o.shiftIds)))) {
      conflicts.add(apply.id);
    }
  }
  return conflicts;
}

module.exports = { timesOverlap, intervalsOverlap, computeScheduleConflicts };
