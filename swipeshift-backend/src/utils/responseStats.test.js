// src/utils/responseStats.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { computeResponseStats, median, MIN_SAMPLE } = require("./responseStats");

const now = new Date("2026-11-16T12:00:00Z");
const hoursAgo = (h) => new Date(now.getTime() - h * 3600e3);
const answered = (createdH, afterH, status = "accepted") =>
  ({ status, createdAt: hoursAgo(createdH), respondedAt: hoursAgo(createdH - afterH) });

test("median", () => {
  assert.equal(median([]), null);
  assert.equal(median([5, 1, 3]), 3);
  assert.equal(median([1, 2, 3, 10]), 2.5);
});

test("Rate: frische pending-Bewerbungen zaehlen nicht gegen die Firma", () => {
  const s = computeResponseStats([
    answered(100, 2), answered(90, 4, "declined"), answered(80, 6),
    { status: "pending", createdAt: hoursAgo(10), respondedAt: null }, // < 48 h → ignoriert
  ], now);
  assert.equal(s.responseRate, 1);
  assert.equal(s.responseSampleSize, 3);
});

test("Rate: alte unbeantwortete Bewerbungen senken die Quote", () => {
  const s = computeResponseStats([
    answered(100, 2), answered(90, 4), answered(80, 6),
    { status: "pending", createdAt: hoursAgo(72), respondedAt: null },
  ], now);
  assert.equal(s.responseRate, 0.75);
});

test("Typical Response Time = Median in Stunden", () => {
  const s = computeResponseStats([answered(100, 2), answered(90, 4, "declined"), answered(80, 30)], now);
  assert.equal(s.typicalResponseHours, 4);
});

test("Altdaten ohne respondedAt zaehlen fuer die Quote, nicht fuer die Zeit", () => {
  const legacy = { status: "accepted", createdAt: hoursAgo(500), respondedAt: null };
  const s = computeResponseStats([legacy, legacy, legacy, answered(100, 1)], now);
  assert.equal(s.responseRate, 1);
  assert.equal(s.typicalResponseHours, null); // nur 1 Messwert
});

test("Unter MIN_SAMPLE → null (New on platform)", () => {
  const s = computeResponseStats([answered(100, 2), answered(90, 4)], now);
  assert.equal(MIN_SAMPLE, 3);
  assert.equal(s.responseRate, null);
  assert.equal(s.typicalResponseHours, null);
  assert.equal(computeResponseStats([], now).responseSampleSize, 0);
});

test("Unassign (zurueck auf pending) behaelt die erste Antwort", () => {
  // respondedAt bleibt gesetzt, Status wieder pending → weiterhin beantwortet
  const s = computeResponseStats([
    { status: "pending", createdAt: hoursAgo(100), respondedAt: hoursAgo(98) },
    answered(90, 4), answered(80, 6),
  ], now);
  assert.equal(s.responseRate, 1);
  assert.equal(s.typicalResponseHours, 4);
});
