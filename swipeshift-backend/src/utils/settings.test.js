// src/utils/settings.test.js
const { decryptAccountNumber } = require("./bankDetails");
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { withDefaults, applyPatch, publicSettings, DEFAULT_SETTINGS } = require("./settings");

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

const ctx = { userId: "u1" };
const BANK = { accountHolderName: " Jane Doe ", routingNumber: "0210-0002 1", accountNumber: "0012 3456-7890", accountType: "checking" };

test("applyPatch: Bankdaten werden geprueft, normalisiert, Kontonummer verschluesselt", () => {
  assert.match(applyPatch(null, { payout: { bank: { ...BANK, routingNumber: "123456789" } } }, ctx).error, /payout\.bank\.routingNumber/);
  assert.match(applyPatch(null, { payout: { bank: { ...BANK, accountNumber: "123" } } }, ctx).error, /accountNumber/);
  assert.match(applyPatch(null, { payout: { bank: { ...BANK, accountNumber: "12ab5678" } } }, ctx).error, /accountNumber/);
  assert.match(applyPatch(null, { payout: { bank: { ...BANK, accountType: "iban" } } }, ctx).error, /accountType/);
  assert.match(applyPatch(null, { payout: { bank: { accountHolderName: "Jane" } } }, ctx).error, /Required/); // unvollstaendig
  const r = applyPatch(null, { payout: { method: "bank", bank: BANK } }, ctx);
  const bank = r.settings.payout.bank;
  assert.equal(r.payoutDetailsChanged, true);
  assert.equal(bank.accountHolderName, "Jane Doe");
  assert.equal(bank.routingNumber, "021000021");
  assert.equal(bank.accountLast4, "7890");
  assert.equal(bank.accountType, "checking");
  assert.ok(!JSON.stringify(bank).includes("1234567890"));
  assert.equal(decryptAccountNumber(bank.accountEnc, "u1"), "00123456789" + "0");
});

test("applyPatch: Bank-Teil-Aenderung behaelt Kontonummer, null loescht, gleiche Eingabe ist keine Aenderung", () => {
  const a = applyPatch(null, { payout: { bank: BANK } }, ctx).settings;
  const b = applyPatch(a, { payout: { bank: { accountType: "savings", accountHolderName: "J. Doe" } } }, ctx);
  assert.equal(b.settings.payout.bank.accountEnc, a.payout.bank.accountEnc);
  assert.equal(b.settings.payout.bank.accountType, "savings");
  assert.equal(b.payoutDetailsChanged, true);
  assert.equal(applyPatch(a, { payout: { frequency: "monthly" } }, ctx).payoutDetailsChanged, false);
  assert.equal(applyPatch(a, { payout: { bank: { accountNumber: "00123456789 0" } } }, ctx).payoutDetailsChanged, false);
  assert.equal(applyPatch(a, { payout: { bank: { accountNumber: "99999" } } }, ctx).settings.payout.bank.accountLast4, "9999");
  assert.equal(applyPatch(a, { payout: { bank: null } }, ctx).settings.payout.bank, null);
});

test("applyPatch: PayPal-Aenderung zaehlt als geaenderte Auszahlungsdaten", () => {
  assert.equal(applyPatch(null, { payout: { paypalEmail: "A@b.de" } }, ctx).payoutDetailsChanged, true);
});

test("Alte IBAN wird ignoriert und beim Schreiben entfernt", () => {
  const stored = { payout: { method: "bank", iban: "DE89370400440532013000" } };
  assert.equal(withDefaults(stored).payout.iban, undefined);
  assert.equal(applyPatch(stored, { payout: { frequency: "monthly" } }, ctx).settings.payout.iban, undefined);
  // Feld gibt es nicht mehr: wird von der Validierung verworfen, nie gespeichert
  assert.equal(applyPatch(null, { payout: { iban: "DE89370400440532013000" } }, ctx).settings.payout.iban, undefined);
});

test("applyPatch: unbekannte Felder und falsche Zeiten abgelehnt", () => {
  assert.ok(applyPatch(null, { darkMode: true }).error);
  assert.ok(applyPatch(null, { quietHours: { from: "7 Uhr" } }).error);
  assert.ok(applyPatch(null, { payout: { paypalEmail: "kein-mail" } }).error);
});

test("publicSettings gibt die Kontonummer nie heraus, nur accountLast4", () => {
  const stored = applyPatch(null, { payout: { bank: BANK } }, ctx).settings;
  const out = publicSettings(stored);
  assert.deepEqual(out.payout.bank, { accountHolderName: "Jane Doe", routingNumber: "021000021", accountType: "checking", accountLast4: "7890" });
  assert.ok(!JSON.stringify(out).includes("accountEnc"));
  assert.equal(publicSettings(null).payout.bank, null);
});

test("Methodenwechsel zaehlt als Aenderung, Frequenz allein nicht", () => {
  const a = applyPatch(null, { payout: { method: "bank" } }, ctx);
  assert.equal(a.payoutDetailsChanged, false);
  const b = applyPatch(a.settings, { payout: { method: "paypal" } }, ctx);
  assert.equal(b.payoutDetailsChanged, true);
  assert.equal(b.payoutChanges.method, true);
  assert.equal(applyPatch(b.settings, { payout: { frequency: "monthly" } }, ctx).payoutDetailsChanged, false);
});
