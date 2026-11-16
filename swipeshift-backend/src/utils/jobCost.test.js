// src/utils/jobCost.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { shiftHours, payPerWorker, jobCosts, DEFAULT_SHIFT_HOURS } = require("./jobCost");

const job = (h, extra = {}) => ({
  payAmount: 15, openSpots: 3,
  startTime: new Date(2026, 10, 3, 9), endTime: new Date(2026, 10, 3, 9 + h), ...extra,
});

test("shiftHours: Dauer, Rundung, Fallback", () => {
  assert.equal(shiftHours(job(4)), 4);
  assert.equal(shiftHours({ startTime: new Date(2026, 0, 1, 9), endTime: new Date(2026, 0, 1, 13, 20) }), 4.3);
  assert.equal(shiftHours({ startTime: new Date(2026, 0, 1, 9) }), DEFAULT_SHIFT_HOURS);
  assert.equal(shiftHours({ startTime: new Date(2026, 0, 1, 9), endTime: new Date(2026, 0, 1, 8) }), DEFAULT_SHIFT_HOURS);
});

test("payPerWorker = Stundenlohn × Stunden", () => {
  assert.equal(payPerWorker(job(4)), 60);
  assert.equal(payPerWorker({ ...job(4), payAmount: null }), 0);
});

test("jobCosts: abgeschlossen nach angenommenen, geplant nach Plaetzen, Paid Out nach bezahlten", () => {
  const c = jobCosts(job(4), [{ isPaid: true }, { isPaid: false }]);
  assert.equal(c.completed, 120);
  assert.equal(c.planned, 180);   // 3 Plaetze
  assert.equal(c.paidOut, 60);
});

test("jobCosts: mehr angenommene als Plaetze → geplant nach angenommenen", () => {
  const c = jobCosts(job(2, { openSpots: 1 }), [{ isPaid: false }, { isPaid: false }]);
  assert.equal(c.planned, 60);
});

test("jobCosts: ohne angenommene Worker kostet ein abgeschlossener Job nichts", () => {
  const c = jobCosts(job(4), []);
  assert.equal(c.completed, 0);
  assert.equal(c.paidOut, 0);
  assert.equal(c.planned, 180);
});
