// src/utils/lateCancel.js
// "Kurzfristige" Absage (< 24 h vor Schichtbeginn) und deren Zaehlung. Rein, ohne Abhaengigkeiten
// (von utils/reliability.js und utils/shiftCancel.js gemeinsam genutzt → keine zirkulaere Abhaengigkeit).

const LATE_CANCEL_HOURS = 24;
const HOUR_MS = 3_600_000;

function toDate(value) {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

// Weniger als 24 h bis zum Schichtbeginn (und noch nicht begonnen) → kurzfristig
function isLateCancellation(startTime, now = new Date()) {
  const start = toDate(startTime);
  if (!start) return false;
  return start.getTime() - new Date(now).getTime() < LATE_CANCEL_HOURS * HOUR_MS;
}

/**
 * Kurzfristige Absagen einer Zeile (Apply, optional mit shiftCancellations: [{ late, cancelledAt }]) seit sinceMs.
 *   - jede kurzfristige ShiftCancellation zaehlt 1 (pro Schicht, auch bei Komplett-Absage)
 *   - Altbestand: ein vom Worker stornierter Apply OHNE ShiftCancellation-Zeilen (Storno vor Einfuehrung der
 *     Schicht-Absagen) zaehlt ueber Apply.lateCancellation genau 1
 */
function countLateCancellations(row, sinceMs) {
  const cancels = Array.isArray(row?.shiftCancellations) ? row.shiftCancellations : [];
  let n = 0;
  for (const c of cancels) {
    const at = toDate(c?.cancelledAt)?.getTime() ?? NaN;
    if (c?.late === true && at >= sinceMs) n += 1;
  }
  if (cancels.length === 0 && row?.status === "cancelled_by_worker" && row.lateCancellation === true) {
    const at = toDate(row.cancelledAt)?.getTime() ?? NaN;
    if (at >= sinceMs) n += 1;
  }
  return n;
}

module.exports = { LATE_CANCEL_HOURS, isLateCancellation, countLateCancellations };
