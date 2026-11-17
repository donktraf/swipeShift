const test = require("node:test");
const assert = require("node:assert/strict");
const { deriveRatingTags, averageCategories } = require("./ratingTags");

const base = {
  communication: 4.8, paymentFairness: 4.4, workEnvironment: 4.5,
  jobDescriptionAccuracy: 3.0, overallExperience: 4.6, totalReviews: 5,
};

test("liefert Tags nur fuer Kategorien mit Durchschnitt >= 4.5", () => {
  assert.deepEqual(deriveRatingTags(base), ["Good Communication", "Friendly Team", "Great Experience"]);
});

test("Grenzwert 4.5 zaehlt, 4.4 nicht", () => {
  assert.deepEqual(deriveRatingTags({ ...base, communication: 4.4, workEnvironment: 4.5, overallExperience: 4.4 }), ["Friendly Team"]);
});

test("unter 3 Bewertungen keine Tags", () => {
  assert.deepEqual(deriveRatingTags({ ...base, totalReviews: 2 }), []);
  assert.deepEqual(deriveRatingTags({ ...base, totalReviews: 3 }).length, 3);
});

test("alle fuenf Tags in fester Reihenfolge", () => {
  const all = { communication: 5, paymentFairness: 5, workEnvironment: 5, jobDescriptionAccuracy: 5, overallExperience: 5, totalReviews: 10 };
  assert.deepEqual(deriveRatingTags(all),
    ["Good Communication", "Fair Pay", "Friendly Team", "Accurate Job Info", "Great Experience"]);
});

test("null/leere Eingabe ergibt leere Liste", () => {
  assert.deepEqual(deriveRatingTags(null), []);
  assert.deepEqual(deriveRatingTags({}), []);
});

test("averageCategories: Durchschnitt ueber alle Zeilen, null bei leerer Liste", () => {
  assert.equal(averageCategories([]), null);
  const row = (n) => ({ communication: n, paymentFairness: n, workEnvironment: n, jobDescriptionAccuracy: n, overallExperience: n });
  const out = averageCategories([row(5), row(4), row(5)]);
  assert.equal(out.totalReviews, 3);
  assert.equal(out.communication, 4.7);
  assert.equal(deriveRatingTags(out).length, 5);
});
