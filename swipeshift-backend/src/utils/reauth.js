// src/utils/reauth.js
// Reine, DB-freie Logik fuer die Step-up-Re-Auth (vor dem Aendern von Auszahlungsdaten).
// Der Nachweis haengt an der UserSession (reauthAt), nicht am User.

const REAUTH_TTL_MS = 10 * 60 * 1000; // 10 Minuten gueltig
const REAUTH_METHODS = ["totp", "password", "email"];

function hasPassword(user) {
  return !!user?.passwordHash && user.passwordHash !== "SOCIAL_LOGIN";
}

// Verfuegbare Methoden in Praeferenz-Reihenfolge. E-Mail-Code nur fuer Konten ohne TOTP UND ohne Passwort
// (reine Social-Login-Konten) — sonst wuerde Mailzugriff allein die staerkeren Faktoren umgehen.
function availableMethods(user) {
  const methods = [];
  if (user?.twoFactorEnabled && user.twoFactorMethod === "totp") methods.push("totp");
  if (hasPassword(user)) methods.push("password");
  if (!methods.length) methods.push("email");
  return methods;
}

function reauthValidUntil(reauthAt) {
  if (!reauthAt) return null;
  return new Date(new Date(reauthAt).getTime() + REAUTH_TTL_MS);
}

// Frisch = innerhalb der TTL (und nicht in der Zukunft). session muss aktiv sein (nicht widerrufen/abgelaufen).
function isReauthFresh(session, now = Date.now()) {
  if (!session || !session.reauthAt) return false;
  if (session.revokedAt) return false;
  const n = new Date(now).getTime();
  if (session.expiresAt && new Date(session.expiresAt).getTime() <= n) return false;
  const at = new Date(session.reauthAt).getTime();
  return at <= n && n < at + REAUTH_TTL_MS;
}

module.exports = { REAUTH_TTL_MS, REAUTH_METHODS, hasPassword, availableMethods, reauthValidUntil, isReauthFresh };
