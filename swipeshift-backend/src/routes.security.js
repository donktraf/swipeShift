// src/routes.security.js
// Aktive Sitzungen (Geraete) + 2FA per E-Mail-Code. Gemountet unter /auth.
//
//   GET  /auth/sessions                 eigene aktive Sitzungen
//   POST /auth/sessions/:id/revoke      einzelnes Geraet abmelden
//   POST /auth/sessions/revoke-others   alle anderen Geraete abmelden
//   POST /auth/logout                   aktuelle Sitzung beenden
//   GET  /auth/2fa                      { enabled }
//   POST /auth/2fa/request              { action: "enable"|"disable", method?: "email"|"totp" } → Code per Mail
//                                       (enable+totp: Mail-Code als Re-Auth vor der Einrichtung; auch bei
//                                       aktiver E-Mail-2FA erlaubt = Wechsel email→totp; bei aktivem TOTP 409; TOTP→email: /2fa/switch-to-email/*)
//   POST /auth/2fa/confirm              { challengeId, code } → 2FA an/aus
//   POST /auth/2fa/verify-login         { challengeId, code } → Token (ohne Auth)
//   POST /auth/2fa/resend               { challengeId } → neuer Login-Code (ohne Auth; 400 bei TOTP)
//   POST /auth/2fa/totp/setup           { challengeId, code } (Mail-Code, purpose totp_enable) → { secret, otpauthUri }
//   POST /auth/2fa/totp/backup-codes    { code } (aktueller TOTP-Code) → neue Backup-Codes
//   POST /auth/2fa/totp/confirm         { code } → TOTP aktiv + 8 Backup-Codes (einmalig); bei aktiver E-Mail-2FA
//                                       atomarer Wechsel email→totp (2FA bleibt durchgehend an)
//   POST /auth/2fa/switch-to-email/start   { code } (TOTP-/Backup-Code) → Mail-Code (purpose switch_email, an Sitzung gebunden)
//   POST /auth/2fa/switch-to-email/confirm { challengeId, code } → Methode email, TOTP-Daten + Backup-Codes geloescht
//   Bei Methode totp akzeptieren confirm(disable) und verify-login TOTP-Code ODER Backup-Code.

const express = require("express");
const rateLimit = require("express-rate-limit");
const { z } = require("zod");
const { prisma } = require("./prisma.js");
const { removeDevicesForSessions } = require("./pushDevices");
const { requireAuth, JWT_SECRET } = require("./auth");
const { respondIfRestricted, createSession, authUserPayload, issueTwoFactorCode, issueTotpChallenge } = require("./sessions");
const { sendMail } = require("./mailer");
const {
  codeMatches, isCodeUsable, TOTP_CHALLENGE_MARKER, MAX_ATTEMPTS,
  isLockActive, nextLockState, lockOptsFor, minutesUntil, shouldSendLockMail, LOCK_MAIL_INTERVAL_MS,
  GLOBAL_LOCK_IP, IP_LOCK_OPTS, GLOBAL_LOCK_OPTS,
  currentMethod, challengeMatchesUser, maskEmail,
  canSwitchMethod, switchBindingValid, methodChangedMail,
} = require("./utils/twoFactor");
const totp = require("./utils/totp");
const { normalizeIp } = require("./utils/clientIp");
const bcrypt = require("bcrypt");
const { availableMethods, reauthValidUntil } = require("./utils/reauth");

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
        id: true, city: true, deviceName: true, deviceModel: true, osVersion: true,
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
    await removeDevicesForSessions({ sessionId: req.params.id, userId: req.auth.sub });
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
    await removeDevicesForSessions({ userId: req.auth.sub, sessionId: { not: req.auth.sid } });
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
    await removeDevicesForSessions({ sessionId: req.auth.sid, userId: req.auth.sub });
    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /auth/logout error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ───────────────────────── 2FA ─────────────────────────

// Fehlversuche pro User+IP (Tabelle TwoFactorLock) PLUS nutzerweite Obergrenze ueber alle IPs
// (Zeile mit ip = "*"). Zaehlen und Sperren werden per Compare-and-Set auf der Zeile entschieden
// (nextLockState ist rein). Bewusst CAS statt Raw-SQL-Upsert: die Logik bleibt in getestetem JS.
// Faellt der CAS dauerhaft durch (Dauerkonflikt), wird fail-closed abgelehnt (429).
function ipOf(req) {
  return normalizeIp(req?.ip || req?.socket?.remoteAddress);
}

// Aktive Sperre fuer dieses User+IP-Paar ODER nutzerweit; liefert die laengste oder null
// scope "" = 2FA-Login/-Aenderungen, REAUTH_SCOPE = eigene Zaehler/Sperren fuer die Re-Auth (Zeilen "reauth:<ip>" / "reauth:*")
const REAUTH_SCOPE = "reauth:";
async function getActiveLock(userId, ip, scope = "") {
  const rows = await prisma.twoFactorLock.findMany({ where: { userId, ip: { in: [scope + ip, scope + GLOBAL_LOCK_IP] } } });
  const active = rows.filter((r) => isLockActive(r));
  if (!active.length) return null;
  return active.reduce((a, b) => (new Date(a.lockedUntil) > new Date(b.lockedUntil) ? a : b));
}

