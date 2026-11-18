const { test } = require("node:test");
const assert = require("node:assert/strict");
const { countNewMatches, pickInlineApplies, inlineScheduleConflicts } = require("./employerJobCard");

const t = (n) => new Date(Date.UTC(2026, 10, n));

test("countNewMatches: ohne seenAt alle, sonst nur spaetere (auch Instant Match)", () => {
  const applies = [
    { createdAt: t(1) }, { createdAt: t(5), autoAccepted: true }, { createdAt: t(9) },
  ];
  assert.equal(countNewMatches(applies, null), 3);
  assert.equal(countNewMatches(applies, t(5)), 1);
  assert.equal(countNewMatches(applies, t(10)), 0);
  assert.equal(countNewMatches(undefined, null), 0);
});

test("pickInlineApplies: nur pending + manuell, aelteste zuerst, max 2", () => {
  const applies = [
    { id: "a", status: "pending", createdAt: t(3) },
    { id: "b", status: "pending", createdAt: t(1) },
    { id: "c", status: "pending", createdAt: t(2) },
    { id: "d", status: "accepted", createdAt: t(0) },
    { id: "e", status: "pending", autoAccepted: true, createdAt: t(0) },
  ];
  assert.deepEqual(pickInlineApplies(applies).map((a) => a.id), ["b", "c"]);
  assert.deepEqual(pickInlineApplies(applies, 5).map((a) => a.id), ["b", "c", "a"]);
});

test("inlineScheduleConflicts: Ueberschneidung mit anderem angenommenem Job, Randfaelle", () => {
  const h = (n) => new Date(Date.UTC(2026, 10, 20, n));
  const jobs = [
    { id: "j1", startTime: h(10), endTime: h(14) },
    { id: "j2", startTime: h(9), endTime: h(11) },
  ];
  const inlineByJob = new Map([
    ["j1", [{ id: "a1", userId: "u1" }, { id: "a2", userId: "u2" }, { id: "a3", userId: "u3" }]],
    ["j2", []],
  ]);
  const accepted = [
    { id: "x1", userId: "u1", jobId: "other", job: { startTime: h(13), endTime: h(16), status: "published" } }, // Konflikt
    { id: "x2", userId: "u2", jobId: "other", job: { startTime: h(14), endTime: h(16), status: "published" } }, // angrenzend
    { id: "x3", userId: "u3", jobId: "other", job: { startTime: h(11), endTime: h(12), status: "cancelled" } }, // storniert
  ];
  const result = inlineScheduleConflicts(jobs, inlineByJob, accepted);
  assert.deepEqual([...result], ["a1"]);
  assert.equal(inlineScheduleConflicts(jobs, new Map(), accepted).size, 0);
  assert.equal(inlineScheduleConflicts(undefined, undefined, undefined).size, 0);
});
