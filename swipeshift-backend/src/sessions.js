// src/sessions.js
// Login-Abschluss fuer alle Login-Wege (E-Mail/Passwort, Google, Apple, Register):
// legt eine UserSession an und signiert den Token — oder startet bei aktivierter 2FA
// zuerst eine Code-Challenge per E-Mail.

const { prisma } = require("./prisma.js");
const { signToken, JWT_SECRET, SESSION_TTL_MS } = require("./auth");
const { sendMail } = require("./mailer");
const { deviceInfoFromRequest } = require("./utils/deviceInfo");
const { pushTokenFromHeaders } = require("./utils/pushPayload");
const { generateCode, hashCode, maskEmail, CODE_TTL_MS, TOTP_CHALLENGE_MARKER } = require("./utils/twoFactor");

async function createSession(user, req) {
  const session = await prisma.userSession.create({
    data: {
      userId: user.id,
      ...deviceInfoFromRequest(req),
      expiresAt: new Date(Date.now() + SESSION_TTL_MS),
    },
  });
  // Sicherheitsnetz: ein Geraet, das sich jetzt anmeldet, gehoert diesem User. Sendet die App ihr aktuelles Push-Token
  // mit (X-Push-Token), verlieren andere User ein evtl. noch haengendes Token (z.B. nach Offline-Logout).
  const pushToken = pushTokenFromHeaders(req?.headers);
  if (pushToken) {
    await prisma.pushDevice.deleteMany({ where: { token: pushToken, userId: { not: user.id } } })
      .catch((err) => console.error("push token takeover cleanup failed:", err));
  }
  return signToken(user, session.id);
}

// Einheitliches User-Objekt fuer Login-Antworten (entspricht dem, was die App als UserDTO erwartet)
function authUserPayload(user, overrides = {}) {
  return {
    id: user.id,
    email: user.email,
    role: user.role,
    onboarding: user.onboarding,
    location: user.location,
    lat: user.lat,
    lng: user.lng,
    firstName: user.firstName,
    lastName: user.lastName,
    isEmailVerified: !!user.emailVerifiedAt,
    hasSocialLogin: user.passwordHash === "SOCIAL_LOGIN",
    ...overrides,
  };
}

const PURPOSE_COPY = {
  login: {
    subject: "Your SwipeShift sign-in code",
    line: "Use this code to finish signing in to SwipeShift.",
  },
  enable: {
    subject: "Turn on two-factor authentication",
    line: "Use this code to turn on two-factor authentication for your SwipeShift account.",
  },
  totp_enable: {
    subject: "Set up an authenticator app",
    line: "Use this code to confirm it's you before setting up an authenticator app for your SwipeShift account.",
  },
  reauth: {
    subject: "Confirm it's you",
    line: "Use this code to confirm it's you before changing your payout details on SwipeShift.",
  },
  disable: {
    subject: "Turn off two-factor authentication",
    line: "Use this code to turn off two-factor authentication for your SwipeShift account.",
  },
};

// Erzeugt einen neuen Code (alte offene Codes desselben Zwecks werden ungueltig) und mailt ihn.
async function issueTwoFactorCode(user, purpose) {
  const code = generateCode();

  await prisma.twoFactorCode.updateMany({
    where: { userId: user.id, purpose, consumedAt: null },
    data: { consumedAt: new Date() },
  });

  const record = await prisma.twoFactorCode.create({
    data: {
      userId: user.id,
      purpose,
      codeHash: hashCode(code, JWT_SECRET),
      expiresAt: new Date(Date.now() + CODE_TTL_MS),
    },
  });

  const copy = PURPOSE_COPY[purpose];
  const minutes = Math.round(CODE_TTL_MS / 60000);
  await sendMail({
    to: user.email,
    subject: copy.subject,
    text: `${copy.line}\n\nYour code: ${code}\n\nThe code expires in ${minutes} minutes. If you didn't request it, you can ignore this email — and consider changing your password.`,
    html: `<p>${copy.line}</p>
<p style="font-size:28px;font-weight:bold;letter-spacing:6px">${code}</p>
<p>The code expires in ${minutes} minutes. If you didn't request it, you can ignore this email — and consider changing your password.</p>`,
  });

  // Bewusst KEIN Dev-Echo des Codes in der Antwort (wuerde 2FA aushebeln, falls NODE_ENV
  // in Produktion fehlt) — lokal den Code in MailHog (http://localhost:8025) ablesen.
  return {
    challengeId: record.id,
    method: "email",
    emailHint: maskEmail(user.email),
    expiresInSeconds: Math.round(CODE_TTL_MS / 1000),
  };
}

// TOTP: kein Code, keine Mail — der Datensatz dient nur als Challenge (identifiziert den User,
// zaehlt Fehlversuche, laeuft ab). Der Marker im codeHash passt zu keinem E-Mail-Code.
async function issueTotpChallenge(user, purpose) {
  await prisma.twoFactorCode.updateMany({
    where: { userId: user.id, purpose, consumedAt: null },
    data: { consumedAt: new Date() },
  });
  const record = await prisma.twoFactorCode.create({
    data: {
      userId: user.id,
      purpose,
      codeHash: TOTP_CHALLENGE_MARKER,
      expiresAt: new Date(Date.now() + CODE_TTL_MS),
    },
  });
  return { challengeId: record.id, method: "totp", expiresInSeconds: Math.round(CODE_TTL_MS / 1000) };
}

// Gemeinsamer Abschluss aller Logins. `extra` landet zusaetzlich in der Antwort (z.B. isNewUser).
async function completeLogin(user, req, { userOverrides = {}, extra = {} } = {}) {
  if (user.twoFactorEnabled) {
    const challenge = user.twoFactorMethod === "totp"
      ? await issueTotpChallenge(user, "login")
      : await issueTwoFactorCode(user, "login");
    return { twoFactorRequired: true, ...challenge, ...extra };
  }
  const token = await createSession(user, req);
  return { token, user: authUserPayload(user, userOverrides), ...extra };
}

module.exports = { createSession, authUserPayload, issueTwoFactorCode, issueTotpChallenge, completeLogin };
