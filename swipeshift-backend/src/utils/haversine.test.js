// src/utils/haversine.test.js
// Smoke-Tests fuer die reine, DB-freie Distanzberechnung.

const { test } = require("node:test");
const assert = require("node:assert/strict");
const { haversineDistance } = require("./haversine");

test("haversineDistance gibt 0 zurueck fuer identische Koordinaten", () => {
  const distance = haversineDistance(48.7758, 9.1829, 48.7758, 9.1829);
  assert.equal(distance, 0);
});

test("haversineDistance berechnet die ungefaehre Distanz Stuttgart -> Hamburg korrekt", () => {
  // Stuttgart (48.7758, 9.1829) -> Hamburg (53.5511, 9.9937)
  // Luftlinie liegt bei ca. 530-535 km
  const distance = haversineDistance(48.7758, 9.1829, 53.5511, 9.9937);
  assert.ok(
    distance > 520 && distance < 545,
    `Erwartete Distanz zwischen 520 und 545 km, war ${distance}`
  );
});

test("haversineDistance ist symmetrisch (A->B == B->A)", () => {
  const forward = haversineDistance(52.52, 13.405, 50.1109, 8.6821);
  const backward = haversineDistance(50.1109, 8.6821, 52.52, 13.405);
  assert.equal(forward, backward);
});