function sendLocked(res, lock) {
  const m = lock ? minutesUntil(lock.lockedUntil) : 1;
  return res.status(429).json({
    error: `Too many wrong codes. Try again in ${m} minute${m === 1 ? "" : "s"}.`,
    code: "TOO_MANY_ATTEMPTS",
  });
}

async function lockResponseIfLocked(res, userId, ip) {
  const lock = await getActiveLock(userId, ip);
  if (!lock) return false;
  sendLocked(res, lock);
  return true;
}

// Eine Zeile atomar fortschreiben. true = gezaehlt, false = Dauerkonflikt (fail-closed).
async function bumpLockRow(userId, ip) {
  const opts = lockOptsFor(ip);
  for (let attempt = 0; attempt < 8; attempt++) {
    const row = await prisma.twoFactorLock.findUnique({ where: { userId_ip: { userId, ip } } });
    const next = nextLockState(row, Date.now(), opts);
    const data = { failedCount: next.failedCount, firstFailedAt: next.firstFailedAt, lockedUntil: next.lockedUntil };
    if (!row) {
      try {
        await prisma.twoFactorLock.create({ data: { userId, ip, ...data } });
      } catch (err) {
        if (err.code === "P2002") continue; // paralleler Insert → neu lesen
        throw err;
      }
    } else {
      const { count } = await prisma.twoFactorLock.updateMany({
        where: { id: row.id, failedCount: row.failedCount, firstFailedAt: row.firstFailedAt, lockedUntil: row.lockedUntil },
        data,
      });
      if (count !== 1) continue; // jemand war schneller → neu lesen
    }
    if (next.justLocked) await notifyLock(userId, ip).catch((e) => console.error("2FA lock mail failed:", e.message));
    return true;
  }
  return false;
}

// Opportunistisch: abgelaufene Zeilen dieses Users loeschen (Fenster vorbei, nicht gesperrt)
async function cleanupLocks(userId) {
  const now = Date.now();
  const idle = [{ lockedUntil: null }, { lockedUntil: { lt: new Date(now) } }];
  await prisma.twoFactorLock.deleteMany({
    where: {
      userId,
      OR: [
        { NOT: { ip: { endsWith: GLOBAL_LOCK_IP } }, firstFailedAt: { lt: new Date(now - IP_LOCK_OPTS.windowMs) }, OR: idle },
        { ip: { endsWith: GLOBAL_LOCK_IP }, firstFailedAt: { lt: new Date(now - GLOBAL_LOCK_OPTS.windowMs) }, OR: idle },
      ],
    },
  });
}

// Zaehlt einen Fehlversuch (IP-Zeile + nutzerweit). Rueckgabe false = nicht sicher gezaehlt → Aufrufer lehnt ab.
async function registerFailure(userId, ip, scope = "") {
  const okIp = await bumpLockRow(userId, scope + ip);
  const okGlobal = await bumpLockRow(userId, scope + GLOBAL_LOCK_IP);
  cleanupLocks(userId).catch((e) => console.error("2FA lock cleanup failed:", e.message));
  if (!okIp || !okGlobal) {
    console.error(`2FA_LOCK_CONTENTION userId=${userId} ip=${ip} — rejecting (fail-closed)`);
    return false;
  }
  return true;
}

// Info-Mail nach einer Sperre, max. 1 pro Stunde je User (ueber alle Zeilen)
async function notifyLock(userId, ip) {
  const latest = await prisma.twoFactorLock.findFirst({
    where: { userId, notifiedAt: { not: null } },
    orderBy: { notifiedAt: "desc" },
    select: { notifiedAt: true },
  });
  if (!shouldSendLockMail(latest?.notifiedAt)) return;
  const row = await prisma.twoFactorLock.findUnique({ where: { userId_ip: { userId, ip } } });
  if (!row) return;
  // Nur einer gewinnt (Race-Schutz fuer die Mail)
  const { count } = await prisma.twoFactorLock.updateMany({
    where: { id: row.id, OR: [{ notifiedAt: null }, { notifiedAt: { lt: new Date(Date.now() - LOCK_MAIL_INTERVAL_MS) } }] },
    data: { notifiedAt: new Date() },
  });
  if (count !== 1) return;
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
  if (!user) return;
  await sendMail({
    to: user.email,
    subject: "Several incorrect two-factor codes on your SwipeShift account",
    text: "Several incorrect two-factor codes were entered for your SwipeShift account. For security, further code attempts are paused for 15 minutes.\n\nIf this wasn't you, change your password.",
    html: "<p>Several incorrect two-factor codes were entered for your SwipeShift account. For security, further code attempts are paused for 15 minutes.</p><p>If this wasn't you, change your password.</p>",
  });
}

// Ein korrekter Code loescht nur die Zeile der eigenen IP; die nutzerweite Zeile verfaellt ueber ihr Fenster
async function clearFailures(userId, ip, scope = "") {
  await prisma.twoFactorLock.deleteMany({ where: { userId, ip: scope + ip } });
}

