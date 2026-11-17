const { test } = require("node:test");
const assert = require("node:assert/strict");
const { REPORT_REASONS, validateReport, blockState, isBlockedBetween } = require("./safety");

test("validateReport: alle Whitelist-Gruende gueltig, Details getrimmt", () => {
  for (const reason of REPORT_REASONS) {
    const r = validateReport({ reason, details: "  hi  " });
    assert.equal(r.ok, true);
    assert.deepEqual(r.value, { reason, details: "hi" });
  }
});

test("validateReport: unbekannter/fehlender Grund wird abgelehnt", () => {
  assert.equal(validateReport({ reason: "nope" }).ok, false);
  assert.equal(validateReport({}).ok, false);
  assert.equal(validateReport().ok, false);
});

test("validateReport: Details optional, leer -> null, Limit 1000", () => {
  assert.equal(validateReport({ reason: "spam" }).value.details, null);
  assert.equal(validateReport({ reason: "spam", details: "   " }).value.details, null);
  assert.equal(validateReport({ reason: "spam", details: "x".repeat(1000) }).ok, true);
  assert.equal(validateReport({ reason: "spam", details: "x".repeat(1001) }).ok, false);
  assert.equal(validateReport({ reason: "spam", details: 5 }).ok, false);
});

test("blockState / isBlockedBetween: beide Richtungen", () => {
  const blocks = [{ blockerId: "a", blockedId: "b" }];
  assert.deepEqual(blockState(blocks, "a", "b"), { blockedByMe: true,  blockedByOther: false });
  assert.deepEqual(blockState(blocks, "b", "a"), { blockedByMe: false, blockedByOther: true });
  assert.equal(isBlockedBetween(blocks, "a", "b"), true);
  assert.equal(isBlockedBetween(blocks, "b", "a"), true);
  assert.equal(isBlockedBetween(blocks, "a", "c"), false);
  assert.equal(isBlockedBetween([], "a", "b"), false);
  assert.equal(isBlockedBetween(undefined, "a", "b"), false);
});

test("validateReport: Groesse/Schreibweise, Nicht-String-Grund, null-Details, Trim vor Limit", () => {
  assert.equal(validateReport({ reason: "SPAM" }).ok, false);
  assert.equal(validateReport({ reason: "Spam" }).ok, false);
  assert.equal(validateReport({ reason: " spam" }).ok, false);
  assert.equal(validateReport({ reason: 1 }).ok, false);
  assert.equal(validateReport({ reason: null }).ok, false);
  assert.equal(validateReport({ reason: ["spam"] }).ok, false);
  assert.equal(validateReport({ reason: "spam", details: null }).value.details, null);
  assert.equal(validateReport({ reason: "spam", details: {} }).ok, false);
  assert.equal(validateReport({ reason: "spam", details: "\n\t " }).value.details, null);
  // 1000 Zeichen plus Whitespace: Limit gilt nach dem Trimmen
  assert.equal(validateReport({ reason: "spam", details: "  " + "x".repeat(1000) + "  " }).ok, true);
  assert.equal(validateReport({ reason: "spam", details: "x".repeat(1001) }).error.includes("1000"), true);
});

test("blockState / isBlockedBetween: gegenseitig, fremde Paare, ungueltige Eingaben", () => {
  const mutual = [{ blockerId: "a", blockedId: "b" }, { blockerId: "b", blockedId: "a" }];
  assert.deepEqual(blockState(mutual, "a", "b"), { blockedByMe: true, blockedByOther: true });
  assert.deepEqual(blockState(mutual, "b", "a"), { blockedByMe: true, blockedByOther: true });
  const foreign = [{ blockerId: "x", blockedId: "y" }, { blockerId: "y", blockedId: "z" }];
  assert.deepEqual(blockState(foreign, "a", "b"), { blockedByMe: false, blockedByOther: false });
  assert.equal(isBlockedBetween(foreign, "a", "b"), false);
  assert.equal(isBlockedBetween(foreign, "x", "y"), true);
  assert.equal(isBlockedBetween(foreign, "x", "z"), false);
  assert.deepEqual(blockState(null, "a", "b"), { blockedByMe: false, blockedByOther: false });
});
