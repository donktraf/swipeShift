// src/routes.pushDevices.js  (gemountet unter /auth)
//   POST   /auth/me/push-devices        { token, environment: "sandbox"|"production" }  → Upsert, an aktuelle Session gebunden
//   DELETE /auth/me/push-devices/:token → nur eigene Geraete

const express = require("express");
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const { isValidDeviceToken, normalizeEnvironment } = require("./utils/pushPayload");

const router = express.Router();

router.post("/me/push-devices", requireAuth, async (req, res) => {
  const token = typeof req.body?.token === "string" ? req.body.token.trim().toLowerCase() : "";
  const environment = normalizeEnvironment(req.body?.environment);
  if (!isValidDeviceToken(token)) return res.status(400).json({ error: "Invalid device token" });
  if (!environment) return res.status(400).json({ error: "Invalid environment" });
  try {
    const now = new Date();
    // Token gehoert immer dem zuletzt eingeloggten User (Geraetewechsel/Account-Wechsel auf demselben Geraet)
    await prisma.pushDevice.upsert({
      where: { token },
      create: { token, environment, userId: req.auth.sub, sessionId: req.auth.sid ?? null, lastSeenAt: now },
      update: { environment, userId: req.auth.sub, sessionId: req.auth.sid ?? null, lastSeenAt: now },
    });
    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /auth/me/push-devices error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

router.delete("/me/push-devices/:token", requireAuth, async (req, res) => {
  try {
    const token = String(req.params.token || "").trim().toLowerCase();
    await prisma.pushDevice.deleteMany({ where: { token, userId: req.auth.sub } });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /auth/me/push-devices/:token error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
