// src/utils/totp.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("crypto");
const totp = require("./totp");
const { sanitizeCity, deviceInfoFromRequest } = require("./deviceInfo");
const tf = require("./twoFactor");

// RFC 6238 Anhang B: Secret "12345678901234567890" (ASCII), SHA1, 8 Stellen
const RFC_SECRET = totp.base32Encode(Buffer.from("12345678901234567890"));
const RFC_VECTORS = [
  [59, "94287082"], [1111111109, "07081804"], [1111111111, "14050471"],
  [1234567890, "89005924"], [2000000000, "69279037"], [20000000000, "65353130"],
];

test("RFC-6238-Testvektoren (SHA1, 8 Stellen)", () => {
  for (const [t, expected] of RFC_VECTORS) {
    assert.equal(totp.totpAt(RFC_SECRET, t * 1000, { digits: 8 }), expected, `t=${t}`);
  }
});

test("6-stellige Codes sind die letzten 6 Stellen der RFC-Vektoren", () => {
  assert.equal(totp.totpAt(RFC_SECRET, 59 * 1000), "287082");
});

test("Base32 Roundtrip + Fehler", () => {
  const buf = crypto.randomBytes(20);
  assert.deepEqual(totp.base32Decode(totp.base32Encode(buf)), buf);
  assert.equal(totp.base32Encode(Buffer.from("foobar")), "MZXW6YTBOI");
  assert.throws(() => totp.base32Decode("not*base32"));
  assert.match(totp.generateSecret(), /^[A-Z2-7]{32}$/);
});

test("verifyTotp: aktueller Schritt und ±1 Toleranz, aber nicht ±2", () => {
  const now = 1_700_000_000_000;
  const at = (offsetSteps) => totp.totpAt(RFC_SECRET, now + offsetSteps * 30_000);
  assert.equal(totp.verifyTotp(RFC_SECRET, at(0), { nowMs: now }).ok, true);
  assert.equal(totp.verifyTotp(RFC_SECRET, at(-1), { nowMs: now }).ok, true);
  assert.equal(totp.verifyTotp(RFC_SECRET, at(1), { nowMs: now }).ok, true);
  assert.equal(totp.verifyTotp(RFC_SECRET, at(-2), { nowMs: now }).ok, false);
  assert.equal(totp.verifyTotp(RFC_SECRET, at(2), { nowMs: now }).ok, false);
});

test("verifyTotp: Replay mit lastStep wird abgelehnt, naechster Schritt geht", () => {
  const now = 1_700_000_000_000;
  const code = totp.totpAt(RFC_SECRET, now);
  const first = totp.verifyTotp(RFC_SECRET, code, { nowMs: now });
  assert.equal(first.ok, true);
  const again = totp.verifyTotp(RFC_SECRET, code, { nowMs: now, lastStep: first.step });
  assert.equal(again.ok, false);
  assert.equal(again.replay, true);
  // aelterer Schritt (Toleranzfenster) nach neuerem ist ebenfalls Replay
  const older = totp.totpAt(RFC_SECRET, now - 30_000);
  assert.equal(totp.verifyTotp(RFC_SECRET, older, { nowMs: now, lastStep: first.step }).ok, false);
  const next = totp.totpAt(RFC_SECRET, now + 30_000);
  assert.equal(totp.verifyTotp(RFC_SECRET, next, { nowMs: now + 30_000, lastStep: first.step }).ok, true);
});

test("verifyTotp: kaputte Eingaben", () => {
  for (const bad of ["", "12345", "1234567", "abcdef", null, undefined, 123456]) {
    assert.equal(totp.verifyTotp(RFC_SECRET, bad).ok, false);
  }
});

test("otpauth-URI mit Issuer, E-Mail und Secret", () => {
  const uri = totp.otpauthUri("ABCDEFGH", "kevin+x@example.com");
  assert.ok(uri.startsWith("otpauth://totp/SwipeShift%3Akevin%2Bx%40example.com?"));
  const q = new URL(uri).searchParams;
  assert.equal(q.get("secret"), "ABCDEFGH");
  assert.equal(q.get("issuer"), "SwipeShift");
  assert.equal(q.get("digits"), "6");
  assert.equal(q.get("period"), "30");
});

const ring = (cur, prev = null) => ({ current: { kid: totp.kidOf(cur), key: cur }, previous: prev ? { kid: totp.kidOf(prev), key: prev } : null });

