// src/utils/bankDetails.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const b = require("./bankDetails");
const totp = require("./totp");
const box = require("./secretBox");

test("Routing Number: ABA-Pruefsumme, Format, Trennzeichen", () => {
  assert.equal(b.isValidRoutingNumber("021000021"), true);   // JPMorgan Chase
  assert.equal(b.isValidRoutingNumber("011401533"), true);
  assert.equal(b.isValidRoutingNumber("0210-0002 1"), true);
  assert.equal(b.isValidRoutingNumber("021000022"), false);  // Pruefsumme
  assert.equal(b.isValidRoutingNumber("12345678"), false);
  assert.equal(b.isValidRoutingNumber("0210000211"), false);
  assert.equal(b.isValidRoutingNumber("02100002a"), false);
});

test("Account Number: 4-17 Ziffern, Trennzeichen erlaubt", () => {
  assert.equal(b.isValidAccountNumber("1234"), true);
  assert.equal(b.isValidAccountNumber("12345678901234567"), true);
  assert.equal(b.isValidAccountNumber("123456789012345678"), false);
  assert.equal(b.isValidAccountNumber("123"), false);
  assert.equal(b.isValidAccountNumber("12-34 56"), true);
  assert.equal(b.isValidAccountNumber("12x4"), false);
});

test("Holder Name: 2-100 Zeichen", () => {
  assert.equal(b.isValidHolderName("A"), false);
  assert.equal(b.isValidHolderName(" Jo "), true);
  assert.equal(b.isValidHolderName("x".repeat(101)), false);
});

test("Kontonummer: Roundtrip, AAD an User + Kontext gebunden, TOTP-AAD nicht austauschbar", () => {
  const keyring = totp.getKeyring();
  const enc = b.encryptAccountNumber("123456789", "u1", keyring);
  assert.equal(b.decryptAccountNumber(enc, "u1", keyring), "123456789");
  assert.throws(() => b.decryptAccountNumber(enc, "u2", keyring));
  assert.throws(() => totp.decryptSecret(enc, "u1", keyring)); // anderes AAD als TOTP
  assert.ok(!enc.includes("123456789"));
});

test("Key-Rotation: mit altem Key verschluesselte Kontonummer bleibt lesbar und laesst sich neu verschluesseln", () => {
  const oldKey = "a".repeat(64), newKey = "b".repeat(64);
  const oldRing = box.getKeyring({ NODE_ENV: "test", TOTP_ENCRYPTION_KEY: oldKey });
  const ring = box.getKeyring({ NODE_ENV: "test", TOTP_ENCRYPTION_KEY: newKey, TOTP_ENCRYPTION_KEY_PREVIOUS: oldKey });
  const enc = b.encryptAccountNumber("987654321", "u1", oldRing);
  assert.equal(b.decryptAccountNumber(enc, "u1", ring), "987654321");
  const re = box.reencryptWithAad(enc, "bank:u1", ring);
  assert.equal(box.payloadKid(re), ring.current.kid);
  assert.equal(b.decryptAccountNumber(re, "u1", ring), "987654321");
});

test("sanitizeStoredBank / publicBank: kaputte Daten → null, nie accountEnc", () => {
  assert.equal(b.sanitizeStoredBank({ accountHolderName: "x" }), null);
  const ok = { accountHolderName: "Jo", routingNumber: "021000021", accountType: "savings", accountEnc: "v1.x", accountLast4: "1234" };
  assert.equal(b.publicBank(ok).accountEnc, undefined);
  assert.equal(b.publicBank(ok).accountLast4, "1234");
});

test("reencryptAccountNumber: AAD bank:<userId>, null wenn schon aktuell", () => {
  const oldKey = "c".repeat(64), newKey = "d".repeat(64);
  const oldRing = box.getKeyring({ NODE_ENV: "test", TOTP_ENCRYPTION_KEY: oldKey });
  const ring = box.getKeyring({ NODE_ENV: "test", TOTP_ENCRYPTION_KEY: newKey, TOTP_ENCRYPTION_KEY_PREVIOUS: oldKey });
  const enc = b.encryptAccountNumber("55556666", "u9", oldRing);
  const re = b.reencryptAccountNumber(enc, "u9", ring);
  assert.notEqual(re, null);
  assert.equal(b.decryptAccountNumber(re, "u9", ring), "55556666");
  assert.equal(b.reencryptAccountNumber(re, "u9", ring), null);
  assert.throws(() => b.reencryptAccountNumber(enc, "other", ring)); // falsche AAD
});

test("Routing Number 000000000 ist ungueltig", () => {
  assert.equal(b.isValidRoutingNumber("000000000"), false);
});
