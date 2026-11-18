const { test } = require("node:test");
const assert = require("node:assert/strict");
const { sanitizeTimeZone, isWithinQuietHours, shouldDeliver } = require("./notifyPolicy");

const qh = (from, to, enabled = true) => ({ enabled, from, to });
// 2026-11-18T23:30:00Z: Berlin (CET, +1) = 00:30, New York (EST, -5) = 18:30, UTC = 23:30
const NOW = new Date("2026-11-18T23:30:00Z");

test("sanitizeTimeZone: gueltig/ungueltig", () => {
  assert.equal(sanitizeTimeZone("Europe/Berlin"), "Europe/Berlin");
  assert.equal(sanitizeTimeZone(" America/New_York "), "America/New_York");
  assert.equal(sanitizeTimeZone("Mars/Olympus"), null);
  assert.equal(sanitizeTimeZone(""), null);
  assert.equal(sanitizeTimeZone(null), null);
  assert.equal(sanitizeTimeZone("x".repeat(100)), null);
  assert.equal(sanitizeTimeZone("Europe/Berlin; drop"), null);
});

test("isWithinQuietHours: Nacht ueber Mitternacht", () => {
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "Europe/Berlin", NOW), true); // 00:30
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "America/New_York", NOW), false); // 18:30
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "UTC", NOW), true); // 23:30
});

test("isWithinQuietHours: Tagesintervall, Grenzen [from, to)", () => {
  assert.equal(isWithinQuietHours(qh("12:00", "14:00"), "UTC", new Date("2026-11-18T12:00:00Z")), true);
  assert.equal(isWithinQuietHours(qh("12:00", "14:00"), "UTC", new Date("2026-11-18T14:00:00Z")), false);
  assert.equal(isWithinQuietHours(qh("12:00", "14:00"), "UTC", new Date("2026-11-18T11:59:00Z")), false);
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "UTC", new Date("2026-11-18T07:00:00Z")), false);
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "UTC", new Date("2026-11-18T22:00:00Z")), true);
});

test("isWithinQuietHours: deaktiviert, gleiche Zeiten, unbekannte Zone → nie ruhig", () => {
  assert.equal(isWithinQuietHours(qh("22:00", "07:00", false), "UTC", NOW), false);
  assert.equal(isWithinQuietHours(qh("10:00", "10:00"), "UTC", NOW), false);
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), null, NOW), false);
  assert.equal(isWithinQuietHours(qh("22:00", "07:00"), "Nope/Zone", NOW), false);
  assert.equal(isWithinQuietHours(null, "UTC", NOW), false);
});

test("isWithinQuietHours: Sommerzeit wird beruecksichtigt", () => {
  // 2026-07-01T21:30Z: Berlin (CEST +2) = 23:30
  assert.equal(isWithinQuietHours(qh("23:00", "23:45"), "Europe/Berlin", new Date("2026-07-01T21:30:00Z")), true);
  // im Winter waere es 22:30 → nicht in 23:00–23:45
  assert.equal(isWithinQuietHours(qh("23:00", "23:45"), "Europe/Berlin", new Date("2026-12-01T21:30:00Z")), false);
});

const base = { email: "a@b.c", emailVerifiedAt: new Date(), timeZone: "UTC", pausedAt: null };

test("shouldDeliver: Defaults (jobActivity push+email, messages nur push)", () => {
  assert.equal(shouldDeliver({ ...base, settings: null }, "jobActivity", "push"), true);
  assert.equal(shouldDeliver({ ...base, settings: null }, "jobActivity", "email"), true);
  assert.equal(shouldDeliver({ ...base, settings: null }, "messages", "email"), false);
  assert.equal(shouldDeliver({ ...base, settings: null }, "account", "push"), false);
});

test("shouldDeliver: Kanal aus, unverifizierte Mail, unbekannte Kategorie/Kanal", () => {
  const s = { notifications: { jobActivity: { push: false, email: true } } };
  assert.equal(shouldDeliver({ ...base, settings: s }, "jobActivity", "push"), false);
  assert.equal(shouldDeliver({ ...base, settings: s }, "jobActivity", "email"), true);
  assert.equal(shouldDeliver({ ...base, emailVerifiedAt: null, settings: s }, "jobActivity", "email"), false);
  assert.equal(shouldDeliver({ ...base, settings: s }, "nope", "email"), false);
  assert.equal(shouldDeliver({ ...base, settings: s }, "jobActivity", "sms"), false);
  assert.equal(shouldDeliver(null, "jobActivity", "push"), false);
});

test("shouldDeliver: Ruhezeiten muten nur Push, nicht E-Mail", () => {
  const settings = { quietHours: { enabled: true, from: "22:00", to: "07:00" } };
  assert.equal(shouldDeliver({ ...base, settings }, "jobActivity", "push", NOW), false);
  assert.equal(shouldDeliver({ ...base, settings }, "jobActivity", "email", NOW), true);
  // unbekannte Zone → Ruhezeiten greifen nicht
  assert.equal(shouldDeliver({ ...base, timeZone: null, settings }, "jobActivity", "push", NOW), true);
});

test("shouldDeliver: pausiertes Konto bekommt nur pausedOk-Ereignisse", () => {
  const settings = { notifications: { account: { push: true, email: true } } };
  const paused = { ...base, pausedAt: new Date(), settings };
  const at = new Date();
  assert.equal(shouldDeliver(paused, "jobActivity", "push"), false);
  assert.equal(shouldDeliver(paused, "messages", "push"), false);
  // account ohne pausedOk (z.B. neue Bewertung) → nichts
  assert.equal(shouldDeliver(paused, "account", "email", at), false);
  assert.equal(shouldDeliver(paused, "account", "push", at), false);
  assert.equal(shouldDeliver(paused, "account", "email", at, { pausedOk: true }), true);
  assert.equal(shouldDeliver(paused, "account", "push", at, { pausedOk: true }), true);
});
