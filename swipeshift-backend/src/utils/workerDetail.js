// src/utils/workerDetail.js
// Zusatzbloecke fuers Detail-Profil eines Workers aus Arbeitgeber-Sicht (GET /employer/workers/:userId):
// Past Jobs, Account-Status, Match-Hinweis zu einem Job. Rein und DB-frei → testbar.

const { deriveApplicationStatus } = require("./applicationStatus");
const { reviewOverall } = require("./reviewLogic");
const { ageFromBirthDate, cleanSelfRatedSkills } = require("./workerProfile");

const MAX_PAST_JOBS = 10;
const MIN_SKILL_VALUE = 4; // ab dieser Selbsteinschaetzung (1-5) gilt ein Skill als "vorhanden"
// Job-Skill-Label (PostJob) → Schluessel in Worker.skills
const SKILL_KEY = {
  "communication": "communication",
  "teamwork": "teamwork",
  "reliability": "reliability",
  "working under pressure": "underPressure",
};

function round1(n) {
  return Math.round(n * 10) / 10;
}

/**
 * Letzte abgeschlossene Jobs, bei denen der Worker angenommen war — mit der Bewertung, die der Employer
 * dieses Jobs vergeben hat (nur die Zahl, bewusst kein Kommentar).
 * @param {Array} accepted { status, isPaid, review, job: { title, company, startTime, endTime, status, cancellationReason } }
 */
function buildPastJobs(accepted, now = new Date(), limit = MAX_PAST_JOBS) {
  return (Array.isArray(accepted) ? accepted : [])
    .filter((a) => a?.job && deriveApplicationStatus(a, a.job, now).displayStatus === "completed")
    .map((a) => {
      const date = a.job.startTime ?? a.job.endTime ?? null;
      const overall = a.review ? reviewOverall(a.review) : null;
      return {
        companyName: a.job.company ?? "",
        jobTitle: a.job.title ?? "",
        date,
        rating: overall === null ? null : round1(overall),
        _sort: new Date(a.job.endTime ?? a.job.startTime ?? 0).getTime(),
      };
    })
    .sort((a, b) => b._sort - a._sort)
    .slice(0, limit)
    .map(({ _sort, ...rest }) => rest);
}

function buildAccountStatus(user) {
  return {
    // Bewusst KEIN pausedAt/Status: "Konto pausieren" ist eine Privatsphaere-Einstellung des Workers
    emailVerified: !!user?.emailVerifiedAt,
    memberSince: user?.createdAt ?? null,
  };
}

/**
 * Einfacher Vergleich Job ↔ Worker (kein Scoring). Gibt null zurueck, wenn nichts vergleichbar ist.
 * @returns {{ text: string, parts: string[] } | null}
 */
function buildMatchHint(job, worker, now = new Date()) {
  if (!job) return null;
  const parts = [];

  const preferred = (Array.isArray(worker?.preferredCategories) ? worker.preferredCategories : [])
    .map((c) => String(c).toLowerCase());
  if (job.category && preferred.length) {
    parts.push(preferred.includes(String(job.category).toLowerCase()) ? "Category matches" : "Category not in preferences");
  }

  const required = Array.isArray(job.requiredSkills) ? job.requiredSkills : [];
  const skills = cleanSelfRatedSkills(worker?.skills);
  if (required.length && skills) {
    const met = required.filter((s) => {
      const key = SKILL_KEY[String(s).toLowerCase()];
      return key && skills[key] >= MIN_SKILL_VALUE;
    }).length;
    parts.push(`${met} of ${required.length} required skills`);
  }

  if (job.workAuthorizationRequired) {
    parts.push(worker?.workAuthorization ? "Work authorization ✓" : "Work authorization missing");
  }

  if (typeof job.minAge === "number" && job.minAge > 0) {
    const age = ageFromBirthDate(worker?.dateOfBirth, now);
    if (age !== null) parts.push(age >= job.minAge ? "Meets minimum age" : "Below minimum age");
  }

  return parts.length ? { text: parts.join(" · "), parts } : null;
}

module.exports = { MAX_PAST_JOBS, buildPastJobs, buildAccountStatus, buildMatchHint };
