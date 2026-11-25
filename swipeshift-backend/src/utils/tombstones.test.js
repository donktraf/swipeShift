const test = require("node:test");
const assert = require("node:assert/strict");
const t = require("./tombstones");

const now = new Date("2026-11-25T12:00:00Z");
const ago = (days) => new Date(+now - days * 86400000);

test("selectExpiredTombstones: 90 days, banned/suspended/open-report/unban rules", () => {
  assert.equal(t.TOMBSTONE_RETENTION_DAYS, 90);
  const tombs = [
    { id: "old", deletedAt: ago(91) },
    { id: "edge", deletedAt: ago(90) },
    { id: "young", deletedAt: ago(89) },
    { id: "banned", deletedAt: ago(200), bannedAt: ago(150) },
    { id: "susp", deletedAt: ago(200), suspendedUntil: new Date(+now + 1000) },
    { id: "suspExpired", deletedAt: ago(200), suspendedUntil: new Date(+now - 1000) },
    { id: "open", deletedAt: ago(200) },
    { id: "unbannedRecently", deletedAt: ago(300), unbannedAt: ago(10) },
    { id: "unbannedLongAgo", deletedAt: ago(300), unbannedAt: ago(91) },
  ];
  assert.deepEqual(t.selectExpiredTombstones(tombs, ["open"], now), ["old", "edge", "suspExpired", "unbannedLongAgo"]);
  assert.deepEqual(t.selectExpiredTombstones([], [], now), []);
});

test("retentionCutoff", () => {
  assert.equal(+t.retentionCutoff(now), +ago(90));
});

test("canUnbanDeleted: conflict of interest, not banned, missing", () => {
  assert.equal(t.canUnbanDeleted("a", null).status, 404);
  assert.equal(t.canUnbanDeleted("a", { id: "x" }).status, 409);
  assert.equal(t.canUnbanDeleted("a", { bannedAt: now }, ["a", "b"]).status, 403);
  assert.equal(t.canUnbanDeleted("a", { bannedAt: now }, ["b"]).ok, true);
});
