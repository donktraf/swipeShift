// src/routes.security.js
// Aktive Sitzungen (Geraete) + 2FA per E-Mail-Code. Gemountet unter /auth.
//
//   GET  /auth/sessions                 eigene aktive Sitzungen
//   POST /auth/sessions/:id/revoke      einzelnes Geraet abmelden
//   POST /auth/sessions/revoke-others   alle anderen Geraete abmelden
//   POST /auth/logout                   aktuelle Sitzung beenden
//   GET  /auth/2fa                      { enabled }
//   POST /auth/2fa/request              { action: "enable"|"disable" } → Code per Mail
//   POST /auth/2fa/confirm              { challengeId, code } → 2FA an/aus
//   POST /auth/2fa/verify-login         { challengeId, code } → Token (ohne Auth)
//   POST /auth/2fa/resend               { challengeId } → neuer Login-Code (ohne Auth)

const express = require("express");
const rateLimit = require("express-rate-limit");
const { z } = require("zod");
const { prisma } = require("./prisma.js");
const { requireAuth, JWT_SECRET } = require("./auth");
const { createSession, authUserPayload, issueTwoFactorCode } = require("./sessions");
const { codeMatches, isCodeUsable } = require("./utils/twoFactor");

const router = express.Router();

const codeLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many attempts, try again later.", code: "RATE_LIMITED" },
});

const sendLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many codes requested, try again later.", code: "RATE_LIMITED" },
});

// Login-Challenges duerfen nur kurz nach dem Passwort-/Social-Schritt neu angefordert werden
const LOGIN_RESEND_WINDOW_MS = 30 * 60 * 1000;

function activeSessionWhere(userId) {
  return { userId, revokedAt: null, expiresAt: { gt: new Date() } };
}

// ───────────────────────── Sessions ─────────────────────────