// Alle offenen Codes/Challenges eines Users ungueltig machen (bei Aktivieren/Deaktivieren/Wechsel)
async function invalidateOpenCodes(userId, client = prisma) {
  await client.twoFactorCode.updateMany({
    where: { userId, consumedAt: null },
    data: { consumedAt: new Date() },
  });
}

async function remainingBackupCodes(userId) {
  return prisma.twoFactorBackupCode.count({ where: { userId, usedAt: null } });
}

// Zweiter Faktor per TOTP: aktueller Code (einmalig pro Zeitschritt) ODER (allowBackup) Backup-Code (wird verbraucht).
// Rueckgabe: { ok, usedBackup?, decryptFailed? } — decryptFailed ist ein Serverproblem und zaehlt NICHT als Fehlversuch.
async function verifyTotpFactor(userId, input, { allowBackup = true } = {}) {
  if (totp.looksLikeTotpCode(input)) {
    // CAS: bei Konflikt (parallele Re-Encrypt/Schritt-Verbrauch) einmal neu lesen und wiederholen
    for (let attempt = 0; attempt < 2; attempt++) {
      const user = await prisma.user.findUnique({
        where: { id: userId },
        select: { totpSecretEnc: true, totpLastStep: true },
      });
      if (!user?.totpSecretEnc) return { ok: false };
      let secret;
      try { secret = totp.decryptSecret(user.totpSecretEnc, userId); }
      catch (err) {
        console.error(`TOTP_DECRYPT_FAILED userId=${userId}: ${err.message}`);
        return { ok: false, decryptFailed: true };
      }
      const r = totp.verifyTotp(secret, input, { lastStep: user.totpLastStep });
      if (!r.ok) return { ok: false };
      const data = { totpLastStep: r.step };
      // Key-Rotation: mit altem Key verschluesselte Secrets beim ersten Erfolg neu verschluesseln
      if (totp.needsReencrypt(user.totpSecretEnc)) data.totpSecretEnc = totp.encryptSecret(secret, userId);
      const { count } = await prisma.user.updateMany({
        where: {
          id: userId,
          totpSecretEnc: user.totpSecretEnc,
          OR: [{ totpLastStep: null }, { totpLastStep: { lt: r.step } }],
        },
        data,
      });
      if (count === 1) return { ok: true };
    }
    return { ok: false };
  }

  if (!allowBackup) return { ok: false };
  const codes = await prisma.twoFactorBackupCode.findMany({
    where: { userId, usedAt: null },
    select: { id: true, codeHash: true },
  });
  const hit = totp.findBackupCodeHash(input, totp.getBackupPepper(), codes.map((c) => c.codeHash));
  if (!hit) return { ok: false };
  const row = codes.find((c) => c.codeHash === hit);
  const { count } = await prisma.twoFactorBackupCode.updateMany({
    where: { id: row.id, usedAt: null },
    data: { usedAt: new Date() },
  });
  if (count !== 1) return { ok: false };

  // Info-Mail (nicht blockierend)
  Promise.all([
    prisma.user.findUnique({ where: { id: userId }, select: { email: true } }),
    remainingBackupCodes(userId),
  ])
    .then(([u, left]) => u && sendMail({
      to: u.email,
      subject: "A SwipeShift backup code was used",
      text: `A backup code was just used to confirm a sign-in or security change on your SwipeShift account.\n\nBackup codes left: ${left}.\n\nIf this wasn't you, change your password and turn two-factor authentication off and on again to get new codes.`,
      html: `<p>A backup code was just used to confirm a sign-in or security change on your SwipeShift account.</p><p>Backup codes left: <b>${left}</b>.</p><p>If this wasn't you, change your password and turn two-factor authentication off and on again to get new codes.</p>`,
    }))
    .catch((err) => console.error("Backup-code info mail failed:", err.message));
  return { ok: true, usedBackup: true };
}

