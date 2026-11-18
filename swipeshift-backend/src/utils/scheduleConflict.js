// src/utils/scheduleConflict.js
// Zeitkonflikt eines Bewerbers (Employer-Sicht): hat der Worker schon einen ANDEREN angenommenen Job,
// dessen Zeitraum sich mit diesem Job ueberschneidet? Rein und DB-frei → testbar (Vergleich in UTC genuegt).

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

/**
 * @param {Array} applies  zu pruefende Bewerbungen { id, userId, jobId, job: { startTime, endTime } }
 * @param {Array} accepted angenommene Bewerbungen derselben Worker { id, userId, jobId, job: { startTime, endTime, status } }
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
    if (others.some((o) => o.id !== apply.id && o.jobId !== apply.jobId && timesOverlap(apply.job, o.job))) {
      conflicts.add(apply.id);
    }
  }
  return conflicts;
}

module.exports = { timesOverlap, computeScheduleConflicts };