test("Verschluesselung: Roundtrip, zufaellige IV, Key-ID im Format, Manipulation/falscher Key schlagen fehl", () => {
  const key = crypto.randomBytes(32);
  const r = ring(key);
  const enc = totp.encryptSecret("JBSWY3DPEHPK3PXP", "user-1", r);
  assert.ok(!enc.includes("JBSWY3DPEHPK3PXP"));
  assert.ok(enc.startsWith(`v1.${totp.kidOf(key)}.`));
  assert.equal(totp.payloadKid(enc), totp.kidOf(key));
  assert.equal(totp.decryptSecret(enc, "user-1", r), "JBSWY3DPEHPK3PXP");
  assert.notEqual(enc, totp.encryptSecret("JBSWY3DPEHPK3PXP", "user-1", r));
  const parts = enc.split(".");
  parts[4] = Buffer.from("tampered!").toString("base64");
  assert.throws(() => totp.decryptSecret(parts.join("."), "user-1", r));
  assert.throws(() => totp.decryptSecret(enc, "user-1", ring(crypto.randomBytes(32))));
  assert.throws(() => totp.decryptSecret("garbage", "user-1", r));
});

test("Verschluesselung: AAD bindet das Secret an die userId", () => {
  const r = ring(crypto.randomBytes(32));
  const enc = totp.encryptSecret("SECRET", "user-1", r);
  assert.throws(() => totp.decryptSecret(enc, "user-2", r));
});

test("Key-Rotation: PREVIOUS entschluesselt alte Payloads, needsReencrypt erkennt sie", () => {
  const oldKey = crypto.randomBytes(32), newKey = crypto.randomBytes(32);
  const enc = totp.encryptSecret("SECRET", "u", ring(oldKey));
  const rotated = ring(newKey, oldKey);
  assert.equal(totp.decryptSecret(enc, "u", rotated), "SECRET");
  assert.equal(totp.needsReencrypt(enc, rotated), true);
  const re = totp.encryptSecret("SECRET", "u", rotated);
  assert.equal(totp.needsReencrypt(re, rotated), false);
  // ohne PREVIOUS: unbekannte Key-ID
  assert.throws(() => totp.decryptSecret(enc, "u", ring(newKey)), /Unknown key id/);
});

test("Key-Parsing: Hex/Base64 immer, Passphrase nur in development/test", () => {
  const hex = "ab".repeat(32);
  assert.deepEqual(totp.parseKey(hex), Buffer.from(hex, "hex"));
  const b64 = crypto.randomBytes(32).toString("base64");
  assert.deepEqual(totp.parseKey(b64), Buffer.from(b64, "base64"));
  assert.throws(() => totp.parseKey("any passphrase"), /32 bytes/);
  assert.throws(() => totp.parseKey("ab".repeat(16)), /32 bytes/);
  assert.equal(totp.parseKey("any passphrase", { allowPassphrase: true }).length, 32);

  assert.equal(totp.getKeyring({ NODE_ENV: "production", TOTP_ENCRYPTION_KEY: hex }).current.kid, totp.kidOf(Buffer.from(hex, "hex")));
  assert.throws(() => totp.getKeyring({ NODE_ENV: "production", TOTP_ENCRYPTION_KEY: "passphrase" }), /32 bytes/);
  assert.throws(() => totp.getKeyring({ NODE_ENV: "staging", TOTP_ENCRYPTION_KEY: "passphrase" }), /32 bytes/);
  assert.equal(totp.getKeyring({ NODE_ENV: "development", TOTP_ENCRYPTION_KEY: "passphrase" }).current.key.length, 32);
  const withPrev = totp.getKeyring({ NODE_ENV: "production", TOTP_ENCRYPTION_KEY: hex, TOTP_ENCRYPTION_KEY_PREVIOUS: "cd".repeat(32) });
  assert.ok(withPrev.previous && withPrev.previous.kid !== withPrev.current.kid);
});

test("Key fehlt: nur development/test haben Fallback, sonst Fehler (auch bei NODE_ENV unset)", () => {
  for (const env of [{ NODE_ENV: "production" }, { NODE_ENV: "staging" }, {}]) {
    assert.throws(() => totp.assertTotpConfig(env), /TOTP_ENCRYPTION_KEY/);
  }
  const origWarn = console.warn; console.warn = () => {};
  try {
    for (const NODE_ENV of ["development", "test"]) assert.equal(totp.getKeyring({ NODE_ENV }).current.key.length, 32);
  } finally { console.warn = origWarn; }
});

