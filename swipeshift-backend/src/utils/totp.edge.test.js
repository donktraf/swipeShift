// src/utils/totp.edge.test.js — zusaetzliche Randfaelle (DB-frei)
const { test } = require("node:test");
const assert = require("node:assert/strict");
const totp = require("./totp");
const { sanitizeCity } = require("./deviceInfo");

const SECRET = totp.base32Encode(Buffer.from("12345678901234567890"));

test("RFC-Vektoren: 6-stellig = letzte 6 Stellen der 8-stelligen Codes", () => {
  const v = [[59, "94287082"], [1111111109, "07081804"], [1111111111, "14050471"],
    [1234567890, "89005924"], [2000000000, "69279037"], [20000000000, "65353130"]];
  for (const [t, eight] of v) assert.equal(totp.totpAt(SECRET, t * 1000), eight.slice(-6), `t=${t}`);
});

test("verifyTotp: fuehrende Nullen und umgebende Leerzeichen", () => {
  const now = 1111111109 * 1000; // Code 081804 (fuehrende Null)
  assert.equal(totp.totpAt(SECRET, now), "081804");
  assert.equal(totp.verifyTotp(SECRET, "081804", { nowMs: now }).ok, true);
  assert.equal(totp.verifyTotp(SECRET, " 081804 ", { nowMs: now }).ok, true);
  assert.equal(totp.verifyTotp(SECRET, "81804", { nowMs: now }).ok, false);
  assert.equal(totp.verifyTotp(SECRET, "081 804", { nowMs: now }).ok, false);
  assert.equal(totp.verifyTotp(SECRET, "08180x", { nowMs: now }).ok, false);
  assert.equal(totp.verifyTotp(SECRET, "0818041", { nowMs: now }).ok, false);
});

test("verifyTotp: lastStep=0 ist ein gueltiger Replay-Marker", () => {
  const now = 59 * 1000; // Schritt 1
  const code = totp.totpAt(SECRET, now);
  assert.equal(totp.verifyTotp(SECRET, code, { nowMs: now, lastStep: 0 }).ok, true);
  assert.equal(totp.verifyTotp(SECRET, code, { nowMs: now, lastStep: 1 }).ok, false);
});

test("Base32: Kleinbuchstaben, Padding, Leerzeichen, ungueltige Zeichen", () => {
  const ref = totp.base32Decode("MZXW6YTBOI");
  assert.equal(ref.toString(), "foobar");
  assert.equal(totp.base32Decode("mzxw6ytboi").toString(), "foobar");
  assert.equal(totp.base32Decode("MZXW6YTBOI======").toString(), "foobar");
  assert.equal(totp.base32Decode("mzxw 6ytb oi").toString(), "foobar");
  for (const bad of ["MZXW1YTB", "MZXW0YTB", "MZXW8YTB", "MZXW9YTB", "MZXW*YTB"]) {
    assert.throws(() => totp.base32Decode(bad), bad);
  }
});

test("Verschluesselung: Tag-Manipulation schlaegt fehl", () => {
  const key = Buffer.alloc(32, 7);
  const p = totp.encryptSecret("JBSWY3DPEHPK3PXP", key).split(".");
  const tag = Buffer.from(p[2], "base64"); tag[0] ^= 1; p[2] = tag.toString("base64");
  assert.throws(() => totp.decryptSecret(p.join("."), key));
  const q = totp.encryptSecret("X", key).split(".");
  const ct = Buffer.from(q[3], "base64"); ct[0] ^= 1; q[3] = ct.toString("base64");
  assert.throws(() => totp.decryptSecret(q.join("."), key));
});

test("normalizeBackupCode: Gross/Klein, Bindestrich, Leerzeichen, ungueltig", () => {
  assert.equal(totp.normalizeBackupCode("abcde-fghjk"), "ABCDEFGHJK");
  assert.equal(totp.normalizeBackupCode("ABCDEFGHJK"), "ABCDEFGHJK");
  assert.equal(totp.normalizeBackupCode("  abcde fghjk "), "ABCDEFGHJK");
  assert.equal(totp.normalizeBackupCode("abcde-fghj"), null);
  assert.equal(totp.normalizeBackupCode("ABCDE-FGHJ1"), null); // 1 nicht im Alphabet
  assert.equal(totp.normalizeBackupCode(null), null);
});

test("sanitizeCity: Unicode, Grenzen, leer", () => {
  assert.equal(sanitizeCity("São Paulo"), "São Paulo");
  assert.equal(sanitizeCity("東京"), "東京");
  assert.equal(sanitizeCity("S%C3%A3o%20Paulo"), "São Paulo");
  assert.equal(sanitizeCity("ã".repeat(80)), "ã".repeat(80));
  assert.equal(sanitizeCity("ã".repeat(81)), null);
  assert.equal(sanitizeCity("A\tB"), null);
  assert.equal(sanitizeCity("A‮B"), null);
  assert.equal(sanitizeCity("A B"), null);
  assert.equal(sanitizeCity(""), null);
});
