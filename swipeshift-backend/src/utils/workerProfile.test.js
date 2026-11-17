// src/utils/workerProfile.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  ageFromBirthDate, availableDays, summarizeReviews, summarizeCompletedJobs, cleanSelfRatedSkills, stringList,
} = require("./workerProfile");

test("cleanSelfRatedSkills: nur vollstaendige Zahlen, auf 0-5 begrenzt", () => {
  assert.deepEqual(
    cleanSelfRatedSkills({ communication: 4, teamwork: "5", reliability: 9, underPressure: 3 }),
    { communication: 4, teamwork: 5, reliability: 5, underPressure: 3 }
  );
  assert.equal(cleanSelfRatedSkills({ communication: 4, teamwork: 5 }), null);
  assert.equal(cleanSelfRatedSkills(null), null);
});

test("stringList filtert Nicht-Strings", () => {
  assert.deepEqual(stringList(["Events", 3, "", null, "Retail"]), ["Events", "Retail"]);
  assert.deepEqual(stringList("x"), []);
});

const NOW = new Date("2026-11-17T12:00:00Z");

test("ageFromBirthDate: vor/nach Geburtstag, ungueltig", () => {
  assert.equal(ageFromBirthDate("2000-11-17", NOW), 26);
  assert.equal(ageFromBirthDate("2000-11-18", NOW), 25);
  assert.equal(ageFromBirthDate("2008-12-01", NOW), 17);
  assert.equal(ageFromBirthDate(null, NOW), null);
  assert.equal(ageFromBirthDate("kaputt", NOW), null);
});

test("availableDays filtert verfuegbare Tage", () => {
  assert.deepEqual(
    availableDays([{ name: "Mon", available: true }, { name: "Tue", available: false }, { name: "Sat", available: true }]),
    ["Mon", "Sat"]
  );
  assert.deepEqual(availableDays(null), []);
});

test("summarizeReviews: leer → null-Werte", () => {
  assert.deepEqual(summarizeReviews([]), { reviewCount: 0, overallRating: null, ratings: null, wouldRehirePercent: null, topWorkerCount: 0 });
});

test("summarizeReviews: Durchschnitte + Rehire-Quote", () => {
  const s = summarizeReviews([
    { communication: 5, teamwork: 4, reliability: 5, underPressure: 4, wouldRehire: true },
    { communication: 3, teamwork: 4, reliability: 3, underPressure: 2, wouldRehire: false },
  ]);
  assert.equal(s.reviewCount, 2);
  assert.deepEqual(s.ratings, { communication: 4, teamwork: 4, reliability: 4, underPressure: 3, workQuality: null });
  assert.equal(s.overallRating, 3.8); // (4.5 + 3) / 2 = 3.75 → 3.8
  assert.equal(s.wouldRehirePercent, 50);
});

test("summarizeCompletedJobs: nur abgeschlossene, nach Kategorie", () => {
  const past = "2026-11-01T18:00:00Z";
  const future = "2026-12-01T18:00:00Z";
  const s = summarizeCompletedJobs([
    { status: "accepted", job: { category: "Events", endTime: past, status: "published" } },
    { status: "accepted", job: { category: "Events", endTime: past, status: "completed" } },
    { status: "accepted", job: { category: "Retail", endTime: past, status: "published" } },
    { status: "accepted", job: { category: "Retail", endTime: future, status: "published" } }, // noch nicht vorbei
    { status: "pending",  job: { category: "Retail", endTime: past, status: "published" } },   // nie angenommen
    { status: "accepted", job: { category: "Retail", endTime: past, status: "cancelled" } },   // storniert
  ], NOW);
  assert.equal(s.completedJobs, 3);
  assert.deepEqual(s.completedByCategory, [{ category: "Events", count: 2 }, { category: "Retail", count: 1 }]);
});
