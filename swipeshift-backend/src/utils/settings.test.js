// src/utils/settings.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { isValidIban, withDefaults, applyPatch, publicSettings, DEFAULT_SETTINGS } = require("./settings");

test("isValidIban: echte Pruefziffer, Leerzeichen egal", () => {
  assert.equal(isValidIban("DE89 3704 0044 0532 0130 00"), true);
  assert.equal(isValidIban("de89370400440532013000"), true);
  assert.equal(isValidIban("DE89 3704 0044 0532 0130 01"), false);
  assert.equal(isValidIban("1234"), false);
});

test("withDefaults fuellt fehlende/kaputte Werte auf", () => {
  assert.deepEqual(withDefaults(null), JSON.parse(JSON.stringify(DEFAULT_SETTINGS)));
  const s = withDefaults({ notifications: { messages: { push: false, email: "x" } }, quietHours: { from: "25:00" } });
  assert.equal(s.notifications.messages.push, false);
  assert.equal(s.notifications.messages.email, false); // Default bleibt
  assert.equal(s.quietHours.from, "22:00");
});

test("applyPatch: Teil-Aenderungen werden zusammengefuehrt", () => {
  const { settings } = applyPatch(null, {
    notifications: { payments: { email: true } },
    quietHours: { enabled: true, from: "23:30" },
  });
  assert.equal(settings.notifications.payments.email, true);
  assert.equal(settings.notifications.payments.push, true);
  assert.deepEqual(settings.quietHours, { enabled: true, from: "23:30", to: "07:00" });
});

test("applyPatch: IBAN wird geprueft, normalisiert, null loescht", () => {
  assert.match(applyPatch(null, { payout: { iban: "DE00 1234" } }).error, /payout\.iban/);
  const a = applyPatch(null, { payout: { method: "bank", iban: "de89 3704 0044 0532 0130 00" } }).settings;
  assert.equal(a.payout.iban, "DE89370400440532013000");
  const b = applyPatch(a, { payout: { frequency: "monthly" } }).settings;
  assert.equal(b.payout.iban, "DE89370400440532013000"); // weggelassen = unveraendert
  assert.equal(applyPatch(b, { payout: { iban: null } }).settings.payout.iban, null);
});

test("applyPatch: unbekannte Felder und falsche Zeiten abgelehnt", () => {
  assert.ok(applyPatch(null, { darkMode: true }).error);
  assert.ok(applyPatch(null, { quietHours: { from: "7 Uhr" } }).error);
  assert.ok(applyPatch(null, { payout: { paypalEmail: "kein-mail" } }).error);
});

test("publicSettings gibt die IBAN nie komplett heraus", () => {
  const out = publicSettings({ payout: { iban: "DE89370400440532013000" } });
  assert.equal(out.payout.iban, undefined);
  assert.equal(out.payout.hasIban, true);
  assert.equal(out.payout.ibanMasked, "DE•• •••• 3000");
});
