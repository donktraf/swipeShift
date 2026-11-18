const { test } = require("node:test");
const assert = require("node:assert/strict");
const { buildPastJobs, buildAccountStatus, buildMatchHint } = require("./workerDetail");

const NOW = new Date("2026-11-18T12:00:00Z");
const day = (n) => new Date(NOW.getTime() + n * 86_400_000);
const past = (n, extra = {}, applyExtra = {}) => ({
  status: "accepted", isPaid: false, review: null, ...applyExtra,
  job: { title: `Job ${n}`, company: `Co ${n}`, startTime: day(-n), endTime: day(-n + 0.2), status: "published", ...extra },
});

test("buildPastJobs: nur abgeschlossene, neueste zuerst, max 10, Rating ohne Kommentar", () => {
  const list = [
    past(5, {}, { review: { communication: 4, teamwork: 5, reliability: 5, underPressure: 4, comment: "secret" } }),
    past(2),
    { status: "accepted", job: { title: "Future", company: "X", startTime: day(3), endTime: day(3.2), status: "published" } },
    past(7, { status: "cancelled" }),
    { status: "pending", job: past(1).job },
    ...Array.from({ length: 12 }, (_, i) => past(10 + i)),
  ];
  const r = buildPastJobs(list, NOW);
  assert.equal(r.length, 10);
  assert.equal(r[0].jobTitle, "Job 2");
  assert.equal(r[1].jobTitle, "Job 5");
  assert.equal(r[1].rating, 4.5);
  assert.equal(r[0].rating, null);
  assert.equal(JSON.stringify(r).includes("secret"), false);
  assert.ok(!r.some((x) => x.jobTitle === "Future" || x.jobTitle === "Job 7"));
});

test("buildAccountStatus", () => {
  const created = new Date("2025-03-01T00:00:00Z");
  assert.deepEqual(buildAccountStatus({ pausedAt: null, emailVerifiedAt: NOW, createdAt: created }),
    { emailVerified: true, memberSince: created });
  assert.equal("status" in buildAccountStatus({ pausedAt: NOW }), false);
  assert.equal(buildAccountStatus({}).emailVerified, false);
});

test("buildMatchHint: Kategorie, Skills, Arbeitserlaubnis, Alter", () => {
  const job = {
    category: "Events", requiredSkills: ["Teamwork", "Communication", "Working under Pressure"],
    workAuthorizationRequired: true, minAge: 18,
  };
  const worker = {
    preferredCategories: ["events"], workAuthorization: true, dateOfBirth: new Date("2000-01-01"),
    skills: { communication: 5, teamwork: 4, reliability: 3, underPressure: 2 },
  };
  const hint = buildMatchHint(job, worker, NOW);
  assert.equal(hint.text, "Category matches · 2 of 3 required skills · Work authorization ✓ · Meets minimum age");
});

test("buildMatchHint: negative Faelle und leer", () => {
  const hint = buildMatchHint(
    { category: "Retail", workAuthorizationRequired: true, minAge: 21 },
    { preferredCategories: ["Events"], workAuthorization: false, dateOfBirth: new Date("2007-01-01") }, NOW);
  assert.equal(hint.text, "Category not in preferences · Work authorization missing · Below minimum age");
  assert.equal(buildMatchHint({ category: "Retail" }, { preferredCategories: [] }, NOW), null);
  assert.equal(buildMatchHint(null, {}), null);
});
