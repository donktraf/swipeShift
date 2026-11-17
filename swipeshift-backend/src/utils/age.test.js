const { test } = require("node:test");
const assert = require("node:assert/strict");
const { isAtLeast18 } = require("./age");

const now = new Date("2026-11-17T12:00:00Z");

test("isAtLeast18: genau 18 Jahre alt ist erlaubt", () => {
  assert.equal(isAtLeast18("2008-11-17", now), true);
});

test("isAtLeast18: einen Tag vor dem 18. Geburtstag ist abgelehnt", () => {
  assert.equal(isAtLeast18("2008-11-18", now), false);
});

test("isAtLeast18: Erwachsene und Date-Objekte", () => {
  assert.equal(isAtLeast18("1990-05-01", now), true);
  assert.equal(isAtLeast18(new Date("2015-01-01"), now), false);
});

test("isAtLeast18: ungültiges Datum wird abgelehnt", () => {
  assert.equal(isAtLeast18("not-a-date", now), false);
});

test("isAtLeast18: volle ISO-Strings werden auf das Datum gekürzt", () => {
  assert.equal(isAtLeast18("2008-11-17T23:59:59.000Z", now), true);
  assert.equal(isAtLeast18("2008-11-18T00:00:00.000Z", now), false);
});

test("isAtLeast18: 29. Februar", () => {
  // Am 28.02.2026 ist man mit Geburtstag 29.02.2008 noch nicht 18, am 01.03.2026 ja
  assert.equal(isAtLeast18("2008-02-29", new Date("2026-02-28T12:00:00Z")), false);
  assert.equal(isAtLeast18("2008-02-29", new Date("2026-03-01T12:00:00Z")), true);
});
