// src/utils/applyCounts.js
// Bewerbungs-Zaehler fuer das Employer-Dashboard (rein, DB-frei → testbar).
//
// Instant-Match-Bewerbungen (autoAccepted) wurden automatisch angenommen: der Employer muss nicht
// antworten. Sie zaehlen daher NICHT als "neue/offene Bewerbung", sondern separat als Instant Match.
// Gebuchte Plaetze (Jobs filled, Assigned Workers, Open Spots, Finanzen, Spend, Reviews) zaehlen
// autoAccepted dagegen bewusst als ganz normale angenommene Worker — dort wird nichts gefiltert.

const WEEK_MS = 7 * 24 * 3_600_000;

// applies: [{ status, autoAccepted, createdAt }]
function countEmployerApplies(applies, now = new Date()) {
  const weekAgo = new Date(now.getTime() - WEEK_MS);
  const isRecent = (a) => new Date(a.createdAt) >= weekAgo;
  const manual = applies.filter((a) => !a.autoAccepted);
  return {
    // Noch zu beantworten: pending UND manuell
    newApplicants: manual.filter((a) => a.status === "pending").length,
    applicationsThisWeek: manual.filter(isRecent).length,
    instantMatchesThisWeek: applies.filter((a) => a.autoAccepted && isRecent(a)).length,
  };
}

module.exports = { countEmployerApplies };