// Prueft einen Code gegen eine Challenge. Liefert den (verbrauchten) Datensatz oder einen Fehler-Code.
// E-Mail-Challenge: Code-Hash; TOTP-Challenge (Marker im codeHash): TOTP-/Backup-Code.
async function consumeCode(challengeId, code, { purpose, userId, ip } = {}) {
  const record = await prisma.twoFactorCode.findUnique({ where: { id: challengeId } });
  if (!record) return { error: "CODE_INVALID" };
  if (purpose && !purpose.includes(record.purpose)) return { error: "CODE_INVALID" };
  if (userId && record.userId !== userId) return { error: "CODE_INVALID" };

  const isTotp = record.codeHash === TOTP_CHALLENGE_MARKER;
  const user = await prisma.user.findUnique({
    where: { id: record.userId },
    select: { twoFactorEnabled: true, twoFactorMethod: true },
  });
  if (!user) return { error: "CODE_INVALID", isTotp };
  // Challenge-Art muss zur AKTUELLEN Methode passen (kein Downgrade ueber alte E-Mail-Challenges)
  if (!challengeMatchesUser(record.purpose, isTotp, user)) return { error: "CODE_INVALID", isTotp };
  const lock = await getActiveLock(record.userId, ip);
  if (lock) return { error: "LOCKED", isTotp, minutes: minutesUntil(lock.lockedUntil) };
  if (!isCodeUsable(record)) return { error: "CODE_EXPIRED", isTotp };

  // Versuch ZUERST atomar zaehlen — parallele Requests koennen die Grenze nicht umgehen
  const claim = await prisma.twoFactorCode.updateMany({
    where: { id: record.id, consumedAt: null, attempts: { lt: MAX_ATTEMPTS }, expiresAt: { gt: new Date() } },
    data: { attempts: { increment: 1 } },
  });
  if (claim.count !== 1) return { error: "CODE_EXPIRED", isTotp };

  let valid, usedBackup = false;
  if (isTotp) {
    const r = await verifyTotpFactor(record.userId, code);
    valid = r.ok;
    usedBackup = !!r.usedBackup;
    // Serverseitiges Entschluesselungsproblem: kein Fehlversuch fuer den Nutzer
    if (!valid && r.decryptFailed) return { error: "CODE_INVALID", isTotp };
  } else {
    valid = codeMatches(code, record.codeHash, JWT_SECRET);
  }

  if (!valid) {
    // Nicht sicher gezaehlt (Dauerkonflikt) → fail-closed
    if (!(await registerFailure(record.userId, ip))) return { error: "LOCKED", isTotp, minutes: 1 };
    return { error: "CODE_INVALID", isTotp };
  }

  // Race-sicher verbrauchen: nur einer gewinnt
  const { count } = await prisma.twoFactorCode.updateMany({
    where: { id: record.id, consumedAt: null },
    data: { consumedAt: new Date() },
  });
  if (count !== 1) {
    if (usedBackup) {
      console.error(`TWO_FACTOR backup code consumed, challenge not completed userId=${record.userId} challenge=${record.id}`);
      return { error: "BACKUP_CODE_CONSUMED", isTotp };
    }
    return { error: "CODE_EXPIRED", isTotp };
  }
  await clearFailures(record.userId, ip);
  return { record };
}

const CODE_ERRORS = {
  CODE_INVALID: "That code isn't right. Check your email and try again.",
  CODE_EXPIRED: "This code has expired. Request a new one.",
};
const TOTP_CODE_ERRORS = {
  CODE_INVALID: "That code isn't right. Check your authenticator app (or use a backup code) and try again.",
  CODE_EXPIRED: "This request has expired. Please start again.",
};

function codeErrorResponse(res, error, isTotp = false, minutes = 15) {
  if (error === "BACKUP_CODE_CONSUMED") {
    return res.status(409).json({
      error: "That backup code was used up, but the request could not be completed. Please try again with another code.",
      code: "BACKUP_CODE_CONSUMED",
    });
  }
  if (error === "LOCKED") {
    return res.status(429).json({
      error: `Too many wrong codes. Try again in ${minutes} minute${minutes === 1 ? "" : "s"}.`,
      code: "TOO_MANY_ATTEMPTS",
    });
  }
  const table = isTotp ? TOTP_CODE_ERRORS : CODE_ERRORS;
  return res.status(400).json({ error: table[error] || "Invalid code", code: error });
}

const codeSchema = z.object({
  challengeId: z.string().min(1),
  code: z.string().min(1).max(12),
});

const methodOf = currentMethod;

router.get("/2fa", requireAuth, async (req, res) => {
  const user = await prisma.user.findUnique({
    where: { id: req.auth.sub },
    select: { twoFactorEnabled: true, twoFactorMethod: true },
  });
  if (!user) return res.status(404).json({ error: "User not found" });
  const method = methodOf(user);
  return res.json({
    enabled: user.twoFactorEnabled,
    method,
    backupCodesRemaining: method === "totp" ? await remainingBackupCodes(req.auth.sub) : null,
  });
});

