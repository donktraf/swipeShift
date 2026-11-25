const { test } = require("node:test");
const assert = require("node:assert/strict");
const r = require("./retention");

const NOW = new Date("2026-11-25T12:00:00Z");
const daysAgo = (d) => new Date(NOW.getTime() - d * r.DAY_MS);

test("Konstanten", () => {
  assert.equal(r.REPORT_RETENTION_DAYS, 730);
  assert.equal(r.SESSION_RETENTION_DAYS, 30);
});

test("isSessionPurgeable: 30 Tage nach Ablauf bzw. Widerruf", () => {
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(31), revokedAt: null }, NOW), true);
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(30), revokedAt: null }, NOW), true);
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(29), revokedAt: null }, NOW), false);
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(-5), revokedAt: daysAgo(31) }, NOW), true);
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(-5), revokedAt: daysAgo(2) }, NOW), false);
  assert.equal(r.isSessionPurgeable({ expiresAt: daysAgo(-5), revokedAt: null }, NOW), false);
});

test("isReportPurgeable: nur geschlossene, >= 2 Jahre, ohne aktiven Bann", () => {
  const banned = new Set(["bad"]);
  const old = daysAgo(731);
  assert.equal(r.isReportPurgeable({ status: "closed", resolvedAt: old, reportedUserId: "u" }, banned, NOW), true);
  assert.equal(r.isReportPurgeable({ status: "closed", resolvedAt: daysAgo(729), reportedUserId: "u" }, banned, NOW), false);
  assert.equal(r.isReportPurgeable({ status: "open", resolvedAt: old, reportedUserId: "u" }, banned, NOW), false);
  assert.equal(r.isReportPurgeable({ status: "closed", resolvedAt: null, reportedUserId: "u" }, banned, NOW), false);
  assert.equal(r.isReportPurgeable({ status: "closed", resolvedAt: old, reportedUserId: "bad" }, banned, NOW), false);
});

test("isActionPurgeable: createdAt >= 2 Jahre, nicht bei aktivem Bann", () => {
  const banned = new Set(["bad"]);
  assert.equal(r.isActionPurgeable({ targetUserId: "u", createdAt: daysAgo(800) }, banned, NOW), true);
  assert.equal(r.isActionPurgeable({ targetUserId: "u", createdAt: daysAgo(100) }, banned, NOW), false);
  assert.equal(r.isActionPurgeable({ targetUserId: "bad", createdAt: daysAgo(800) }, banned, NOW), false);
});

test("activeBanTargets: User und Tombstones mit bannedAt", () => {
  const s = r.activeBanTargets([{ id: "a", bannedAt: new Date() }, { id: "b", bannedAt: null }], [{ id: "c", bannedAt: new Date() }]);
  assert.deepEqual([...s].sort(), ["a", "c"]);
});

test("Cutoffs", () => {
  assert.equal(r.reportCutoff(NOW).getTime(), NOW.getTime() - 730 * r.DAY_MS);
  assert.equal(r.tokenCutoff(NOW).getTime(), NOW.getTime() - 7 * r.DAY_MS);
});
