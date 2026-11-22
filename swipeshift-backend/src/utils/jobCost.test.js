// src/utils/jobCost.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { shiftHoursList, shiftHours, payPerWorker, jobCosts, DEFAULT_SHIFT_HOURS } = require("./jobCost");

const job = (h, extra = {}) => ({
  payAmount: 15, openSpots: 3, platformFeePercent: null,
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

test("jobCosts: Gebuehr obendrauf, Worker-Lohn unveraendert (Default 15 %)", () => {
  const c = jobCosts(job(4), [{ isPaid: true }, { isPaid: false }]);
  assert.equal(c.feePercent, 15);
  assert.equal(c.perWorker, 60);
  assert.equal(c.perWorkerFee, 9);
  assert.equal(c.perWorkerTotal, 69);
  assert.equal(c.completed, 120);        // Lohn unveraendert
  assert.equal(c.completedFee, 18);
  assert.equal(c.completedTotal, 138);
  assert.equal(c.plannedTotal, 207);
  assert.equal(c.paidOutFee, 9);
  assert.equal(c.paidOutTotal, 69);
});

test("jobCosts: Snapshot-Satz hat Vorrang, 0 % moeglich, No-Show ohne Gebuehr", () => {
  const c = jobCosts(job(4, { platformFeePercent: 10 }), [{ isPaid: false }, { isPaid: false, attendance: "no_show" }]);
  assert.equal(c.feePercent, 10);
  assert.equal(c.completedFee, 6);
  assert.equal(c.completedTotal, 66);
  assert.equal(jobCosts(job(4, { platformFeePercent: 0 }), [{}]).completedTotal, 60);
});

const iso = (h, len) => { const st = new Date(2026, 10, 3, h); return { startTimeISO: st.toISOString(), endTimeISO: new Date(st.getTime() + len * 3_600_000).toISOString() }; };

test("Mehrere Schichten: Stunden und Lohn ueber ALLE Schichten", () => {
  const j = { payAmount: 20, openSpots: 2, platformFeePercent: 15, shifts: [iso(9, 4), iso(14, 2.5), { startTimeISO: null }],
    startTime: new Date(2026, 10, 3, 9), endTime: new Date(2026, 10, 3, 13) };
  assert.deepEqual(shiftHoursList(j), [4, 2.5]);
  assert.equal(shiftHours(j), 6.5);
  assert.equal(payPerWorker(j), 130);
  const c = jobCosts(j, [{}, {}]);
  assert.equal(c.perWorker, 130);
  assert.equal(c.perWorkerFee, 19.5);   // 12 + 7.5 → je Schicht gerundet (12 + 7.5)
  assert.equal(c.completed, 260);
  assert.equal(c.completedFee, 39);
  assert.equal(c.completedTotal, 299);
});

test("Schichten ohne gueltige shifts-JSON → startTime/endTime, sonst 8 h", () => {
  assert.deepEqual(shiftHoursList({ shifts: [], startTime: new Date(2026, 0, 1, 9), endTime: new Date(2026, 0, 1, 12) }), [3]);
  assert.deepEqual(shiftHoursList({ shifts: [] }), [8]);
});

test("jobCosts: No-Show unter Einspruch wird nicht berechnet, sondern on hold", () => {
  const now = new Date();
  const applies = [{ isPaid: false }, { attendance: "no_show", disputedAt: now }, { attendance: "no_show" }];
  const c = jobCosts(job(4, { platformFeePercent: 10 }), applies);
  assert.equal(c.completed, 60);      // nur der reguläre Worker
  assert.equal(c.completedTotal, 66);
  assert.equal(c.onHold, 60);
  assert.equal(c.onHoldFee, 6);
  assert.equal(c.onHoldTotal, 66);
  // Entschieden auf attended → berechnet, nicht mehr on hold
  const c2 = jobCosts(job(4, { platformFeePercent: 10 }), [{ attendance: "attended", disputedAt: now, disputeResolvedAt: now }]);
  assert.equal(c2.completedTotal, 66);
  assert.equal(c2.onHoldTotal, 0);
});

test("Gebuchte Schichten: Lohn/Stunden nur fuer die gebuchte Schicht", () => {
  const j = { payAmount: 20, openSpots: 1, platformFeePercent: 10, shifts: [{ id: "a", ...iso(9, 4) }, { id: "b", ...iso(9 + 24, 2) }] };
  assert.deepEqual(shiftHoursList(j, ["b"]), [2]);
  assert.equal(shiftHours(j, ["a"]), 4);
  assert.equal(payPerWorker(j, ["b"]), 40);
  assert.equal(payPerWorker(j, []), 120);  // leer = alle (Altbestand)
  assert.equal(payPerWorker(j), 120);
  const c = jobCosts(j, [{ shiftIds: ["a"] }, { shiftIds: ["b"], isPaid: true }]);
  assert.equal(c.completed, 120);          // 80 + 40
  assert.equal(c.completedFee, 12);
  assert.equal(c.paidOut, 40);
  assert.equal(c.perWorker, 120);          // Richtwert ueber alle Schichten
});

test("Geplante Kosten pro Schicht: max(Plaetze, abdeckende Worker)", () => {
  const j = { payAmount: 10, openSpots: 1, platformFeePercent: 0, shifts: [{ id: "a", ...iso(9, 2) }, { id: "b", ...iso(9 + 24, 4) }] };
  // zwei Worker auf Schicht a (> 1 Platz), keiner auf b → a: 2×20, b: 1×40
  assert.equal(jobCosts(j, [{ shiftIds: ["a"] }, { shiftIds: ["a"] }]).planned, 80);
  assert.equal(jobCosts(j, []).planned, 60);
});

test("jobCosts: Teilbuchung vs. Altbestand (leere shiftIds = alle Schichten)", () => {
  const j = { payAmount: 10, openSpots: 1, platformFeePercent: 0, shifts: [{ id: "a", ...iso(9, 2) }, { id: "b", ...iso(9 + 24, 3) }] };
  const partial = jobCosts(j, [{ shiftIds: ["b"] }]);
  const legacy  = jobCosts(j, [{ shiftIds: [] }]);
  const noField = jobCosts(j, [{}]);
  assert.equal(partial.completed, 30);
  assert.equal(legacy.completed, 50);
  assert.equal(noField.completed, 50);
  assert.equal(legacy.perWorker, 50);
});
