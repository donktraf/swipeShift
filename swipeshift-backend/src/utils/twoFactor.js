// src/utils/twoFactor.js
// Reine, DB-freie Helper fuer 2FA per E-Mail-Code.
// Codes werden nie im Klartext gespeichert, sondern als HMAC (Secret = JWT_SECRET).

const crypto = require("crypto");

const CODE_LENGTH = 6;
const CODE_TTL_MS = 10 * 60 * 1000; // 10 Minuten gueltig
// Marker im codeHash einer TOTP-Challenge (kein E-Mail-Code, nichts wurde verschickt)
const TOTP_CHALLENGE_MARKER = "totp-challenge";
const MAX_ATTEMPTS = 5;             // danach ist der Code verbrannt

// Sperre pro User+IP (Modell TwoFactorLock): Zaehler verfaellt LOCK_WINDOW_MS nach dem ersten Fehlversuch;
// nach USER_FAIL_LIMIT Fehlversuchen im Fenster ist das Paar USER_LOCK_MS gesperrt.
const USER_FAIL_LIMIT = 10;
const USER_LOCK_MS = 15 * 60 * 1000;
const LOCK_WINDOW_MS = 15 * 60 * 1000;
// Nutzerweite Obergrenze ueber alle IPs (Lock-Zeile mit ip = GLOBAL_LOCK_IP)
const GLOBAL_LOCK_IP = "*";
const GLOBAL_LOCK_OPTS = { limit: 50, windowMs: 60 * 60 * 1000, lockMs: 15 * 60 * 1000 };
const IP_LOCK_OPTS = { limit: USER_FAIL_LIMIT, windowMs: LOCK_WINDOW_MS, lockMs: USER_LOCK_MS };
const LOCK_MAIL_INTERVAL_MS = 60 * 60 * 1000;

function t(d) { return new Date(d).getTime(); }

function isLockActive(lock, now = Date.now()) {
  return !!lock?.lockedUntil && t(lock.lockedUntil) > t(now);
}

// Naechster Zustand nach einem Fehlversuch (rein). state = bisherige Zeile oder null.
// Rueckgabe: { failedCount, firstFailedAt, lockedUntil, justLocked }
function nextLockState(state, now = Date.now(), { limit, windowMs, lockMs } = IP_LOCK_OPTS) {
  const nowD = new Date(now);
  if (!state) return { failedCount: 1, firstFailedAt: nowD, lockedUntil: null, justLocked: false };
  if (isLockActive(state, now)) {
    return { failedCount: state.failedCount, firstFailedAt: state.firstFailedAt, lockedUntil: state.lockedUntil, justLocked: false };
  }
  if (t(now) - t(state.firstFailedAt) >= windowMs) {
    return { failedCount: 1, firstFailedAt: nowD, lockedUntil: null, justLocked: false };
  }
  const failedCount = state.failedCount + 1;
  if (failedCount >= limit) {
    return { failedCount, firstFailedAt: state.firstFailedAt, lockedUntil: new Date(t(now) + lockMs), justLocked: true };
  }
  return { failedCount, firstFailedAt: state.firstFailedAt, lockedUntil: null, justLocked: false };
}

function lockOptsFor(ip) {
  return ip === GLOBAL_LOCK_IP ? GLOBAL_LOCK_OPTS : IP_LOCK_OPTS;
}

// Abgelaufene Zeile (Fenster vorbei, nicht gesperrt) → darf aufgeraeumt werden
function isLockRowExpired(row, now = Date.now()) {
  return !isLockActive(row, now) && t(now) - t(row.firstFailedAt) >= lockOptsFor(row.ip).windowMs;
}

function minutesUntil(date, now = Date.now()) {
  return Math.max(1, Math.ceil((t(date) - t(now)) / 60000));
}

// Max. 1 Info-Mail pro Stunde (ueber alle IPs des Users): lastNotifiedAt = juengster notifiedAt oder null
function shouldSendLockMail(lastNotifiedAt, now = Date.now()) {
  return !lastNotifiedAt || t(now) - t(lastNotifiedAt) >= LOCK_MAIL_INTERVAL_MS;
}

function currentMethod(user) {
  return user?.twoFactorEnabled ? user.twoFactorMethod || "email" : null;
}

// Passt die Challenge-Art zur AKTUELLEN Methode des Users? (Schutz vor Downgrade: z.B. alte
// E-Mail-Challenge, obwohl inzwischen TOTP aktiv ist, wird abgelehnt)
function challengeMatchesUser(purpose, isTotp, user) {
  const method = currentMethod(user);
  switch (purpose) {
    case "login":
    case "disable":
      return isTotp ? method === "totp" : method === "email";
    case "enable":
      return !isTotp && method === null;
    case "totp_enable":
      return !isTotp && method !== "totp";
    default:
      return false;
  }
}

function generateCode() {
  // crypto.randomInt ist gleichverteilt; fuehrende Nullen bleiben erhalten
  return String(crypto.randomInt(0, 10 ** CODE_LENGTH)).padStart(CODE_LENGTH, "0");
}

function hashCode(code, secret) {
  return crypto.createHmac("sha256", secret).update(String(code)).digest("hex");
}

// Vergleich in konstanter Zeit
function codeMatches(code, codeHash, secret) {
  if (typeof code !== "string" || !/^\d{6}$/.test(code.trim())) return false;
  const a = Buffer.from(hashCode(code.trim(), secret), "hex");
  const b = Buffer.from(String(codeHash || ""), "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}

// Ein Code ist nutzbar, solange er nicht verbraucht, nicht abgelaufen und nicht zu oft falsch eingegeben wurde.
function isCodeUsable(record, now = new Date()) {
  if (!record) return false;
  if (record.consumedAt) return false;
  if (record.attempts >= MAX_ATTEMPTS) return false;
  return new Date(record.expiresAt).getTime() > new Date(now).getTime();
}

// "kevin@gmail.com" -> "k***n@gmail.com" (fuer "Code gesendet an ...")
function maskEmail(email) {
  const [local, domain] = String(email || "").split("@");
  if (!local || !domain) return "";
  if (local.length <= 2) return `${local[0]}***@${domain}`;
  return `${local[0]}***${local[local.length - 1]}@${domain}`;
}

module.exports = {
  CODE_LENGTH,
  CODE_TTL_MS,
  MAX_ATTEMPTS,
  TOTP_CHALLENGE_MARKER,
  USER_FAIL_LIMIT, USER_LOCK_MS, LOCK_WINDOW_MS, GLOBAL_LOCK_IP, GLOBAL_LOCK_OPTS, IP_LOCK_OPTS, LOCK_MAIL_INTERVAL_MS, isLockActive, nextLockState, lockOptsFor, isLockRowExpired, minutesUntil, shouldSendLockMail, currentMethod, challengeMatchesUser,
  generateCode,
  hashCode,
  codeMatches,
  isCodeUsable,
  maskEmail,
};
