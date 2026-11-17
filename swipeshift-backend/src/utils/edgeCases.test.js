const test = require("node:test");
const assert = require("node:assert/strict");
const { deriveRatingTags } = require("./ratingTags");
const { currentWeekRange } = require("./period");
const { distanceMilesBetween } = require("./haversine");
const { isCompletedJob, countCompletedJobs, truncateText } = require("./companyStats");

const all = { communication: 5, paymentFairness: 5, workEnvironment: 5, jobDescriptionAccuracy: 5, overallExperience: 5 };

test("ratingTags: genau 3 Reviews zaehlen, 2 nicht", () => {
  assert.equal(deriveRatingTags({ ...all, totalReviews: 3 }).length, 5);
  assert.deepEqual(deriveRatingTags({ ...all, totalReviews: 2 }), []);
});
test("ratingTags: 4.49 nein, 4.5 ja", () => {
  assert.deepEqual(deriveRatingTags({ ...all, communication: 4.49, totalReviews: 5 }).includes("Good Communication"), false);
  assert.equal(deriveRatingTags({ ...all, communication: 4.5, totalReviews: 5 }).includes("Good Communication"), true);
});
test("ratingTags: fehlende/ungueltige Kategorien und null", () => {
  assert.deepEqual(deriveRatingTags({ communication: 5, totalReviews: 4 }), ["Good Communication"]);
  assert.deepEqual(deriveRatingTags({ communication: "5", paymentFairness: null, totalReviews: 4 }), []);
  assert.deepEqual(deriveRatingTags({ ...all }), []); // totalReviews fehlt
  assert.deepEqual(deriveRatingTags(null), []);
  assert.deepEqual(deriveRatingTags(undefined), []);
});

test("currentWeekRange: Montag 00:00 und Sonntag 23:59:59.999", () => {
  const a = currentWeekRange(new Date(2026, 10, 16, 0, 0, 0));
  assert.deepEqual(a.since, new Date(2026, 10, 16));
  const b = currentWeekRange(new Date(2026, 10, 22, 23, 59, 59, 999));
  assert.deepEqual(b.since, new Date(2026, 10, 16));
  assert.deepEqual(b.until, new Date(2026, 10, 22, 23, 59, 59, 999));
  assert.deepEqual(a.until, b.until);
});
test("currentWeekRange: Jahreswechsel", () => {
  const r = currentWeekRange(new Date(2026, 0, 1, 10)); // Donnerstag
  assert.deepEqual(r.since, new Date(2025, 11, 29));
  assert.deepEqual(r.until, new Date(2026, 0, 4, 23, 59, 59, 999));
});
test("currentWeekRange: Sommerzeitwechsel (lokale Mitternacht bleibt erhalten)", () => {
  // Wechsel EU 29.03.2026 / US 08.03.2026 – Woche enthaelt in beiden Faellen lokale Daten
  for (const d of [new Date(2026, 2, 8, 12), new Date(2026, 2, 29, 12), new Date(2026, 9, 25, 12), new Date(2026, 10, 1, 12)]) {
    const r = currentWeekRange(d);
    assert.equal(r.since.getDay(), 1);
    assert.equal(r.since.getHours(), 0);
    assert.equal(r.until.getDay(), 0);
    assert.equal(r.until.getHours(), 23);
    assert.equal(r.until.getMinutes(), 59);
    assert.ok(r.since <= d && d <= r.until);
  }
});

test("distanceMilesBetween: fehlend, 0/0, NaN, String, Rundung", () => {
  assert.equal(distanceMilesBetween(0, 0, 0, 0), 0);
  assert.equal(distanceMilesBetween(0, 0, 0, null), null);
  assert.equal(distanceMilesBetween(NaN, 0, 0, 0), null);
  assert.equal(distanceMilesBetween(Infinity, 0, 0, 0), null);
  assert.equal(distanceMilesBetween("1", 0, 0, 0), null);
  const d = distanceMilesBetween(40.0, -74.0, 40.1, -74.0);
  assert.equal(d, Math.round(d * 10) / 10);
  assert.equal(d, 6.9);
  assert.equal(distanceMilesBetween(40, -74, 40.0001, -74), 0); // ~0.007mi → 0
});

test("companyStats: completed vs. endTime vergangen vs. cancelled", () => {
  const past = new Date(Date.now() - 86400000).toISOString();
  assert.equal(isCompletedJob({ status: "completed" }), true);
  assert.equal(isCompletedJob({ status: "published", endTime: past }), false);
  assert.equal(isCompletedJob({ status: "cancelled", endTime: past }), false);
  assert.equal(isCompletedJob(null), false);
  assert.equal(isCompletedJob(undefined), false);
  assert.equal(countCompletedJobs([{ status: "completed" }, { status: "published", endTime: past }, { status: "cancelled" }, null].filter(Boolean)), 1);
  assert.equal(countCompletedJobs(), 0);
  assert.equal(countCompletedJobs([]), 0);
});

test("truncateText: Grenze, Unicode/Emoji, null", () => {
  assert.equal(truncateText("a".repeat(120)), "a".repeat(120));
  assert.equal(truncateText("a".repeat(121)), "a".repeat(120) + "…");
  assert.equal(truncateText("hello world", 11), "hello world");
  assert.equal(truncateText("hello world foo", 11), "hello world…");
  assert.equal(truncateText(null), null);
  assert.equal(truncateText(undefined), null);
  assert.equal(truncateText(42), null);
  assert.equal(truncateText("   "), null);
  assert.equal(truncateText("Ünïcödé Straße"), "Ünïcödé Straße");
});

// truncateText schneidet an Graphem-Grenzen (keine halben Surrogatpaare)
test("truncateText: Emoji nicht zerschneiden", () => {
  const emoji = truncateText("😀".repeat(30), 5); // UTF-16: Surrogat-Paare
  assert.ok(!/[\uD800-\uDBFF]$/.test(emoji.replace(/…$/, "")), "Emoji darf nicht mitten im Surrogatpaar abgeschnitten werden");
});