test("Pending-Secret laeuft nach 15 Minuten ab", () => {
  const now = Date.now();
  assert.equal(totp.isPendingFresh(new Date(now - 14 * 60000), now), true);
  assert.equal(totp.isPendingFresh(new Date(now - 16 * 60000), now), false);
  assert.equal(totp.isPendingFresh(null, now), false);
});

test("Backup-Pepper: eigener Key (nicht an Verschluesselungs-Key gekoppelt), Pflicht ausserhalb Dev", () => {
  const hex = "11".repeat(32);
  const enc = "22".repeat(32);
  const env = { NODE_ENV: "production", BACKUP_CODE_PEPPER: hex, TOTP_ENCRYPTION_KEY: enc };
  assert.deepEqual(totp.getBackupPepper(env), Buffer.from(hex, "hex"));
  // Rotation des Verschluesselungs-Keys aendert den Pepper nicht
  assert.deepEqual(
    totp.getBackupPepper({ ...env, TOTP_ENCRYPTION_KEY: "33".repeat(32), TOTP_ENCRYPTION_KEY_PREVIOUS: enc }),
    totp.getBackupPepper(env)
  );
  assert.throws(() => totp.getBackupPepper({ NODE_ENV: "production" }), /BACKUP_CODE_PEPPER/);
  assert.throws(() => totp.getBackupPepper({}), /BACKUP_CODE_PEPPER/);
  assert.throws(() => totp.getBackupPepper({ NODE_ENV: "production", BACKUP_CODE_PEPPER: "short" }), /32 bytes/);
  // Dev: Fallback (abgeleitet) + Passphrase erlaubt
  assert.equal(totp.getBackupPepper({ NODE_ENV: "development" }).length, 32);
  assert.deepEqual(totp.getBackupPepper({ NODE_ENV: "test", JWT_SECRET: "a" }), totp.getBackupPepper({ NODE_ENV: "test", JWT_SECRET: "a" }));
  assert.notDeepEqual(totp.getBackupPepper({ NODE_ENV: "test", JWT_SECRET: "a" }), totp.getBackupPepper({ NODE_ENV: "test", JWT_SECRET: "b" }));
  // assertTotpConfig verlangt beide
  assert.throws(() => totp.assertTotpConfig({ NODE_ENV: "production", TOTP_ENCRYPTION_KEY: enc }), /BACKUP_CODE_PEPPER/);
  assert.doesNotThrow(() => totp.assertTotpConfig(env));
});

test("Backup-Codes: Format, Eindeutigkeit, Hash, Normalisierung, Verbrauch", () => {
  const codes = totp.generateBackupCodes();
  assert.equal(codes.length, 8);
  assert.equal(new Set(codes).size, 8);
  for (const c of codes) assert.match(c, /^[A-HJ-NP-Z2-9]{5}-[A-HJ-NP-Z2-9]{5}$/);

  const P = crypto.randomBytes(32);
  const hashes = codes.map((c) => totp.hashBackupCode(c, P));
  assert.ok(hashes.every((h) => /^[0-9a-f]{64}$/.test(h)));
  assert.ok(!hashes.includes(codes[0]));

  const typed = codes[2].toLowerCase().replace("-", " ");
  assert.equal(totp.findBackupCodeHash(typed, P, hashes), hashes[2]);
  assert.equal(totp.findBackupCodeHash(codes[2], crypto.randomBytes(32), hashes), null);
  assert.equal(totp.findBackupCodeHash("AAAAA-AAAAA", P, hashes), null);
  assert.equal(totp.findBackupCodeHash("123456", P, hashes), null);

  let unused = [...hashes];
  const hit = totp.findBackupCodeHash(codes[0], P, unused);
  assert.equal(hit, hashes[0]);
  unused = unused.filter((h) => h !== hit);
  assert.equal(totp.findBackupCodeHash(codes[0], P, unused), null);
  assert.equal(totp.findBackupCodeHash(codes[1], P, unused), hashes[1]);
});

test("reencryptPayload: alter Key -> aktueller Key, aktuelle Payloads bleiben (null), AAD bleibt userId", () => {
  const oldKey = crypto.randomBytes(32), newKey = crypto.randomBytes(32);
  const old = totp.encryptSecret("SECRET", "u1", ring(oldKey));
  const rotated = ring(newKey, oldKey);
  const next = totp.reencryptPayload(old, "u1", rotated);
  assert.equal(totp.payloadKid(next), totp.kidOf(newKey));
  assert.equal(totp.decryptSecret(next, "u1", ring(newKey)), "SECRET"); // PREVIOUS wird nicht mehr gebraucht
  assert.equal(totp.reencryptPayload(next, "u1", rotated), null);
  assert.throws(() => totp.reencryptPayload(old, "other-user", rotated)); // falsche userId
  assert.throws(() => totp.reencryptPayload(old, "u1", ring(newKey))); // PREVIOUS fehlt
});

