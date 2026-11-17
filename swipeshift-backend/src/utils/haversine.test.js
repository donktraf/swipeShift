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

test("kmToMiles / milesToKm rechnen korrekt um und sind invers", () => {
  const { kmToMiles, milesToKm } = require("./haversine");
  assert.ok(Math.abs(kmToMiles(1.609344) - 1) < 1e-9);
  assert.ok(Math.abs(milesToKm(10) - 16.09344) < 1e-9);
  assert.ok(Math.abs(kmToMiles(milesToKm(25)) - 25) < 1e-9);
});

test("distanceMilesBetween rundet auf 0,1 Meilen und liefert null bei fehlenden Koordinaten", () => {
  const { distanceMilesBetween } = require("./haversine");
  // 1 Breitengrad ≈ 69.1 Meilen
  assert.equal(distanceMilesBetween(40, -74, 41, -74), 69.1);
  assert.equal(distanceMilesBetween(40, -74, 40, -74), 0);
  assert.equal(distanceMilesBetween(null, -74, 41, -74), null);
  assert.equal(distanceMilesBetween(40, -74, undefined, -74), null);
});
