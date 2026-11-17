// src/utils/twoFactor.js
// Reine, DB-freie Helper fuer 2FA per E-Mail-Code.
// Codes werden nie im Klartext gespeichert, sondern als HMAC (Secret = JWT_SECRET).

const crypto = require("crypto");

const CODE_LENGTH = 6;
const CODE_TTL_MS = 10 * 60 * 1000; // 10 Minuten gueltig
const MAX_ATTEMPTS = 5;             // danach ist der Code verbrannt

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
  generateCode,
  hashCode,
  codeMatches,
  isCodeUsable,
  maskEmail,
};
