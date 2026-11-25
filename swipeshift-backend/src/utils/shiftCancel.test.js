// src/utils/shiftCancel.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { evaluateShiftCancel, describeBookedForCancel, countLateCancellations } = require("./shiftCancel");
const r = require("./reliability");

const now = new Date("2026-11-18T12:00:00Z");
const h = (n) => new Date(now.getTime() + n * 3_600_000);
const shift = (id, startH, lenH = 3) => ({ id, date: "Thu, Nov 19", timeRange: "x", startTimeISO: h(startH).toISOString(), endTimeISO: h(startH + lenH).toISOString() });
const job = { status: "published", startTime: h(5), endTime: h(80), shifts: [shift("s1", 5), shift("s2", 30), shift("s3", 54)] };
const apply = (shiftIds, extra = {}) => ({ status: "accepted", shiftIds, ...extra });

test("Teil-Absage > 24 h: nicht spaet, Rest bleibt", () => {
  const d = evaluateShiftCancel(apply(["s1", "s2", "s3"]), job, "s2", { now });
  assert.equal(d.ok, true);
  assert.equal(d.late, false);
  assert.equal(d.isLast, false);
  assert.deepEqual(d.remainingIds, ["s1", "s3"]);
  assert.equal(d.applyLate, false);
});

test("Spaete Teil-Absage: < 24 h vor DIESER Schicht", () => {
  const d = evaluateShiftCancel(apply(["s1", "s2"]), job, "s1", { now });
  assert.equal(d.late, true);
  assert.equal(d.isLast, false);
});

test("Letzte Schicht: Bewerbung zurueckgezogen; spaet = diese ODER fruehere spaete Teil-Absage", () => {
  const d = evaluateShiftCancel(apply(["s2"]), job, "s2", { now });
  assert.equal(d.isLast, true);
  assert.equal(d.late, false);
  assert.equal(d.applyLate, false);
  assert.equal(evaluateShiftCancel(apply(["s2"]), job, "s2", { now, priorLate: true }).applyLate, true);
  assert.equal(evaluateShiftCancel(apply(["s1"]), job, "s1", { now }).applyLate, true);
});

test("Altbestand (shiftIds leer) = alle Schichten gebucht", () => {
  const d = evaluateShiftCancel(apply([]), job, "s3", { now });
  assert.deepEqual(d.remainingIds, ["s1", "s2"]);
});

test("Fehlerfaelle", () => {
  assert.equal(evaluateShiftCancel(apply(["s1"]), job, "s2", { now }).code, "SHIFT_NOT_BOOKED");
  assert.equal(evaluateShiftCancel({ status: "pending", shiftIds: ["s1"] }, job, "s1", { now }).code, "NOT_ACCEPTED");
  assert.equal(evaluateShiftCancel(apply(["s1"]), { ...job, status: "cancelled" }, "s1", { now }).code, "JOB_CLOSED");
  const started = { ...job, shifts: [shift("s1", -1), shift("s2", 30)] };
  assert.equal(evaluateShiftCancel(apply(["s1", "s2"]), started, "s1", { now }).code, "SHIFT_STARTED");
});

test("describeBookedForCancel: canCancel + lateIfCancelledNow je Schicht", () => {
  const list = describeBookedForCancel(apply(["s1", "s2"]), job, now);
  assert.deepEqual(list.map((s) => [s.id, s.canCancel, s.lateIfCancelledNow]), [["s1", true, true], ["s2", true, false]]);
  assert.equal(describeBookedForCancel({ status: "pending", shiftIds: ["s1"] }, job, now)[0].canCancel, false);
});

test("Zaehlung: pro Schicht eine, Komplett-Storno nicht doppelt", () => {
  const since = now.getTime() - 86_400_000;
  const c = (late) => ({ late, cancelledAt: now });
  assert.equal(countLateCancellations({ status: "accepted", shiftCancellations: [c(true), c(false)] }, since), 1);
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now, shiftCancellations: [c(true), c(true)] }, since), 2);
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now, shiftCancellations: [c(true), c(false)] }, since), 1);
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now }, since), 1);
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: false, cancelledAt: now }, since), 0);
  assert.equal(countLateCancellations({ status: "accepted", shiftCancellations: [{ late: true, cancelledAt: new Date(since - 1000) }] }, since), 0);
});

test("summarizeReliability zaehlt Teil-Absagen mit", () => {
  const rows = [
    { status: "accepted", attendance: null, job: { endTime: h(50) }, shiftCancellations: [{ late: true, cancelledAt: now }] },
    { status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now, shiftCancellations: [{ late: true, cancelledAt: now }] },
  ];
  assert.equal(r.summarizeReliability(rows, now).lateCancellations, 2);
});

test("Komplett-Storno von 3 Schichten (eine < 24 h): Zeilen je Schicht → genau 1 Zaehlung; Altbestand ohne Zeilen → 1", () => {
  const since = now.getTime() - 86_400_000;
  const rows = [{ late: true, cancelledAt: now }, { late: false, cancelledAt: now }, { late: false, cancelledAt: now }];
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now, shiftCancellations: rows }, since), 1);
  assert.equal(countLateCancellations({ status: "cancelled_by_worker", lateCancellation: true, cancelledAt: now, shiftCancellations: [] }, since), 1);
  assert.equal(countLateCancellations({ status: "accepted", lateCancellation: true, cancelledAt: now }, since), 0);
});
