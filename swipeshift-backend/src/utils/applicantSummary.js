// src/utils/applicantSummary.js
// Gemeinsame, DB-freie Kurzzusammenfassung eines Bewerbers/Workers fuer den Arbeitgeber
// (Bewerberkarte, gemerkte Bewerber, Arbeitgeber-Kalender). Nutzt die bestehende Logik aus
// reviewLogic.js (null-sichere Durchschnitte), workerProfile.js und profileFields.js.

const { summarizeEmployerReviews } = require("./reviewLogic");
const { summarizeCompletedJobs, availableDays, cleanSelfRatedSkills } = require("./workerProfile");
const { cleanExperience, cleanWhitelist, AVAILABLE_TIMES } = require("./profileFields");
const { isAtLeast18 } = require("./age");

const MAX_TAGS = 3;
const LEVEL_LABEL = { lt3m: "<3 mo", m3to12: "3–12 mo", gt1y: "1+ yrs" };
const LEVEL_RANK  = { gt1y: 3, m3to12: 2, lt3m: 1 };
const WEEK_DAYS   = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"];
const SKILL_LABEL = {
  communication: "Communication",
  teamwork: "Teamwork",
  reliability: "Reliability",
  underPressure: "Under pressure",
};
const MIN_SKILL_TAG_VALUE = 4;

function round1(n) {
  return Math.round(n * 10) / 10;
}

// Gruppiert Zeilen nach row[key] → Map(key → Zeilen[]); Zeilen ohne Schluessel werden ignoriert
function groupBy(rows, key) {
  const map = new Map();
  for (const row of Array.isArray(rows) ? rows : []) {
    const k = row?.[key];
    if (k === undefined || k === null) continue;
    if (!map.has(k)) map.set(k, []);
    map.get(k).push(row);
  }
  return map;
}

// Erfahrung je Kategorie, staerkstes Level zuerst (bei Gleichstand Eingabe-Reihenfolge)
function sortedExperience(rawExperience) {
  return cleanExperience(rawExperience)
    .map((e, index) => ({ ...e, index }))
    .sort((a, b) => LEVEL_RANK[b.level] - LEVEL_RANK[a.level] || a.index - b.index)
    .map(({ category, level }) => ({ category, level, text: `${category} · ${LEVEL_LABEL[level]}` }));
}

// Bis zu MAX_TAGS Tags: zuerst Erfahrung pro Kategorie, Rest mit stark selbsteingeschaetzten Skills
function buildTags(rawExperience, rawSkills, max = MAX_TAGS) {
  const tags = sortedExperience(rawExperience).map((e) => e.text).slice(0, max);
  if (tags.length >= max) return tags;
  const skills = cleanSelfRatedSkills(rawSkills);
  if (skills) {
    const strong = Object.keys(SKILL_LABEL)
      .map((key, index) => ({ key, index, value: skills[key] }))
      .filter((s) => s.value >= MIN_SKILL_TAG_VALUE)
      .sort((a, b) => b.value - a.value || a.index - b.index);
    for (const s of strong) {
      if (tags.length >= max) break;
      tags.push(SKILL_LABEL[s.key]);
    }
  }
  return tags;
}

// ["Mon","Tue","Wed","Sat"] → "Mon–Wed, Sat" (ab 3 aufeinanderfolgenden Tagen als Bereich)
function compactDays(days) {
  const set = new Set(Array.isArray(days) ? days : []);
  const picked = WEEK_DAYS.map((d) => set.has(d));
  if (picked.every(Boolean)) return "Every day";
  const parts = [];
  let i = 0;
  while (i < 7) {
    if (!picked[i]) { i += 1; continue; }
    let j = i;
    while (j + 1 < 7 && picked[j + 1]) j += 1;
    if (j - i >= 2) parts.push(`${WEEK_DAYS[i]}–${WEEK_DAYS[j]}`);
    else for (let k = i; k <= j; k += 1) parts.push(WEEK_DAYS[k]);
    i = j + 1;
  }
  return parts.join(", ");
}

// "Mon–Fri · Morning, Evening" (null, wenn nichts angegeben ist)
function availabilityText(availability, availableTimes) {
  const days = compactDays(availableDays(availability));
  const times = cleanWhitelist(availableTimes, AVAILABLE_TIMES).map((t) => t[0].toUpperCase() + t.slice(1));
  const parts = [days, times.join(", ")].filter(Boolean);
  return parts.length ? parts.join(" · ") : null;
}

/**
 * @param {object} input
 * @param {object|null} input.worker  { dateOfBirth, experience, skills, availability, availableTimes }
 * @param {Array} input.reviews       Review-Zeilen des Workers (Kategorien, workQuality darf null sein)
 * @param {Array} input.applies       angenommene Bewerbungen { status, isPaid, job } (fuer abgeschlossene Jobs)
 */
function summarizeApplicant({ worker = null, reviews = [], applies = [], now = new Date() } = {}) {
  const review = summarizeEmployerReviews(reviews);
  const experience = sortedExperience(worker?.experience);
  return {
    ratingAverage: review.overallRating,
    reviewCount: review.reviewCount,
    completedJobs: summarizeCompletedJobs(applies, now).completedJobs,
    tags: buildTags(worker?.experience, worker?.skills),
    strongestExperience: experience[0]?.text ?? null,
    // Nur das Badge — das Alter selbst wird nie ausgeliefert
    isAdult: worker?.dateOfBirth ? isAtLeast18(worker.dateOfBirth, now) : false,
    availabilityText: availabilityText(worker?.availability, worker?.availableTimes),
    // Rohwerte fuer den Abgleich "Available for this shift" (App rechnet mit der Geraete-Zeitzone)
    availableDays: availableDays(worker?.availability),
    availableTimes: cleanWhitelist(worker?.availableTimes, AVAILABLE_TIMES),
  };
}

// Mittel der Einzel-Durchschnitte (nur Worker mit Bewertung); null, wenn keiner bewertet ist
function averageRating(summaries) {
  const values = (Array.isArray(summaries) ? summaries : [])
    .map((s) => s?.ratingAverage)
    .filter((v) => typeof v === "number");
  return values.length ? round1(values.reduce((a, b) => a + b, 0) / values.length) : null;
}

module.exports = {
  MAX_TAGS,
  groupBy,
  sortedExperience,
  buildTags,
  compactDays,
  availabilityText,
  summarizeApplicant,
  averageRating,
};