router.get("/sessions", requireAuth, async (req, res) => {
  try {
    const sessions = await prisma.userSession.findMany({
      where: activeSessionWhere(req.auth.sub),
      orderBy: { lastActiveAt: "desc" },
      select: {
        id: true, deviceName: true, deviceModel: true, osVersion: true,
        createdAt: true, lastActiveAt: true,
      },
    });
    // Aktuelles Geraet immer zuerst
    const items = sessions
      .map((s) => ({ ...s, isCurrent: s.id === req.auth.sid }))
      .sort((a, b) => Number(b.isCurrent) - Number(a.isCurrent));
    return res.json({ sessions: items });
  } catch (err) {
    console.error("GET /auth/sessions error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/sessions/:id/revoke", requireAuth, async (req, res) => {
  try {
    const { count } = await prisma.userSession.updateMany({
      where: { id: req.params.id, userId: req.auth.sub, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    if (count === 0) return res.status(404).json({ error: "Session not found" });
    return res.json({ ok: true, revokedCurrent: req.params.id === req.auth.sid });
  } catch (err) {
    console.error("POST /auth/sessions/:id/revoke error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/sessions/revoke-others", requireAuth, async (req, res) => {
  try {
    const { count } = await prisma.userSession.updateMany({
      where: { userId: req.auth.sub, revokedAt: null, id: { not: req.auth.sid } },
      data: { revokedAt: new Date() },
    });
    return res.json({ ok: true, revoked: count });
  } catch (err) {
    console.error("POST /auth/sessions/revoke-others error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/logout", requireAuth, async (req, res) => {
  try {
    await prisma.userSession.updateMany({
      where: { id: req.auth.sid, revokedAt: null },
      data: { revokedAt: new Date() },
    });
    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /auth/logout error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ───────────────────────── 2FA ─────────────────────────

// Prueft einen Code gegen eine Challenge. Liefert den (verbrauchten) Datensatz oder einen Fehler-Code.
async function consumeCode(challengeId, code, { purpose, userId } = {}) {
  const record = await prisma.twoFactorCode.findUnique({ where: { id: challengeId } });
  if (!record) return { error: "CODE_INVALID" };
  if (purpose && !purpose.includes(record.purpose)) return { error: "CODE_INVALID" };
  if (userId && record.userId !== userId) return { error: "CODE_INVALID" };
  if (!isCodeUsable(record)) return { error: "CODE_EXPIRED" };

  if (!codeMatches(code, record.codeHash, JWT_SECRET)) {
    await prisma.twoFactorCode.update({
      where: { id: record.id },
      data: { attempts: { increment: 1 } },
    });
    return { error: "CODE_INVALID" };
  }

  // Race-sicher verbrauchen: nur einer gewinnt
  const { count } = await prisma.twoFactorCode.updateMany({
    where: { id: record.id, consumedAt: null },
    data: { consumedAt: new Date() },
  });
  if (count !== 1) return { error: "CODE_EXPIRED" };
  return { record };
}

const CODE_ERRORS = {
  CODE_INVALID: "That code isn't right. Check your email and try again.",
  CODE_EXPIRED: "This code has expired. Request a new one.",
};

function codeErrorResponse(res, error) {
  return res.status(400).json({ error: CODE_ERRORS[error] || "Invalid code", code: error });
}

const codeSchema = z.object({
  challengeId: z.string().min(1),
  code: z.string().min(1).max(12),
});

router.get("/2fa", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.auth.sub },
    select: { twoFactorEnabled: true },
  });
  if (!user) return res.status(404).json({ error: "User not found" });
  return res.json({ enabled: user.twoFactorEnabled });
});

router.post("/2fa/request", requireAuth, sendLimiter, async (req, res) => {
  const parsed = z.object({ action: z.enum(["enable", "disable"]) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });
  const { action } = parsed.data;

  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });

    if (action === "enable" && user.twoFactorEnabled)
      return res.status(409).json({ error: "Two-factor authentication is already on.", code: "ALREADY_ENABLED" });
    if (action === "disable" && !user.twoFactorEnabled)
      return res.status(409).json({ error: "Two-factor authentication is already off.", code: "ALREADY_DISABLED" });
    if (action === "enable" && !user.emailVerifiedAt)
      return res.status(403).json({ error: "Please verify your email address first.", code: "EMAIL_NOT_VERIFIED" });

    return res.json(await issueTwoFactorCode(user, action));
  } catch (err) {
    console.error("POST /auth/2fa/request error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

router.post("/2fa/confirm", requireAuth, codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const { record, error } = await consumeCode(parsed.data.challengeId, parsed.data.code, {
      purpose: ["enable", "disable"],
      userId: req.auth.sub,
    });
    if (error) return codeErrorResponse(res, error);

    const enabled = record.purpose === "enable";
    await prisma.user.update({ where: { id: req.auth.sub }, data: { twoFactorEnabled: enabled } });
    return res.json({ ok: true, enabled });
  } catch (err) {
    console.error("POST /auth/2fa/confirm error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/2fa/verify-login", codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const { record, error } = await consumeCode(parsed.data.challengeId, parsed.data.code, { purpose: ["login"] });
    if (error) return codeErrorResponse(res, error);

    const user = await prisma.user.findUnique({ where: { id: record.userId } });
    if (!user) return codeErrorResponse(res, "CODE_INVALID");

    const token = await createSession(user, req);
    const isSocial = user.passwordHash === "SOCIAL_LOGIN";
    return res.json({
      token,
      isNewUser: false,
      user: authUserPayload(user, isSocial ? { profilePhotoUrl: user.profilePhotoUrl ?? null } : {}),
    });
  } catch (err) {
    console.error("POST /auth/2fa/verify-login error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/2fa/resend", sendLimiter, async (req, res) => {
  const parsed = z.object({ challengeId: z.string().min(1) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const record = await prisma.twoFactorCode.findUnique({
      where: { id: parsed.data.challengeId },
      include: { user: true },
    });
    const tooOld = record && Date.now() - new Date(record.createdAt).getTime() > LOGIN_RESEND_WINDOW_MS;
    if (!record || record.purpose !== "login" || tooOld) {
      return res.status(400).json({ error: "Please sign in again.", code: "CHALLENGE_EXPIRED" });
    }
    return res.json(await issueTwoFactorCode(record.user, "login"));
  } catch (err) {
    console.error("POST /auth/2fa/resend error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

module.exports = router;
