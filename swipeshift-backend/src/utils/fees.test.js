// src/utils/fees.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const f = require("./fees");

test("Konfiguration: Defaults, Env, ungueltige Werte", () => {
  assert.equal(f.platformFeePercent({}), 15);
  assert.equal(f.instantPayoutFeePercent({}), 1.5);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "12,5" }), 12.5);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "0" }), 0);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "abc" }), 15);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "-1" }), 15);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "101" }), 15);
  assert.equal(f.platformFeePercent({ PLATFORM_FEE_PERCENT: "" }), 15);
  assert.deepEqual(f.publicFeeConfig({}), { platformFeePercent: 15, instantPayoutFeePercent: 1.5 });
});

test("feeFor / employerTotal: Cent-Rundung", () => {
  assert.equal(f.feeFor(100, 15), 15);
  assert.equal(f.feeFor(60, 15), 9);
  assert.equal(f.feeFor(10.1, 15), 1.52);     // 1.515 → 1.52
  assert.equal(f.feeFor(0, 15), 0);
  assert.equal(f.feeFor(null, 15), 0);
  assert.equal(f.employerTotal(60, 15), 69);
  assert.equal(f.employerTotal(33.33, 15), 38.33); // Fee 5.00 (4.9995 → 5.00)
  assert.equal(f.employerTotal(50, 0), 50);
});

test("feePercentForJob: Snapshot gewinnt, sonst aktueller Default", () => {
  assert.equal(f.feePercentForJob({ platformFeePercent: 10 }, {}), 10);
  assert.equal(f.feePercentForJob({ platformFeePercent: 0 }, {}), 0);
  assert.equal(f.feePercentForJob({ platformFeePercent: null }, {}), 15);
  assert.equal(f.feePercentForJob({ platformFeePercent: null }, { PLATFORM_FEE_PERCENT: "20" }), 20);
  assert.equal(f.feePercentForJob(null, {}), 15);
});

test("feePercentForJob: warnt bei undefined (fehlendes select), nicht bei null", () => {
  const orig = console.warn; const calls = [];
  console.warn = (...a) => calls.push(a);
  try {
    assert.equal(f.feePercentForJob({}, {}), 15);
    assert.equal(calls.length, 1);
    f.feePercentForJob({ platformFeePercent: null }, {});
    assert.equal(calls.length, 1);
  } finally { console.warn = orig; }
});
