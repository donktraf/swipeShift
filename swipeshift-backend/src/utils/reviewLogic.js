// src/utils/reviewLogic.js
// Reine, DB-freie Logik rund um Bewertungen:
//  - Durchschnitte ueber Arbeitgeber→Worker-Bewertungen (workQuality ist nullable wegen Bestandsdaten)
//  - Validierung von Entwuerfen und neuen Bewertungen
//  - "Would work here again"-Quote fuer das Firmenprofil

const EMPLOYER_RATING_KEYS = ["communication", "teamwork", "reliability", "underPressure", "workQuality"];
const MAX_COMMENT_LENGTH = 600;
// Mindestanzahl nicht-null Werte, ab der die Quote angezeigt wird (wie responseStats.MIN_SAMPLE)
const MIN_WORK_AGAIN_SAMPLE = 3;

function round1(n) {
  return Math.round(n * 10) / 10;
}

// Nur echte Bewertungen zaehlen: endliche Zahl > 0 (null/undefined/0 = nicht vorhanden)
function presentValue(v) {
  if (v === null || v === undefined || v === "") return null;
  const n = Number(v);
  return Number.isFinite(n) && n > 0 ? n : null;
}

// Gesamtwert einer Review = Mittel der vorhandenen Kategorien (ungerundet), null wenn keine
function reviewOverall(review) {
  const values = EMPLOYER_RATING_KEYS.map((k) => presentValue(review?.[k])).filter((v) => v !== null);
  return values.length ? values.reduce((a, b) => a + b, 0) / values.length : null;
}

// Durchschnitt pro Kategorie (nur ueber vorhandene Werte) + Gesamtdurchschnitt + Top-Worker-Anzahl
function summarizeEmployerReviews(reviews) {
  const list = Array.isArray(reviews) ? reviews : [];
  const ratings = {};
  for (const key of EMPLOYER_RATING_KEYS) {
    const values = list.map((r) => presentValue(r?.[key])).filter((v) => v !== null);
    ratings[key] = values.length ? round1(values.reduce((a, b) => a + b, 0) / values.length) : null;
  }
  const overalls = list.map(reviewOverall).filter((v) => v !== null);
  return {
    reviewCount: list.length,
    overallRating: overalls.length ? round1(overalls.reduce((a, b) => a + b, 0) / overalls.length) : null,
    ratings: list.length ? ratings : null,
    topWorkerCount: list.filter((r) => r?.topWorker === true).length,
  };
}

// ---- Validierung ----

function isRatingInt(v) {
  return typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 5;
}

// Entwurf: nur bekannte Felder, Werte validiert. 0 = noch nicht bewertet.
// → { ok: true, data } | { ok: false, error }
function validateDraftData(input) {
  if (!input || typeof input !== "object" || Array.isArray(input)) {
    return { ok: false, error: "Draft data must be an object" };
  }
  const data = {};
  for (const key of EMPLOYER_RATING_KEYS) {
    if (input[key] === undefined || input[key] === null) continue;
    if (!isRatingInt(input[key])) {
      return { ok: false, error: `${key} must be a whole number between 0 and 5` };
    }
    data[key] = input[key];
  }
  if (input.comment !== undefined && input.comment !== null) {
    if (typeof input.comment !== "string") return { ok: false, error: "comment must be text" };
    if (input.comment.length > MAX_COMMENT_LENGTH) {
      return { ok: false, error: `comment must be at most ${MAX_COMMENT_LENGTH} characters` };
    }
    data.comment = input.comment;
  }
  for (const key of ["wouldRehire", "topWorker"]) {
    if (input[key] === undefined || input[key] === null) continue;
    if (typeof input[key] !== "boolean") return { ok: false, error: `${key} must be true or false` };
    data[key] = input[key];
  }
  return { ok: true, data };
}

// Neue (endgueltige) Bewertung: alle 5 Kategorien Pflicht (1-5)
function validateReviewSubmission(body) {
  const parsed = validateDraftData(body);
  if (!parsed.ok) return parsed;
  for (const key of EMPLOYER_RATING_KEYS) {
    if (!parsed.data[key] || parsed.data[key] < 1) {
      return { ok: false, error: `Please rate every category (${key} is missing)` };
    }
  }
  const comment = parsed.data.comment?.trim();
  return {
    ok: true,
    data: {
      ...parsed.data,
      comment: comment ? comment : null,
      wouldRehire: parsed.data.wouldRehire ?? true,
      topWorker: parsed.data.topWorker ?? false,
    },
  };
}

// ---- Worker → Firma ----

// reviews: [{ wouldWorkAgain: true|false|null }] → { percent|null, sampleSize }
function computeWouldWorkAgain(reviews, minSample = MIN_WORK_AGAIN_SAMPLE) {
  const answered = (Array.isArray(reviews) ? reviews : []).filter((r) => typeof r?.wouldWorkAgain === "boolean");
  const yes = answered.filter((r) => r.wouldWorkAgain).length;
  return {
    percent: answered.length >= minSample ? Math.round((yes / answered.length) * 100) : null,
    sampleSize: answered.length,
  };
}

// Pruefung fuer POST /worker/reviews. → null bei OK, sonst lesbare Fehlermeldung
const WORKER_RATING_KEYS = ["communication", "paymentFairness", "workEnvironment", "jobDescriptionAccuracy", "overallExperience"];

function validateWorkerReviewBody(body) {
  if (body?.publishConsent !== true) {
    return "Please confirm that your rating is honest and may be shown on the company profile.";
  }
  if (typeof body.wouldWorkAgain !== "boolean") {
    return "Please tell us whether you would work for this company again.";
  }
  for (const key of WORKER_RATING_KEYS) {
    if (!isRatingInt(body[key]) || body[key] < 1) {
      return "Please rate every category with 1 to 5 stars.";
    }
  }
  if (body.comment != null && (typeof body.comment !== "string" || body.comment.length > 400)) {
    return "Your comment must be at most 400 characters.";
  }
  return null;
}

module.exports = {
  EMPLOYER_RATING_KEYS,
  MAX_COMMENT_LENGTH,
  MIN_WORK_AGAIN_SAMPLE,
  reviewOverall,
  summarizeEmployerReviews,
  validateDraftData,
  validateReviewSubmission,
  computeWouldWorkAgain,
  validateWorkerReviewBody,
  isRatingInt,
};
