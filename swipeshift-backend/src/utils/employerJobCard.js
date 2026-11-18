// src/utils/employerJobCard.js
// Jobkarte des Arbeitgebers (GET /jobs/mine): "New Matches" + Inline-Bewerber. Rein und DB-frei → testbar.

const MAX_INLINE_APPLICANTS = 2;

// Neue Matches = Bewerbungen (manuell ODER automatisch angenommen), die nach dem letzten Oeffnen der
// Bewerberliste entstanden sind; ohne applicantsSeenAt zaehlen alle.
function countNewMatches(applies, seenAt) {
  const list = Array.isArray(applies) ? applies : [];
  const seen = seenAt ? new Date(seenAt).getTime() : null;
  if (seen === null || Number.isNaN(seen)) return list.length;
  return list.filter((a) => new Date(a.createdAt).getTime() > seen).length;
}

// Aelteste unbeantwortete manuelle Bewerbungen zuerst (wer am laengsten wartet), maximal `cap`.
// Gibt nur ihre ids/Reihenfolge zurueck; Profildaten werden gebuendelt nachgeladen.
function pickInlineApplies(applies, cap = MAX_INLINE_APPLICANTS) {
  return (Array.isArray(applies) ? applies : [])
    .filter((a) => !a.autoAccepted && a.status === "pending")
    .sort((a, b) => new Date(a.createdAt) - new Date(b.createdAt))
    .slice(0, cap);
}

module.exports = { MAX_INLINE_APPLICANTS, countNewMatches, pickInlineApplies };
