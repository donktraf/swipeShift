const { test } = require("node:test");
const assert = require("node:assert/strict");
const { timesOverlap, computeScheduleConflicts } = require("./scheduleConflict");

const h = (n) => new Date(Date.UTC(2026, 11, 1, n));
const job = (s, e, extra = {}) => ({ startTime: h(s), endTime: h(e), ...extra });

test("timesOverlap: Ueberschneidung, Beruehrung, fehlende Zeiten", () => {
  assert.equal(timesOverlap(job(8, 12), job(10, 14)), true);
  assert.equal(timesOverlap(job(8, 12), job(12, 14)), false);
  assert.equal(timesOverlap(job(8, 12), job(9, 10)), true);
  assert.equal(timesOverlap(job(8, 12), { startTime: h(9), endTime: null }), false);
  assert.equal(timesOverlap(null, job(8, 12)), false);
});

test("computeScheduleConflicts: nur andere angenommene, nicht stornierte Jobs desselben Workers", () => {
  const applies = [
    { id: "a1", userId: "u1", jobId: "j1", job: job(8, 12) },
    { id: "a2", userId: "u2", jobId: "j1", job: job(8, 12) },
    { id: "a3", userId: "u3", jobId: "j1", job: job(8, 12) },
  ];
  const accepted = [
    { id: "x1", userId: "u1", jobId: "j9", job: job(10, 14, { status: "published" }) },
    { id: "x2", userId: "u2", jobId: "j9", job: job(10, 14, { status: "cancelled" }) },
    { id: "a3", userId: "u3", jobId: "j1", job: job(8, 12, { status: "published" }) }, // dieselbe Bewerbung
  ];
  const r = computeScheduleConflicts(applies, accepted);
  assert.deepEqual([...r], ["a1"]);
});

test("computeScheduleConflicts: leere/ungueltige Eingaben", () => {
  assert.equal(computeScheduleConflicts(null, undefined).size, 0);
});