router.post("/2fa/request", requireAuth, sendLimiter, async (req, res) => {
  const parsed = z.object({
    action: z.enum(["enable", "disable"]),
    method: z.enum(["email", "totp"]).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });
  const { action } = parsed.data;
  const wantsTotp = action === "enable" && parsed.data.method === "totp";

  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (await lockResponseIfLocked(res, user.id, ipOf(req))) return;

    if (action === "enable" && !wantsTotp && user.twoFactorEnabled)
      return res.status(409).json({ error: "Two-factor authentication is already on.", code: "ALREADY_ENABLED" });
    // Entscheidung: Wechsel email→totp ist erlaubt (Mail-Code genuegt als Bestaetigung, E-Mail-2FA bleibt bis
    // zur TOTP-Bestaetigung aktiv). Bei aktivem TOTP: 409.
    if (wantsTotp && methodOf(user) === "totp")
      return res.status(409).json({ error: "The authenticator app is already on.", code: "ALREADY_ENABLED" });
    if (action === "disable" && !user.twoFactorEnabled)
      return res.status(409).json({ error: "Two-factor authentication is already off.", code: "ALREADY_DISABLED" });
    if (action === "enable" && !user.emailVerifiedAt)
      return res.status(403).json({ error: "Please verify your email address first.", code: "EMAIL_NOT_VERIFIED" });

    // Abschalten bei TOTP: keine Mail, Bestaetigung per aktuellem Code der Authenticator-App
    if (action === "disable" && methodOf(user) === "totp")
      return res.json(await issueTotpChallenge(user, "disable"));

    return res.json(await issueTwoFactorCode(user, wantsTotp ? "totp_enable" : action));
  } catch (err) {
    console.error("POST /auth/2fa/request error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

router.post("/2fa/confirm", requireAuth, codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const { record, error, isTotp, minutes } = await consumeCode(parsed.data.challengeId, parsed.data.code, {
      purpose: ["enable", "disable"],
      userId: req.auth.sub,
      ip: ipOf(req),
    });
    if (error) return codeErrorResponse(res, error, isTotp, minutes);

    const enabled = record.purpose === "enable";
    await prisma.$transaction(async (tx) => {
      await tx.user.update({
        where: { id: req.auth.sub },
        data: enabled
          ? { twoFactorEnabled: true, twoFactorMethod: "email", totpPendingEnc: null, totpPendingAt: null }
          : {
              // Alles TOTP-bezogene mit entfernen
              twoFactorEnabled: false, twoFactorMethod: null,
              totpSecretEnc: null, totpPendingEnc: null, totpPendingAt: null, totpLastStep: null,
            },
      });
      if (!enabled) await tx.twoFactorBackupCode.deleteMany({ where: { userId: req.auth.sub } });
      await invalidateOpenCodes(req.auth.sub, tx);
      await tx.userSession.updateMany({ where: { userId: req.auth.sub }, data: { reauthAt: null } }); // Step-up verfaellt
    });
    return res.json({ ok: true, enabled, method: enabled ? "email" : null });
  } catch (err) {
    console.error("POST /auth/2fa/confirm error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/2fa/verify-login", codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const { record, error, isTotp, minutes } = await consumeCode(parsed.data.challengeId, parsed.data.code, { purpose: ["login"], ip: ipOf(req) });
    if (error) return codeErrorResponse(res, error, isTotp, minutes);

    const user = await prisma.user.findUnique({ where: { id: record.userId } });
    if (!user) return codeErrorResponse(res, "CODE_INVALID");

    // Alle uebrigen offenen Login-Challenges (z.B. aeltere Mail-Codes) sind damit erledigt
    await prisma.twoFactorCode.updateMany({
      where: { userId: user.id, purpose: "login", consumedAt: null },
      data: { consumedAt: new Date() },
    });

    const token = await createSession(user, req);
    const isSocial = user.passwordHash === "SOCIAL_LOGIN";
    return res.json({
      token,
      isNewUser: false,
      user: authUserPayload(user, isSocial ? { profilePhotoUrl: user.profilePhotoUrl ?? null } : {}),
    });
  } catch (err) {
    if (respondIfRestricted(err, res)) return;
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
    const isTotp = record.codeHash === TOTP_CHALLENGE_MARKER;
    // Die Challenge-Art muss zur aktuellen Methode passen (sonst: neu einloggen)
    if (!challengeMatchesUser("login", isTotp, record.user)) {
      return res.status(400).json({ error: "Please sign in again.", code: "CHALLENGE_EXPIRED" });
    }
    if (isTotp) {
      return res.status(400).json({
        error: "Codes from your authenticator app can't be resent. Open the app, or use a backup code.",
        code: "RESEND_NOT_AVAILABLE",
      });
    }
    return res.json(await issueTwoFactorCode(record.user, "login"));
  } catch (err) {
    console.error("POST /auth/2fa/resend error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

// ───────────────────────── TOTP (Authenticator-App) ─────────────────────────

// Re-Auth: erst nach gueltigem Mail-Code (purpose totp_enable) gibt es das Pending-Secret.
router.post("/2fa/totp/setup", requireAuth, codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const { record, error, isTotp, minutes } = await consumeCode(parsed.data.challengeId, parsed.data.code, {
      purpose: ["totp_enable"],
      userId: req.auth.sub,
      ip: ipOf(req),
    });
    if (error) return codeErrorResponse(res, error, isTotp, minutes);

    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (methodOf(user) === "totp")
      return res.status(409).json({ error: "The authenticator app is already on.", code: "ALREADY_ENABLED" });

    const secret = totp.generateSecret();
    await prisma.user.update({
      where: { id: user.id },
      data: { totpPendingEnc: totp.encryptSecret(secret, user.id), totpPendingAt: new Date() },
    });
    return res.json({
      secret,
      otpauthUri: totp.otpauthUri(secret, user.email),
      issuer: totp.ISSUER,
      account: user.email,
    });
  } catch (err) {
    console.error("POST /auth/2fa/totp/setup error:", err);
    return res.status(500).json({ error: "Could not start the setup. Please try again." });
  }
});

router.post("/2fa/totp/confirm", requireAuth, codeLimiter, async (req, res) => {
  const parsed = z.object({ code: z.string().min(1).max(12) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (await lockResponseIfLocked(res, user.id, ipOf(req))) return;
    if (methodOf(user) === "totp")
      return res.status(409).json({ error: "Two-factor authentication is already on.", code: "ALREADY_ENABLED" });
    if (!user.totpPendingEnc)
      return res.status(400).json({ error: "Start the setup first.", code: "NO_PENDING_SETUP" });
    if (!totp.isPendingFresh(user.totpPendingAt))
      return res.status(400).json({ error: "The setup took too long. Please start again.", code: "SETUP_EXPIRED" });

    let secret;
    try { secret = totp.decryptSecret(user.totpPendingEnc, user.id); }
    catch (err) {
      console.error(`TOTP_DECRYPT_FAILED (pending) userId=${user.id}: ${err.message}`);
      return res.status(400).json({ error: "Start the setup again.", code: "NO_PENDING_SETUP" });
    }

    const r = totp.verifyTotp(secret, parsed.data.code);
    if (!r.ok) {
      if (!(await registerFailure(user.id, ipOf(req)))) return sendLocked(res, null);
      return codeErrorResponse(res, "CODE_INVALID", true);
    }

    const wasEmail = methodOf(user) === "email";
    const freshAfter = new Date(Date.now() - totp.PENDING_TTL_MS);
    const backupCodes = await prisma.$transaction(async (tx) => {
      // Atomar: nur wenn das Pending-Secret noch exakt dasselbe (und frisch) ist
      const { count } = await tx.user.updateMany({
        where: {
          id: user.id,
          totpPendingEnc: user.totpPendingEnc,
          totpPendingAt: { gt: freshAfter },
          OR: [{ twoFactorEnabled: false }, { twoFactorMethod: { not: "totp" } }],
        },
        data: {
          twoFactorEnabled: true, twoFactorMethod: "totp",
          totpSecretEnc: user.totpPendingEnc, totpPendingEnc: null, totpPendingAt: null,
          totpLastStep: r.step, // der Bestaetigungs-Code ist damit verbraucht
        },
      });
      if (count !== 1) return null;

      // Erst jetzt Backup-Codes erzeugen
      const codes = totp.generateBackupCodes();
      const pepper = totp.getBackupPepper();
      await tx.twoFactorBackupCode.deleteMany({ where: { userId: user.id } });
      await tx.twoFactorBackupCode.createMany({
        data: codes.map((c) => ({ userId: user.id, codeHash: totp.hashBackupCode(c, pepper) })),
      });
      // Methodenwechsel/Aktivierung: alle offenen Codes ungueltig
      await invalidateOpenCodes(user.id, tx);
      await tx.userSession.updateMany({ where: { userId: user.id }, data: { reauthAt: null } }); // Step-up verfaellt
      return codes;
    });
    if (!backupCodes)
      return res.status(409).json({ error: "This setup is no longer valid. Please start again.", code: "SETUP_EXPIRED" });

    // Methodenwechsel email→totp: Sicherheits-Mail (nicht blockierend)
    if (wasEmail) sendMail({ to: user.email, ...methodChangedMail("totp") }).catch((err) => console.error("2FA switch mail failed:", err.message));

    // Klartext-Codes nur in dieser einen Antwort
    return res.json({ ok: true, enabled: true, method: "totp", backupCodes });
  } catch (err) {
    console.error("POST /auth/2fa/totp/confirm error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ───────────────────────── Wechsel Authenticator → E-Mail-Codes ─────────────────────────
// Schritt 1: aktueller TOTP-/Backup-Code (Besitz des bisherigen Faktors) → Mail-Code, an User+Sitzung gebunden.
// Schritt 2: Mail-Code (Postfach funktioniert) → atomar method=email, TOTP-Daten + Backup-Codes weg.

router.post("/2fa/switch-to-email/start", requireAuth, sendLimiter, async (req, res) => {
  const parsed = z.object({ code: z.string().min(1).max(32) }).safeParse(req.body);
  if (!parsed.success || !req.auth.sid) return res.status(400).json({ error: "Invalid input" });

  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (await lockResponseIfLocked(res, user.id, ipOf(req))) return;
    const can = canSwitchMethod(user, "email");
    if (!can.ok)
      return res.status(409).json({
        error: can.code === "NOT_ENABLED" ? "Two-factor authentication isn't turned on." : "Email codes are already on.",
        code: can.code,
      });

    const check = await verifyTotpFactor(user.id, parsed.data.code);
    if (!check.ok) {
      if (check.decryptFailed) return res.status(500).json({ error: "Could not verify the code. Please try again." });
      if (!(await registerFailure(user.id, ipOf(req)))) return sendLocked(res, null);
      return codeErrorResponse(res, "CODE_INVALID", true);
    }
    await clearFailures(user.id, ipOf(req));

    // Der Faktor ist jetzt verbraucht (TOTP-Schritt bzw. Backup-Code). Scheitert der Mailversand,
    // klar sagen, dass ein NEUER Code noetig ist — sonst versucht man es mit demselben Code erneut.
    try {
      return res.json(await issueTwoFactorCode(user, "switch_email", { sessionId: req.auth.sid }));
    } catch (mailErr) {
      console.error("POST /auth/2fa/switch-to-email/start mail error:", mailErr);
      return res.status(503).json({
        error: "We couldn't send the email code. Wait for a new code in your authenticator app (or use another backup code) and try again.",
        code: "MAIL_FAILED",
      });
    }
  } catch (err) {
    console.error("POST /auth/2fa/switch-to-email/start error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

router.post("/2fa/switch-to-email/confirm", requireAuth, codeLimiter, async (req, res) => {
  const parsed = codeSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const userId = req.auth.sub;
    // Bindung VOR dem Verbrauch pruefen: ein fremder/anderer Sitzungs-Code bleibt unberuehrt und zaehlt nur als ungueltig
    const pre = await prisma.twoFactorCode.findUnique({ where: { id: parsed.data.challengeId } });
    if (!switchBindingValid(pre, { userId, sessionId: req.auth.sid })) return codeErrorResponse(res, "CODE_INVALID");

    const { error, isTotp, minutes } = await consumeCode(parsed.data.challengeId, parsed.data.code, {
      purpose: ["switch_email"],
      userId,
      ip: ipOf(req),
    });
    if (error) return codeErrorResponse(res, error, isTotp, minutes);

    const user = await prisma.user.findUnique({ where: { id: userId }, select: { email: true } });
    const switched = await prisma.$transaction(async (tx) => {
      const { count } = await tx.user.updateMany({
        where: { id: userId, twoFactorEnabled: true, twoFactorMethod: "totp" },
        data: {
          twoFactorMethod: "email",
          totpSecretEnc: null, totpPendingEnc: null, totpPendingAt: null, totpLastStep: null,
        },
      });
      if (count !== 1) return false;
      await tx.twoFactorBackupCode.deleteMany({ where: { userId } });
      await invalidateOpenCodes(userId, tx);
      await tx.userSession.updateMany({ where: { userId }, data: { reauthAt: null } }); // Step-up verfaellt
      return true;
    });
    if (!switched)
      return res.status(409).json({ error: "The authenticator app isn't turned on anymore.", code: "NOT_ENABLED" });

    if (user) sendMail({ to: user.email, ...methodChangedMail("email") }).catch((err) => console.error("2FA switch mail failed:", err.message));
    return res.json({ ok: true, enabled: true, method: "email" });
  } catch (err) {
    console.error("POST /auth/2fa/switch-to-email/confirm error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// Neue Backup-Codes (die alten werden ungueltig) — nur mit gueltigem aktuellem TOTP-Code
router.post("/2fa/totp/backup-codes", requireAuth, codeLimiter, async (req, res) => {
  const parsed = z.object({ code: z.string().min(1).max(12) }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (methodOf(user) !== "totp")
      return res.status(409).json({ error: "The authenticator app isn't turned on.", code: "NOT_ENABLED" });
    if (await lockResponseIfLocked(res, user.id, ipOf(req))) return;

    // Nur der Authenticator-Code zaehlt (kein Backup-Code, sonst laesst sich der Vorrat nicht "nachfuellen")
    const check = await verifyTotpFactor(user.id, parsed.data.code, { allowBackup: false });
    if (!check.ok) {
      if (!check.decryptFailed && !(await registerFailure(user.id, ipOf(req)))) return sendLocked(res, null);
      return codeErrorResponse(res, "CODE_INVALID", true);
    }
    await clearFailures(user.id, ipOf(req));

    const codes = totp.generateBackupCodes();
    const pepper = totp.getBackupPepper();
    await prisma.$transaction([
      prisma.twoFactorBackupCode.deleteMany({ where: { userId: user.id } }),
      prisma.twoFactorBackupCode.createMany({
        data: codes.map((c) => ({ userId: user.id, codeHash: totp.hashBackupCode(c, pepper) })),
      }),
      prisma.userSession.updateMany({ where: { userId: user.id }, data: { reauthAt: null } }), // Step-up verfaellt
    ]);
    return res.json({ ok: true, backupCodes: codes });
  } catch (err) {
    console.error("POST /auth/2fa/totp/backup-codes error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ───────────────────────── Step-up Re-Auth (Auszahlungsdaten) ─────────────────────────
// Nachweis haengt an der aktuellen UserSession (reauthAt), gueltig 10 min (utils/reauth.js).
// Fehlversuche zaehlen in dieselbe Sperre wie 2FA (registerFailure / TwoFactorLock).

const REAUTH_USER_SELECT = { id: true, email: true, passwordHash: true, twoFactorEnabled: true, twoFactorMethod: true };

function reauthLocked(res, lock) {
  const m = lock ? minutesUntil(lock.lockedUntil) : 1;
  return res.status(429).json({
    error: `Too many wrong attempts. Try again in ${m} minute${m === 1 ? "" : "s"}.`,
    code: "TOO_MANY_ATTEMPTS",
    retryAfterMinutes: m,
  });
}

const methodsLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 60,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many requests, try again later.", code: "RATE_LIMITED" },
});

router.get("/me/reauth/methods", requireAuth, methodsLimiter, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub }, select: REAUTH_USER_SELECT });
    if (!user) return res.status(404).json({ error: "User not found" });
    return res.json({ methods: availableMethods(user), emailHint: maskEmail(user.email) });
  } catch (err) {
    console.error("GET /auth/me/reauth/methods error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/me/reauth/email-code", requireAuth, sendLimiter, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({ where: { id: req.auth.sub } });
    if (!user) return res.status(404).json({ error: "User not found" });
    const lock = await getActiveLock(user.id, ipOf(req), REAUTH_SCOPE);
    if (lock) return reauthLocked(res, lock);
    if (!availableMethods(user).includes("email"))
      return res.status(400).json({ error: "This method isn't available for your account.", code: "METHOD_UNAVAILABLE" });
    return res.json(await issueTwoFactorCode(user, "reauth"));
  } catch (err) {
    console.error("POST /auth/me/reauth/email-code error:", err);
    return res.status(500).json({ error: "Could not send the code. Please try again." });
  }
});

// Prueft den E-Mail-Code (purpose reauth) des Users. Rueckgabe: "ok" | "CODE_INVALID" | "CODE_EXPIRED" | "LOCKED"
async function verifyReauthEmailCode(userId, code, ip) {
  const record = await prisma.twoFactorCode.findFirst({
    where: { userId, purpose: "reauth", consumedAt: null },
    orderBy: { createdAt: "desc" },
  });
  if (record && !record.consumedAt && record.attempts >= MAX_ATTEMPTS && new Date(record.expiresAt).getTime() > Date.now())
    return "CODE_ATTEMPTS_EXCEEDED";
  if (!record || !isCodeUsable(record)) return "CODE_EXPIRED";
  const claim = await prisma.twoFactorCode.updateMany({
    where: { id: record.id, consumedAt: null, attempts: { lt: MAX_ATTEMPTS }, expiresAt: { gt: new Date() } },
    data: { attempts: { increment: 1 } },
  });
  if (claim.count !== 1) return "CODE_ATTEMPTS_EXCEEDED";
  if (!codeMatches(code, record.codeHash, JWT_SECRET)) {
    return (await registerFailure(userId, ip, REAUTH_SCOPE)) ? "CODE_INVALID" : "LOCKED";
  }
  const { count } = await prisma.twoFactorCode.updateMany({
    where: { id: record.id, consumedAt: null },
    data: { consumedAt: new Date() },
  });
  return count === 1 ? "ok" : "CODE_EXPIRED";
}

router.post("/me/reauth", requireAuth, codeLimiter, async (req, res) => {
  const parsed = z.object({
    method: z.enum(["totp", "password", "email"]),
    password: z.string().min(1).max(200).optional(),
    code: z.string().min(1).max(32).optional(),
  }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input", code: "INVALID_INPUT" });
  const { method, password, code } = parsed.data;
  if (method === "password" ? !password : !code)
    return res.status(400).json({ error: "Invalid input", code: "INVALID_INPUT" });

  try {
    const userId = req.auth.sub;
    const ip = ipOf(req);
    const user = await prisma.user.findUnique({ where: { id: userId }, select: REAUTH_USER_SELECT });
    if (!user) return res.status(404).json({ error: "User not found" });
    if (!availableMethods(user).includes(method))
      return res.status(400).json({ error: "This method isn't available for your account.", code: "METHOD_UNAVAILABLE" });

    const lock = await getActiveLock(userId, ip, REAUTH_SCOPE);
    if (lock) return reauthLocked(res, lock);

    let ok = false;
    if (method === "totp") {
      const r = await verifyTotpFactor(userId, code);
      ok = r.ok;
      if (!ok && r.decryptFailed) return res.status(500).json({ error: "Could not verify the code. Please try again." });
    } else if (method === "password") {
      ok = await bcrypt.compare(password, user.passwordHash);
    } else {
      const r = await verifyReauthEmailCode(userId, code, ip);
      if (r === "LOCKED") return reauthLocked(res, null);
      if (r === "CODE_ATTEMPTS_EXCEEDED")
        return res.status(400).json({ error: "Too many attempts. Request a new code.", code: "CODE_ATTEMPTS_EXCEEDED" });
      if (r === "CODE_EXPIRED")
        return res.status(400).json({ error: "This code has expired. Request a new one.", code: "CODE_EXPIRED" });
      ok = r === "ok";
      if (!ok) return res.status(400).json({ error: "That code isn't right. Check your email and try again.", code: "CODE_INVALID" });
    }

    if (!ok) {
      if (!(await registerFailure(userId, ip, REAUTH_SCOPE))) return reauthLocked(res, null);
      const wrong = method === "password"
        ? { error: "That password isn't right.", code: "PASSWORD_INVALID" }
        : { error: "That code isn't right. Check your authenticator app (or use a backup code) and try again.", code: "CODE_INVALID" };
      return res.status(400).json(wrong);
    }

    await clearFailures(userId, ip, REAUTH_SCOPE);
    const now = new Date();
    const { count } = await prisma.userSession.updateMany({
      where: { id: req.auth.sid, userId, revokedAt: null, expiresAt: { gt: now } },
      data: { reauthAt: now },
    });
    if (count !== 1) return res.status(401).json({ error: "Your session has ended. Please sign in again.", code: "SESSION_REVOKED" });
    return res.json({ validUntil: reauthValidUntil(now).toISOString() });
  } catch (err) {
    console.error("POST /auth/me/reauth error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
