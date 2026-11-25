// src/utils/totp.js
// TOTP nach RFC 6238 (SHA1, 6 Stellen, 30 s) mit node:crypto — reine, DB-freie Helper.
// Dazu: Secret-Verschluesselung (AES-256-GCM) und Backup-Codes (nur HMAC-Hash gespeichert).

const crypto = require("crypto");

const DIGITS = 6;
const PERIOD_S = 30;
const WINDOW = 1; // ±1 Zeitschritt Toleranz
const ISSUER = "SwipeShift";
const B32 = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";

// ───────────── Base32 (RFC 4648, ohne Padding) ─────────────

function base32Encode(buf) {
  let bits = 0, value = 0, out = "";
  for (const byte of buf) {
    value = (value << 8) | byte;
    bits += 8;
    while (bits >= 5) {
      out += B32[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }
  if (bits > 0) out += B32[(value << (5 - bits)) & 31];
  return out;
}

function base32Decode(str) {
  const clean = String(str || "").toUpperCase().replace(/[\s=-]/g, "");
  let bits = 0, value = 0;
  const out = [];
  for (const ch of clean) {
    const idx = B32.indexOf(ch);
    if (idx === -1) throw new Error("Invalid base32 character");
    value = (value << 5) | idx;
    bits += 5;
    if (bits >= 8) {
      out.push((value >>> (bits - 8)) & 255);
      bits -= 8;
    }
  }
  return Buffer.from(out);
}

function generateSecret() {
  return base32Encode(crypto.randomBytes(20)); // 160 Bit, 32 Zeichen
}

// ───────────── HOTP/TOTP ─────────────

function hotp(keyBuf, counter, digits = DIGITS, algorithm = "sha1") {
  const msg = Buffer.alloc(8);
  msg.writeBigUInt64BE(BigInt(counter));
  const hmac = crypto.createHmac(algorithm, keyBuf).update(msg).digest();
  const offset = hmac[hmac.length - 1] & 0x0f;
  const bin =
    ((hmac[offset] & 0x7f) << 24) |
    (hmac[offset + 1] << 16) |
    (hmac[offset + 2] << 8) |
    hmac[offset + 3];
  return String(bin % 10 ** digits).padStart(digits, "0");
}

function timeStep(nowMs = Date.now()) {
  return Math.floor(nowMs / 1000 / PERIOD_S);
}

function totpAt(secretBase32, nowMs = Date.now(), { digits = DIGITS, algorithm = "sha1" } = {}) {
  return hotp(base32Decode(secretBase32), timeStep(nowMs), digits, algorithm);
}

// Prueft einen Code im Fenster ±WINDOW. `lastStep` = zuletzt akzeptierter Schritt: nur
// groessere Schritte sind erlaubt (Replay-Schutz). Liefert { ok, step } — step zum Speichern.
function verifyTotp(secretBase32, code, { nowMs = Date.now(), lastStep = null, window = WINDOW } = {}) {
  if (typeof code !== "string" || !/^\d{6}$/.test(code.trim())) return { ok: false, step: null };
  const input = Buffer.from(code.trim());
  const key = base32Decode(secretBase32);
  const current = timeStep(nowMs);
  let matched = null;
  for (let step = current - window; step <= current + window; step++) {
    const expected = Buffer.from(hotp(key, step));
    // alle Schritte pruefen (konstante Zeit pro Schritt, kein frueher Abbruch)
    if (crypto.timingSafeEqual(expected, input)) matched = step;
  }
  if (matched === null) return { ok: false, step: null };
  if (lastStep !== null && lastStep !== undefined && matched <= lastStep) return { ok: false, step: matched, replay: true };
  return { ok: true, step: matched };
}

function otpauthUri(secretBase32, accountEmail) {
  const label = encodeURIComponent(`${ISSUER}:${accountEmail}`);
  const params = new URLSearchParams({
    secret: secretBase32, issuer: ISSUER, algorithm: "SHA1", digits: String(DIGITS), period: String(PERIOD_S),
  });
  return `otpauth://totp/${label}?${params.toString()}`;
}

// ───────────── Verschluesselung (AES-256-GCM, Key-ID, AAD = userId) ─────────────
// Implementierung in secretBox.js (geteilt mit den Bankdaten); Format/AAD fuer TOTP unveraendert.

const box = require("./secretBox");
const { parseKey, kidOf, getKeyring, payloadKid, needsReencrypt } = box;
const DEV_ENVS = new Set(["development", "test"]);

// Beim Start aufrufen: bricht bei fehlendem/ungueltigem Key ab.
function assertTotpConfig(env = process.env) {
  getKeyring(env);
  getBackupPepper(env);
  getEmailBanPepper(env);
  getEmailBanPepperPrev(env);
}

// Format: v1.<kid>.<iv b64>.<tag b64>.<ciphertext b64>; AAD = userId (Secret ist an den User gebunden)
function encryptSecret(plain, userId, keyring = getKeyring()) {
  return box.encryptWithAad(plain, String(userId), keyring);
}

function decryptSecret(payload, userId, keyring = getKeyring()) {
  return box.decryptWithAad(payload, String(userId), keyring);
}

// Fuer das Rotations-Skript: Payload mit dem aktuellen Key neu verschluesseln; null = schon aktuell
function reencryptPayload(payload, userId, keyring = getKeyring()) {
  return box.reencryptWithAad(payload, String(userId), keyring);
}

// Pending-Secret laeuft nach 15 Minuten ab
const PENDING_TTL_MS = 15 * 60 * 1000;
function isPendingFresh(pendingAt, now = Date.now()) {
  if (!pendingAt) return false;
  return new Date(now).getTime() - new Date(pendingAt).getTime() < PENDING_TTL_MS;
}

// ───────────── Backup-Codes ─────────────

const BACKUP_CODE_COUNT = 8;
// ohne mehrdeutige Zeichen (0/O, 1/I)
const BACKUP_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789";

function generateBackupCodes(count = BACKUP_CODE_COUNT) {
  const codes = [];
  for (let i = 0; i < count; i++) {
    let raw = "";
    for (let j = 0; j < 10; j++) raw += BACKUP_ALPHABET[crypto.randomInt(0, BACKUP_ALPHABET.length)];
    codes.push(`${raw.slice(0, 5)}-${raw.slice(5)}`);
  }
  return codes;
}

// Eingabe normalisieren: Gross, ohne Leerzeichen/Bindestrich → "ABCDEFGHJK"; sonst null
function normalizeBackupCode(input) {
  if (typeof input !== "string") return null;
  const n = input.toUpperCase().replace(/[\s-]/g, "");
  return /^[A-Z2-9]{10}$/.test(n) ? n : null;
}

// Stabiler eigener Pepper fuer Backup-Codes (BACKUP_CODE_PEPPER) — bewusst NICHT an den rotierenden
// Verschluesselungs-Key gekoppelt, damit eine Key-Rotation keine Backup-Codes entwertet.
// Pflicht ausserhalb von development/test (32 Byte: 64 hex oder base64); Dev-Fallback aus JWT_SECRET.
function getBackupPepper(env = process.env) {
  const dev = DEV_ENVS.has(env.NODE_ENV);
  const raw = env.BACKUP_CODE_PEPPER;
  if (!raw) {
    if (!dev) {
      throw new Error("BACKUP_CODE_PEPPER is required unless NODE_ENV is development or test (32 bytes, e.g. `openssl rand -hex 32`).");
    }
    return crypto.createHash("sha256").update("backup-pepper-dev:" + (env.JWT_SECRET || "dev_secret_change_me")).digest();
  }
  return parseKey(raw, { allowPassphrase: dev, name: "BACKUP_CODE_PEPPER" });
}

// Pepper fuer die E-Mail-/Apple-Hashes geloeschter Konten (DeletedAccount). NIE rotieren ohne EMAIL_BAN_PEPPER_PREV
// (sonst greifen bestehende Banns nicht mehr). Pflicht ausserhalb von development/test; Dev-Fallback aus JWT_SECRET.
function getEmailBanPepper(env = process.env) {
  const dev = DEV_ENVS.has(env.NODE_ENV);
  const raw = env.EMAIL_BAN_PEPPER;
  if (!raw) {
    if (!dev) {
      throw new Error("EMAIL_BAN_PEPPER is required unless NODE_ENV is development or test (32 bytes, e.g. `openssl rand -hex 32`).");
    }
    return crypto.createHash("sha256").update("email-ban-pepper-dev:" + (env.JWT_SECRET || "dev_secret_change_me")).digest();
  }
  return parseKey(raw, { allowPassphrase: dev, name: "EMAIL_BAN_PEPPER" });
}

// Optional: vorheriger Pepper waehrend einer Rotation (Check gegen beide); sonst null
function getEmailBanPepperPrev(env = process.env) {
  const raw = env.EMAIL_BAN_PEPPER_PREV;
  if (!raw) return null;
  return parseKey(raw, { allowPassphrase: DEV_ENVS.has(env.NODE_ENV), name: "EMAIL_BAN_PEPPER_PREV" });
}

function hashBackupCode(input, pepper) {
  const n = normalizeBackupCode(input);
  if (!n) return null;
  return crypto.createHmac("sha256", pepper).update("backup:" + n).digest("hex");
}

// Sucht den Code in einer Liste noch ungenutzter Hashes; liefert den Treffer oder null
function findBackupCodeHash(input, pepper, hashes) {
  const h = hashBackupCode(input, pepper);
  if (!h) return null;
  const a = Buffer.from(h, "hex");
  let found = null;
  for (const cand of hashes) {
    const b = Buffer.from(String(cand), "hex");
    if (a.length === b.length && crypto.timingSafeEqual(a, b)) found = cand;
  }
  return found;
}

function looksLikeTotpCode(input) {
  return typeof input === "string" && /^\d{6}$/.test(input.trim());
}

module.exports = {
  DIGITS, PERIOD_S, WINDOW, ISSUER, BACKUP_CODE_COUNT,
  base32Encode, base32Decode, generateSecret,
  hotp, timeStep, totpAt, verifyTotp, otpauthUri,
  parseKey, kidOf, getKeyring, assertTotpConfig, getEmailBanPepper, getEmailBanPepperPrev, encryptSecret, decryptSecret, payloadKid, needsReencrypt, reencryptPayload,
  PENDING_TTL_MS, isPendingFresh,
  generateBackupCodes, normalizeBackupCode, getBackupPepper, hashBackupCode, findBackupCodeHash, looksLikeTotpCode,
};
