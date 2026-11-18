const { test } = require("node:test");
const assert = require("node:assert/strict");
const { countEmployerApplies, summarizeJobApplies } = require("./applyCounts");

const NOW = new Date("2026-11-18T12:00:00Z");
const d = (days) => new Date(NOW.getTime() - days * 86_400_000);

test("countEmployerApplies: newApplicants nur pending + manuell", () => {
  const r = countEmployerApplies([
    { status: "pending",  autoAccepted: false, createdAt: d(1) },
    { status: "pending",  autoAccepted: false, createdAt: d(30) },
    { status: "accepted", autoAccepted: false, createdAt: d(1) },
    { status: "declined", autoAccepted: false, createdAt: d(1) },
    { status: "accepted", autoAccepted: true,  createdAt: d(1) },
  ], NOW);
  assert.equal(r.newApplicants, 2);
});

test("countEmployerApplies: Wochenzaehler trennt manuell und Instant Match", () => {
  const r = countEmployerApplies([
    { status: "pending",  autoAccepted: false, createdAt: d(1) },
    { status: "accepted", autoAccepted: false, createdAt: d(10) },
    { status: "accepted", autoAccepted: true,  createdAt: d(2) },
    { status: "accepted", autoAccepted: true,  createdAt: d(3) },
    { status: "accepted", autoAccepted: true,  createdAt: d(20) },
  ], NOW);
  assert.equal(r.applicationsThisWeek, 1);
  assert.equal(r.instantMatchesThisWeek, 2);
});

test("countEmployerApplies: leer", () => {
  assert.deepEqual(countEmployerApplies([], NOW), { newApplicants: 0, applicationsThisWeek: 0, instantMatchesThisWeek: 0 });
});

test("summarizeJobApplies: applicantCount nur pending + manuell", () => {
  const r = summarizeJobApplies([
    { status: "pending",  autoAccepted: false },
    { status: "pending",  autoAccepted: false },
    { status: "accepted", autoAccepted: false },
    { status: "declined", autoAccepted: false },
    { status: "accepted", autoAccepted: true },
  ]);
  assert.deepEqual(r, { applicantCount: 2, instantMatchCount: 1, totalApplicationCount: 5 });
  assert.deepEqual(summarizeJobApplies([]), { applicantCount: 0, instantMatchCount: 0, totalApplicationCount: 0 });
});