test("looksLikeTotpCode trennt TOTP- von Backup-Code", () => {
  assert.equal(totp.looksLikeTotpCode("123456"), true);
  assert.equal(totp.looksLikeTotpCode(" 123456 "), true);
  assert.equal(totp.looksLikeTotpCode("ABCDE-FGHJK"), false);
});

test("sanitizeCity: gueltige Orte, Laenge, Steuerzeichen, Prozent-Kodierung", () => {
  assert.equal(sanitizeCity("Austin, TX"), "Austin, TX");
  assert.equal(sanitizeCity("  Austin, TX  "), "Austin, TX");
  assert.equal(sanitizeCity("M%C3%BCnchen, BY"), "München, BY");
  assert.equal(sanitizeCity("a".repeat(80)), "a".repeat(80));
  assert.equal(sanitizeCity("a".repeat(81)), null);
  assert.equal(sanitizeCity("Austin\nTX"), null);
  assert.equal(sanitizeCity("Aus\u0000tin"), null);
  assert.equal(sanitizeCity("Austin%00"), null);
  assert.equal(sanitizeCity("Austin TX"), null);
  assert.equal(sanitizeCity("%E0%A4%A"), null);
  for (const bad of ["", "   ", null, undefined, 42, ["Austin"]]) assert.equal(sanitizeCity(bad), null);
});

test("deviceInfoFromRequest: IP nur aus req.ip, X-Forwarded-For wird ignoriert", () => {
  const info = deviceInfoFromRequest({ headers: { "x-forwarded-for": "6.6.6.6" }, ip: "10.1.1.1" });
  assert.equal(info.ipAddress, "10.1.1.1");
});

test("deviceInfoFromRequest liefert city aus X-Device-City", () => {
  const withCity = deviceInfoFromRequest({ headers: { "x-device-city": "Austin, TX" } });
  assert.equal(withCity.city, "Austin, TX");
  assert.equal(deviceInfoFromRequest({ headers: {} }).city, null);
});

test("Lock-Entscheidung (User+IP): Fenster, Limit, Sperre, Verfall", () => {
  const T0 = Date.UTC(2026, 0, 1, 12, 0, 0);
  const min = (m) => m * 60000;
  let st = null;
  // Fehlversuch 1..9: kein Lock
  for (let i = 1; i < tf.USER_FAIL_LIMIT; i++) {
    st = tf.nextLockState(st, T0 + min(i * 0.5));
    assert.equal(st.failedCount, i);
    assert.equal(st.lockedUntil, null);
    assert.equal(st.justLocked, false);
  }
  // 10. Fehlversuch im Fenster: Sperre fuer 15 min, genau einmal justLocked
  const tLock = T0 + min(5);
  const locked = tf.nextLockState(st, tLock);
  assert.equal(locked.justLocked, true);
  assert.equal(new Date(locked.lockedUntil).getTime(), tLock + min(15));
  assert.equal(tf.isLockActive(locked, tLock + 1), true);
  assert.equal(tf.isLockActive(locked, tLock + min(15) + 1), false);
  // Weitere Versuche waehrend der Sperre aendern nichts
  const again = tf.nextLockState(locked, tLock + min(1));
  assert.equal(again.justLocked, false);
  assert.equal(again.failedCount, locked.failedCount);
  assert.deepEqual(new Date(again.lockedUntil), new Date(locked.lockedUntil));
  // Nach Ablauf der Sperre beginnt ein neues Fenster
  const fresh = tf.nextLockState(locked, tLock + min(16));
  assert.equal(fresh.failedCount, 1);
  assert.equal(fresh.lockedUntil, null);
});

