// src/utils/employerJobCard.js
// Jobkarte des Arbeitgebers (GET /jobs/mine): "New Matches" + Inline-Bewerber. Rein und DB-frei → testbar.

const { computeScheduleConflicts } = require("./scheduleConflict");

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

// Zeitkonflikt je Inline-Bewerbung: Set der apply-ids, deren Worker schon einen ANDEREN angenommenen Job
// zur selben Zeit hat. `jobs` = Jobs des Employers (id, startTime, endTime), `inlineByJob` = Map(jobId → applies),
// `accepted` = gebuendelt geladene angenommene Bewerbungen der Inline-Worker ueber alle Jobs.
function inlineScheduleConflicts(jobs, inlineByJob, accepted) {
  const jobById = new Map((Array.isArray(jobs) ? jobs : []).map((j) => [j.id, j]));
  const toCheck = [];
  for (const [jobId, applies] of inlineByJob ?? []) {
    const job = jobById.get(jobId);
    if (!job) continue;
    for (const a of applies) {
      toCheck.push({ id: a.id, userId: a.userId, jobId, job: { startTime: job.startTime, endTime: job.endTime } });
    }
  }
  return computeScheduleConflicts(toCheck, accepted);
}

module.exports = { MAX_INLINE_APPLICANTS, countNewMatches, pickInlineApplies, inlineScheduleConflicts };
