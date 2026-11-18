const { test } = require("node:test");
const assert = require("node:assert/strict");
const { setBounded, shouldWriteTimeZone } = require("./boundedCache");

test("setBounded: Obergrenze, aeltester fliegt raus, Zugriff erneuert", () => {
  const m = new Map();
  setBounded(m, "a", 1, 3); setBounded(m, "b", 2, 3); setBounded(m, "c", 3, 3);
  setBounded(m, "a", 10, 3); // a wird jung
  setBounded(m, "d", 4, 3);  // b fliegt
  assert.deepEqual([...m.keys()], ["c", "a", "d"]);
  assert.equal(m.get("a"), 10);
});

test("shouldWriteTimeZone: erste Zone, gleiche Zone, Aenderung mit Drosselung", () => {
  const T = 1_000_000;
  assert.equal(shouldWriteTimeZone(undefined, "UTC", T), true);
  assert.equal(shouldWriteTimeZone({ zone: "UTC", at: T }, "UTC", T + 99 * 60000), false);
  assert.equal(shouldWriteTimeZone({ zone: "UTC", at: T }, "Europe/Berlin", T + 60000), false);
  assert.equal(shouldWriteTimeZone({ zone: "UTC", at: T }, "Europe/Berlin", T + 10 * 60000), true);
  assert.equal(shouldWriteTimeZone(undefined, null, T), false);
});