test("Lock-Fenster: Zaehler verfaellt 15 min nach dem ersten Fehlversuch", () => {
  const T0 = Date.UTC(2026, 0, 1, 12, 0, 0);
  let st = tf.nextLockState(null, T0);
  for (let i = 0; i < 5; i++) st = tf.nextLockState(st, T0 + 60000);
  assert.equal(st.failedCount, 6);
  const later = tf.nextLockState(st, T0 + 15 * 60000); // Fenster abgelaufen
  assert.equal(later.failedCount, 1);
  assert.equal(new Date(later.firstFailedAt).getTime(), T0 + 15 * 60000);
  // 14:59 → noch im Fenster
  assert.equal(tf.nextLockState(st, T0 + 15 * 60000 - 1000).failedCount, 7);
  assert.equal(tf.isLockActive(null), false);
  assert.equal(tf.minutesUntil(new Date(T0 + 14 * 60000 + 1), T0), 15);
});

test("Lock-Mail: max. 1 pro Stunde", () => {
  const now = Date.now();
  assert.equal(tf.shouldSendLockMail(null, now), true);
  assert.equal(tf.shouldSendLockMail(new Date(now - 30 * 60000), now), false);
  assert.equal(tf.shouldSendLockMail(new Date(now - 61 * 60000), now), true);
});

test("challengeMatchesUser: Challenge-Art muss zur aktuellen Methode passen (kein Downgrade)", () => {
  const none = { twoFactorEnabled: false, twoFactorMethod: null };
  const email = { twoFactorEnabled: true, twoFactorMethod: "email" };
  const legacy = { twoFactorEnabled: true, twoFactorMethod: null };
  const totpU = { twoFactorEnabled: true, twoFactorMethod: "totp" };
  // Login
  assert.equal(tf.challengeMatchesUser("login", false, email), true);
  assert.equal(tf.challengeMatchesUser("login", false, legacy), true);
  assert.equal(tf.challengeMatchesUser("login", false, totpU), false); // alter Mail-Code nach Wechsel auf TOTP
  assert.equal(tf.challengeMatchesUser("login", true, totpU), true);
  assert.equal(tf.challengeMatchesUser("login", true, email), false);
  assert.equal(tf.challengeMatchesUser("login", false, none), false);
  // Disable
  assert.equal(tf.challengeMatchesUser("disable", false, totpU), false);
  assert.equal(tf.challengeMatchesUser("disable", true, totpU), true);
  assert.equal(tf.challengeMatchesUser("disable", false, email), true);
  // Enable
  assert.equal(tf.challengeMatchesUser("enable", false, none), true);
  assert.equal(tf.challengeMatchesUser("enable", false, email), false);
  // TOTP-Einrichtung per Mail-Code: auch aus E-Mail-2FA heraus, nicht wenn TOTP schon aktiv
  assert.equal(tf.challengeMatchesUser("totp_enable", false, none), true);
  assert.equal(tf.challengeMatchesUser("totp_enable", false, email), true);
  assert.equal(tf.challengeMatchesUser("totp_enable", false, totpU), false);
  assert.equal(tf.challengeMatchesUser("totp_enable", true, none), false);
  assert.equal(tf.challengeMatchesUser("unknown", false, email), false);
});

test("TRUST_PROXY: Hops oder konkrete IPs/CIDRs, true verboten, Muell → Fehler", () => {
  const { parseTrustProxy } = require("./trustProxy");
  assert.equal(parseTrustProxy(undefined), undefined);
  assert.equal(parseTrustProxy(""), undefined);
  assert.equal(parseTrustProxy("false"), undefined);
  assert.equal(parseTrustProxy("1"), 1);
  assert.equal(parseTrustProxy(" 2 "), 2);
  assert.deepEqual(parseTrustProxy("10.0.0.0/8, 172.16.0.5"), ["10.0.0.0/8", "172.16.0.5"]);
  assert.deepEqual(parseTrustProxy("loopback,::1"), ["loopback", "::1"]);
  assert.deepEqual(parseTrustProxy("fd00::/8"), ["fd00::/8"]);
  assert.throws(() => parseTrustProxy("true"), /not allowed/);
  assert.throws(() => parseTrustProxy("TRUE"), /not allowed/);
  assert.throws(() => parseTrustProxy("0"), /between/);
  assert.throws(() => parseTrustProxy("99"), /between/);
  assert.throws(() => parseTrustProxy("10.0.0.0/33"), /invalid/);
  assert.throws(() => parseTrustProxy("not-an-ip"), /invalid/);
  assert.throws(() => parseTrustProxy("1.2.3.4/8/9"), /invalid/);
});

