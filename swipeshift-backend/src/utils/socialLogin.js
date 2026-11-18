// src/utils/socialLogin.js
// Reine Entscheidungslogik fuer Apple-/Google-Login und E-Mail-Normalisierung (DB-frei).
//
// Grundregel: einen BESTEHENDEN Account darf nur ein vom Anbieter verifiziertes Merkmal matchen —
// bei Apple der Subject (`sub`) oder die verifizierte Token-E-Mail, bei Google die verifizierte Token-E-Mail.
// Eine E-Mail aus dem Request-Body ist unverifiziert und dient hoechstens als Kontaktangabe fuer ein NEUES Konto.
// TODO: Plus-Adressen (a+x@gmail.com) / Gmail-Punkte werden nicht kanonisiert (Umgehung eines Banns per Alias moeglich).

function normalizeEmail(value) {
  return typeof value === "string" ? value.trim().toLowerCase() : "";
}

function isTruthyFlag(v) {
  return v === true || v === "true";
}

// tokenSub/tokenEmail/tokenEmailVerified: aus dem verifizierten Identity-Token; bodyEmail: unverifiziert (Request-Body).
// userBySub: Konto mit passender appleSub | null; userByEmail: Konto mit der gesuchten E-Mail | null (Aufrufer laedt
// userByEmail fuer die Token-E-Mail bzw. — falls keine — fuer die Body-E-Mail).
// → { action: "login", user, linkSub } | { action: "create", email, emailVerified } | { action: "reject", status, error, code }
function decideAppleLogin({ tokenSub, tokenEmail, tokenEmailVerified, bodyEmail, userBySub, userByEmail }) {
  if (!tokenSub) return { action: "reject", status: 401, error: "Invalid token", code: "INVALID_TOKEN" };
  if (userBySub) return { action: "login", user: userBySub, linkSub: false };

  const email = normalizeEmail(tokenEmail);
  if (email) {
    // Nur eine von Apple als verifiziert gemeldete Token-Adresse darf ein bestehendes Konto matchen
    if (!isTruthyFlag(tokenEmailVerified)) {
      return { action: "reject", status: 401, error: "Apple email is not verified", code: "EMAIL_NOT_VERIFIED" };
    }
    if (userByEmail) return { action: "login", user: userByEmail, linkSub: true };
    return { action: "create", email, emailVerified: true };
  }

  // Kein E-Mail im Token: Body-E-Mail nur als Kontaktangabe fuer ein neues Konto — nie zum Einloggen in ein bestehendes
  const contact = normalizeEmail(bodyEmail);
  if (!contact) return { action: "reject", status: 400, error: "Apple did not provide email", code: "NO_EMAIL" };
  if (userByEmail) {
    return {
      action: "reject", status: 409, code: "EMAIL_IN_USE",
      error: "An account with this email already exists. Please sign in with your original method.",
    };
  }
  return { action: "create", email: contact, emailVerified: false };
}

// → { action: "login", user } | { action: "create", email } | { action: "reject", status, error }
function decideGoogleLogin({ tokenEmail, emailVerified, existingUser }) {
  const email = normalizeEmail(tokenEmail);
  if (!email) return { action: "reject", status: 401, error: "Invalid Google token" };
  if (emailVerified !== true) return { action: "reject", status: 401, error: "Your Google email address is not verified." };
  if (existingUser) return { action: "login", user: existingUser };
  return { action: "create", email };
}

// Pre-Hijacking: Ein Angreifer registriert die E-Mail eines Opfers per Passwort (unverifiziert) und konfiguriert Passwort/2FA/Auszahlung.
// Verifiziert/verknuepft spaeter das Opfer das Konto per Social Login, muss alles Angreifer-Gesetzte weg.
// existingUser: das per verifizierter Token-E-Mail gefundene Konto.
function needsTakeoverCleanup(existingUser) {
  if (!existingUser) return false;
  return !existingUser.emailVerifiedAt;
}

// Settings ohne Auszahlungsdaten (vom Angreifer hinterlegt); andere Einstellungen bleiben
function stripPayout(settings) {
  if (!settings || typeof settings !== "object" || Array.isArray(settings)) return settings ?? null;
  const { payout, ...rest } = settings;
  return rest;
}

module.exports = { needsTakeoverCleanup, stripPayout, normalizeEmail, decideAppleLogin, decideGoogleLogin };
