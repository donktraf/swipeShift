// src/routes.settings.js
// Konto-Einstellungen. Gemountet unter /auth.
//
//   GET   /auth/me/settings   { settings, paused }   (Kontonummer nur als accountLast4)
//   PATCH /auth/me/settings   Teil-Aenderung, siehe src/utils/settings.js
//   POST  /auth/me/pause      { paused: true|false }

const express = require("express");
const { z } = require("zod");
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const events = require("./notifyEvents");
const { sendMail } = require("./mailer");
const { applyPatch, publicSettings } = require("./utils/settings");
const { payoutChangeMail } = require("./utils/payoutMail");

const router = express.Router();

router.get("/me/settings", requireAuth, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.auth.sub },
      select: { settings: true, pausedAt: true },
    });
    if (!user) return res.status(404).json({ error: "User not found" });
    return res.json({ settings: publicSettings(user.settings), paused: !!user.pausedAt });
  } catch (err) {
    console.error("GET /auth/me/settings error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// TODO: Read-Modify-Write auf User.settings ist nicht atomar — zwei gleichzeitige PATCHes
// koennen sich gegenseitig ueberschreiben (Last write wins). Optimistic Locking/jsonb_set erwaegen.
router.patch("/me/settings", requireAuth, async (req, res) => {
  try {
    const user = await prisma.user.findUnique({
      where: { id: req.auth.sub },
      select: { settings: true, email: true },
    });
    if (!user) return res.status(404).json({ error: "User not found" });

    const { settings, error, payoutDetailsChanged, payoutChanges } = applyPatch(user.settings, req.body, { userId: req.auth.sub });
    if (error) return res.status(400).json({ error, code: "INVALID_SETTINGS" });

    await prisma.user.update({ where: { id: req.auth.sub }, data: { settings } });
    // Sicherheitsmail bei geaenderten Auszahlungsdaten (immer, nicht blockierend).
    // TODO: Re-Auth (Passwort/2FA) vor dem Aendern von Auszahlungsdaten verlangen.
    if (payoutDetailsChanged) {
      sendMail({ to: user.email, ...payoutChangeMail(settings, payoutChanges) })
        .catch((err) => console.error("Payout change mail failed:", err.message));
    }
    return res.json({ settings: publicSettings(settings) });
  } catch (err) {
    console.error("PATCH /auth/me/settings error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.post("/me/pause", requireAuth, async (req, res) => {
  const parsed = z.object({ paused: z.boolean() }).safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });
  try {
    const before = await prisma.user.findUnique({ where: { id: req.auth.sub }, select: { pausedAt: true } });
    const updated = await prisma.user.update({
      where: { id: req.auth.sub },
      data: { pausedAt: parsed.data.paused ? new Date() : null },
      select: { pausedAt: true },
    });
    // Nur bei echtem Wechsel benachrichtigen (account-Kategorie, geht auch im pausierten Zustand); fire-and-forget
    if (!!before?.pausedAt !== !!updated.pausedAt) events.accountPauseChanged(req.auth.sub, !!updated.pausedAt);
    return res.json({ paused: !!updated.pausedAt });
  } catch (err) {
    console.error("POST /auth/me/pause error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
