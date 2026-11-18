// src/utils/bankDetails.js
// US-Bankdaten fuer Auszahlungen: Validierung/Normalisierung (reine Logik) + Verschluesselung der
// Kontonummer (AES-256-GCM via secretBox, AAD "bank:<userId>").
// Gespeichert (User.settings.payout.bank): { accountHolderName, routingNumber, accountType, accountEnc, accountLast4 }
// Routing Number ist ein oeffentlicher Bank-Identifier → Klartext. Kontonummer nie im Klartext gespeichert/ausgegeben.

const box = require("./secretBox");

const ACCOUNT_TYPES = ["checking", "savings"];

// Leerzeichen/Bindestriche entfernen; alles andere als Ziffern → null
function normalizeDigits(value) {
  const s = String(value ?? "").replace(/[\s-]+/g, "");
  return /^\d+$/.test(s) ? s : null;
}

// ABA-Pruefsumme: 3·(d1+d4+d7) + 7·(d2+d5+d8) + (d3+d6+d9) ≡ 0 (mod 10)
function isValidRoutingNumber(value) {
  const d = normalizeDigits(value);
  if (!d || d.length !== 9 || /^0+$/.test(d)) return false;
  const n = d.split("").map(Number);
  const sum = 3 * (n[0] + n[3] + n[6]) + 7 * (n[1] + n[4] + n[7]) + (n[2] + n[5] + n[8]);
  return sum % 10 === 0;
}

function isValidAccountNumber(value) {
  const d = normalizeDigits(value);
  return !!d && d.length >= 4 && d.length <= 17;
}

function isValidHolderName(value) {
  const s = String(value ?? "").trim();
  return s.length >= 2 && s.length <= 100;
}

const aadFor = (userId) => `bank:${userId}`;

function encryptAccountNumber(accountNumber, userId, keyring) {
  return box.encryptWithAad(normalizeDigits(accountNumber), aadFor(userId), keyring);
}

function decryptAccountNumber(payload, userId, keyring) {
  return box.decryptWithAad(payload, aadFor(userId), keyring);
}

// Fuer das Rotations-Skript: accountEnc mit dem aktuellen Key neu verschluesseln; null = schon aktuell
function reencryptAccountNumber(payload, userId, keyring) {
  return box.reencryptWithAad(payload, aadFor(userId), keyring);
}

// Gespeichertes Objekt (evtl. kaputt) auf bekannte, gueltig aussehende Felder reduzieren; sonst null
function sanitizeStoredBank(b) {
  if (!b || typeof b !== "object") return null;
  if (typeof b.accountHolderName !== "string" || typeof b.routingNumber !== "string") return null;
  if (!ACCOUNT_TYPES.includes(b.accountType)) return null;
  if (typeof b.accountEnc !== "string" || !/^\d{4}$/.test(String(b.accountLast4))) return null;
  return {
    accountHolderName: b.accountHolderName,
    routingNumber: b.routingNumber,
    accountType: b.accountType,
    accountEnc: b.accountEnc,
    accountLast4: String(b.accountLast4),
  };
}

// Fuer die App: nie die Kontonummer, nur die letzten 4 Ziffern
function publicBank(b) {
  const s = sanitizeStoredBank(b);
  if (!s) return null;
  return {
    accountHolderName: s.accountHolderName,
    routingNumber: s.routingNumber,
    accountType: s.accountType,
    accountLast4: s.accountLast4,
  };
}

module.exports = {
  ACCOUNT_TYPES, normalizeDigits, isValidRoutingNumber, isValidAccountNumber, isValidHolderName,
  encryptAccountNumber, decryptAccountNumber, reencryptAccountNumber, sanitizeStoredBank, publicBank,
};
