// src/utils/workerProfile.js
// Reine, DB-freie Aufbereitung des Worker-Profils, das ein Arbeitgeber sieht
// (GET /employer/workers/:userId). Ersetzt die frueher fest eingetragenen Beispieldaten.

const { deriveApplicationStatus } = require("./applicationStatus");
const { summarizeEmployerReviews } = require("./reviewLogic");

const RATING_KEYS = ["communication", "teamwork", "reliability", "underPressure"];

function round1(n) {
  return Math.round(n * 10) / 10;
}

// Alter in ganzen Jahren (null bei fehlendem/ungueltigem Datum)
function ageFromBirthDate(birthDate, now = new Date()) {
  if (!birthDate) return null;
  const b = new Date(birthDate);
  if (Number.isNaN(b.getTime())) return null;
  const n = new Date(now);
  let age = n.getUTCFullYear() - b.getUTCFullYear();
  const beforeBirthday =
    n.getUTCMonth() < b.getUTCMonth() ||
    (n.getUTCMonth() === b.getUTCMonth() && n.getUTCDate() < b.getUTCDate());
  if (beforeBirthday) age -= 1;
  return age >= 0 && age < 130 ? age : null;
}

// availability: [{ name: "Mon", available: true }, ...] → ["Mon", ...]
function availableDays(availability) {
  if (!Array.isArray(availability)) return [];
  return availability
    .filter((d) => d && d.available === true && typeof d.name === "string")
    .map((d) => d.name);
}

// Selbsteinschaetzung (Worker.skills, freies JSON) nur liefern, wenn alle 4 Werte Zahlen sind —
// die App erwartet sonst ein vollstaendiges Objekt und koennte das Profil nicht laden.
function cleanSelfRatedSkills(skills) {
  if (!skills || typeof skills !== "object") return null;
  const out = {};
  for (const key of RATING_KEYS) {
    const v = Number(skills[key]);
    if (!Number.isFinite(v)) return null;
    out[key] = Math.round(Math.min(Math.max(v, 0), 5));
  }
  return out;
}

function stringList(value) {
  return Array.isArray(value) ? value.filter((v) => typeof v === "string" && v.trim()) : [];
}

// Bewertungen anderer Arbeitgeber (Review-Model) → Durchschnitte.
// workQuality kann bei Bestandsdaten null sein → Durchschnitte nur ueber vorhandene Werte.
function summarizeReviews(reviews) {
  const list = Array.isArray(reviews) ? reviews : [];
  const base = summarizeEmployerReviews(list);
  const rehire = list.filter((r) => r.wouldRehire === true).length;
  return {
    reviewCount: base.reviewCount,
    overallRating: base.overallRating,
    ratings: base.ratings,
    wouldRehirePercent: list.length ? Math.round((rehire / list.length) * 100) : null,
    topWorkerCount: base.topWorkerCount,
  };
}

// Abgeschlossene Jobs (gleiche Logik wie im Worker-Kalender) gesamt + je Kategorie
function summarizeCompletedJobs(appliesWithJob, now = new Date()) {
  const list = Array.isArray(appliesWithJob) ? appliesWithJob : [];
  const byCategory = new Map();
  let completed = 0;
  for (const a of list) {
    if (!a?.job) continue;
    if (deriveApplicationStatus(a, a.job, now).displayStatus !== "completed") continue;
    completed += 1;
    const cat = a.job.category || "Other";
    byCategory.set(cat, (byCategory.get(cat) || 0) + 1);
  }
  const completedByCategory = [...byCategory.entries()]
    .map(([category, count]) => ({ category, count }))
    .sort((x, y) => y.count - x.count || x.category.localeCompare(y.category));
  return { completedJobs: completed, completedByCategory };
}

module.exports = {
  RATING_KEYS,
  ageFromBirthDate,
  availableDays,
  cleanSelfRatedSkills,
  stringList,
  summarizeReviews,
  summarizeCompletedJobs,
};
