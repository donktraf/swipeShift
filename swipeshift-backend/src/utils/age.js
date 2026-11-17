// src/utils/age.js
// Altersprüfung (18+) — rein, ohne DB, damit testbar.

const MIN_AGE = 18;
const UNDERAGE_MESSAGE = "You must be at least 18 years old.";

/**
 * Prüft, ob jemand mit diesem Geburtsdatum an `now` mindestens 18 ist.
 * Verglichen wird kalendertaggenau in UTC ("yyyy-MM-dd" wird von JS als UTC gelesen).
 * @param {string|Date} date - Geburtsdatum (ISO-String oder Date)
 * @param {Date} [now]
 * @returns {boolean} false bei ungültigem Datum
 */
function isAtLeast18(date, now = new Date()) {
  // Strings: nur 'yyyy-MM-dd' zaehlt (Uhrzeit/Zeitzone wuerde den Stichtag verschieben)
  const dob = date instanceof Date ? date : new Date(String(date).slice(0, 10));
  if (Number.isNaN(dob.getTime())) return false;
  const cutoff = Date.UTC(now.getUTCFullYear() - MIN_AGE, now.getUTCMonth(), now.getUTCDate());
  return dob.getTime() <= cutoff;
}

module.exports = { isAtLeast18, MIN_AGE, UNDERAGE_MESSAGE };
