// src/utils/ratingTags.js
// Rating-Tags im Firmenprofil, abgeleitet aus den WorkerReview-Kategoriedurchschnitten.
// Rein und DB-frei → testbar.
//
// Ein Tag erscheint nur bei genug Bewertungen (>= MIN_REVIEWS) und einem
// Kategorie-Durchschnitt >= MIN_AVERAGE. Die Reihenfolge der Tags ist fest.

const MIN_REVIEWS = 3;
const MIN_AVERAGE = 4.5;

const TAG_BY_CATEGORY = [
  ["communication",          "Good Communication"],
  ["paymentFairness",        "Fair Pay"],
  ["workEnvironment",        "Friendly Team"],
  ["jobDescriptionAccuracy", "Accurate Job Info"],
  ["overallExperience",      "Great Experience"],
];

// breakdown: { communication, paymentFairness, ..., totalReviews } oder null
function deriveRatingTags(breakdown) {
  if (!breakdown || !(breakdown.totalReviews >= MIN_REVIEWS)) return [];
  return TAG_BY_CATEGORY
    .filter(([key]) => typeof breakdown[key] === "number" && breakdown[key] >= MIN_AVERAGE)
    .map(([, tag]) => tag);
}

// Kategorie-Durchschnitte (auf 0,1 gerundet, wie im Firmenprofil angezeigt) ueber ALLE Reviews.
// rows: [{ communication, paymentFairness, ... }] → breakdown fuer deriveRatingTags oder null
function averageCategories(rows = []) {
  if (!rows.length) return null;
  const avg = (key) => Math.round((rows.reduce((s, r) => s + (r[key] ?? 0), 0) / rows.length) * 10) / 10;
  const result = { totalReviews: rows.length };
  for (const [key] of TAG_BY_CATEGORY) result[key] = avg(key);
  return result;
}

module.exports = { MIN_REVIEWS, MIN_AVERAGE, deriveRatingTags, averageCategories };
