const { test } = require("node:test");
const assert = require("node:assert/strict");
const { countNewMatches, pickInlineApplies } = require("./employerJobCard");

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