test("normalizeIp: IPv4 unveraendert, IPv6 → /64, IPv4-mapped → IPv4, Muell → unknown", () => {
  const { normalizeIp } = require("./clientIp");
  assert.equal(normalizeIp("203.0.113.5"), "203.0.113.5");
  assert.equal(normalizeIp("::ffff:203.0.113.5"), "203.0.113.5");
  assert.equal(normalizeIp("::FFFF:cb00:7105"), "203.0.113.5"); // Hex-Schreibweise
  assert.equal(normalizeIp("2001:db8:1:2:3:4:5:6"), "2001:db8:1:2::/64");
  // gleiches /64 → gleicher Schluessel, auch bei unterschiedlicher Schreibweise
  assert.equal(normalizeIp("2001:0db8:0001:0002::ffff"), "2001:db8:1:2::/64");
  assert.equal(normalizeIp("2001:db8:1:2:aaaa:bbbb:cccc:dddd"), normalizeIp("2001:DB8:1:2::1"));
  assert.notEqual(normalizeIp("2001:db8:1:3::1"), normalizeIp("2001:db8:1:2::1"));
  // ::-Expansion
  assert.equal(normalizeIp("::1"), "0:0:0:0::/64");
  assert.equal(normalizeIp("2001:db8::"), "2001:db8:0:0::/64");
  assert.equal(normalizeIp("fe80::1%en0"), "fe80:0:0:0::/64");
  assert.equal(normalizeIp("64:ff9b::1.2.3.4"), "64:ff9b:0:0::/64");
  for (const bad of ["", "  ", "garbage", "1.2.3", "2001:db8::1::2", null, undefined, 42]) assert.equal(normalizeIp(bad), "unknown");
});

test("Nutzerweite Obergrenze: 50 Fehlversuche/h ueber alle IPs → 15 min Sperre, anderes Fenster als pro IP", () => {
  const T0 = Date.UTC(2026, 0, 1, 12, 0, 0);
  const G = tf.GLOBAL_LOCK_OPTS;
  assert.equal(tf.GLOBAL_LOCK_IP, "*");
  assert.equal(G.limit, 50);
  let st = null;
  for (let i = 1; i < 50; i++) {
    st = tf.nextLockState(st, T0 + i * 60000 * 0.9, G); // ~44 min verteilt
    assert.equal(st.lockedUntil, null, `i=${i}`);
  }
  const tLock = T0 + 49 * 60000 * 0.9 + 1000;
  const locked = tf.nextLockState(st, tLock, G);
  assert.equal(locked.justLocked, true);
  assert.equal(new Date(locked.lockedUntil).getTime(), tLock + 15 * 60000);
  // Fenster (60 min) ab erstem Fehlversuch → Zaehler verfaellt
  const later = tf.nextLockState({ ...st, failedCount: 30 }, T0 + 61 * 60000, G);
  assert.equal(later.failedCount, 1);
  // pro-IP-Fenster (15 min) waere schon abgelaufen — das globale nicht
  assert.equal(tf.nextLockState({ failedCount: 30, firstFailedAt: new Date(T0), lockedUntil: null }, T0 + 20 * 60000, G).failedCount, 31);
  assert.equal(tf.nextLockState({ failedCount: 9, firstFailedAt: new Date(T0), lockedUntil: null }, T0 + 20 * 60000).failedCount, 1);
});

test("Lock-Cleanup: abgelaufene Zeilen erkennen (je Fenster), aktive/laufende nicht", () => {
  const now = Date.UTC(2026, 0, 1, 12, 0, 0);
  const min = (m) => new Date(now - m * 60000);
  assert.equal(tf.lockOptsFor("*"), tf.GLOBAL_LOCK_OPTS);
  assert.equal(tf.lockOptsFor("1.2.3.4"), tf.IP_LOCK_OPTS);
  assert.equal(tf.isLockRowExpired({ ip: "1.2.3.4", firstFailedAt: min(16), lockedUntil: null }, now), true);
  assert.equal(tf.isLockRowExpired({ ip: "1.2.3.4", firstFailedAt: min(10), lockedUntil: null }, now), false);
  assert.equal(tf.isLockRowExpired({ ip: "1.2.3.4", firstFailedAt: min(20), lockedUntil: new Date(now + 1000) }, now), false); // gesperrt
  assert.equal(tf.isLockRowExpired({ ip: "1.2.3.4", firstFailedAt: min(20), lockedUntil: min(1) }, now), true);
  assert.equal(tf.isLockRowExpired({ ip: "*", firstFailedAt: min(30), lockedUntil: null }, now), false);
  assert.equal(tf.isLockRowExpired({ ip: "*", firstFailedAt: min(61), lockedUntil: null }, now), true);
});
