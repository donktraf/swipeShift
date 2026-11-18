// src/utils/responseStats.js
// "Employer response rate" + "Typical response time" fuer das Company-Profil (Worker-Sicht).
// Rein und DB-frei → testbar.
//
// Response Rate = beantwortet / (beantwortet + unbeantwortet)
//   beantwortet   = angenommen oder abgelehnt (respondedAt gesetzt ODER Status accepted/declined —
//                   letzteres deckt Altdaten von vor Einfuehrung von respondedAt ab)
//   unbeantwortet = noch "pending" UND aelter als die Kulanzfrist (frische Bewerbungen zaehlen
//                   noch nicht gegen die Firma)
// Typical Response Time = Median (Bewerbung → erste Antwort) ueber alle Bewerbungen mit respondedAt
//
// Unter MIN_SAMPLE auswertbaren Bewerbungen → null (UI zeigt "New on platform").

const GRACE_PERIOD_MS = 48 * 3600 * 1000;
const MIN_SAMPLE      = 3;

function isResponded(apply) {
  return apply.respondedAt != null || apply.status === "accepted" || apply.status === "declined";
}

function median(values) {
  if (!values.length) return null;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  return sorted.length % 2 ? sorted[mid] : (sorted[mid - 1] + sorted[mid]) / 2;
}

// applies: [{ status, createdAt, respondedAt, autoAccepted? }]
// Instant-Match-Bewerbungen (autoAccepted) werden ignoriert: sie spiegeln keine Reaktion des Employers wider.
function computeResponseStats(allApplies, now = new Date()) {
  const applies = allApplies.filter(a => !a.autoAccepted);
  const responded = applies.filter(isResponded);
  const unanswered = applies.filter(a =>
    !isResponded(a) && a.status === "pending" && now - new Date(a.createdAt) > GRACE_PERIOD_MS
  );
  const rateSample = responded.length + unanswered.length;

  const durationsHours = responded
    .filter(a => a.respondedAt)
    .map(a => (new Date(a.respondedAt) - new Date(a.createdAt)) / 3_600_000)
    .filter(h => h >= 0);

  return {
    responseRate:         rateSample >= MIN_SAMPLE ? responded.length / rateSample : null,
    responseSampleSize:   rateSample,
    typicalResponseHours: durationsHours.length >= MIN_SAMPLE
      ? Math.round(median(durationsHours) * 10) / 10
      : null,
  };
}

module.exports = { GRACE_PERIOD_MS, MIN_SAMPLE, computeResponseStats, median };
