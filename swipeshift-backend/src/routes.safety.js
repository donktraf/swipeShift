// src/routes.safety.js — Melden + Blockieren (App-Store Guideline 1.2)
const express = require("express");
const router  = express.Router();
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const { sendMail } = require("./mailer");
const rateLimit = require("express-rate-limit");
const { validateReport } = require("./utils/safety");

// Pro User (JWT ist per requireAuth gesetzt, Limiter laeuft danach); Fallback IP
const keyByUser = (req) => req.auth?.sub || req.ip;
const reportLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 10, keyGenerator: keyByUser, validate: { keyGeneratorIpFallback: false },
  standardHeaders: true, legacyHeaders: false,
  message: { error: "Too many reports, try again later.", code: "RATE_LIMITED" },
});
const blockLimiter = rateLimit({
  windowMs: 60 * 60 * 1000, max: 60, keyGenerator: keyByUser, validate: { keyGeneratorIpFallback: false },
  standardHeaders: true, legacyHeaders: false,
  message: { error: "Too many requests, try again later.", code: "RATE_LIMITED" },
});

function handle(label, fn) {
  return async (req, res) => {
    try {
      await fn(req, res);
    } catch (err) {
      console.error(`${label} error:`, err);
      if (!res.headersSent) res.status(500).json({ error: "Internal server error" });
    }
  };
}

// ─── POST /safety/reports ───────────────────────────────────────────────────
// Body: { reportedUserId, conversationId?, reason, details? }
router.post("/reports", requireAuth, reportLimiter, handle("POST /safety/reports", async (req, res) => {
  const reporterId = req.auth.sub;
  const { reportedUserId, conversationId } = req.body || {};

  const check = validateReport(req.body);
  if (!check.ok) return res.status(400).json({ error: check.error });
  if (typeof reportedUserId !== "string" || !reportedUserId) {
    return res.status(400).json({ error: "reportedUserId required" });
  }
  if (reportedUserId === reporterId) {
    return res.status(400).json({ error: "You can't report yourself" });
  }

  if (conversationId !== undefined && conversationId !== null) {
    const conv = await prisma.conversation.findUnique({
      where:  { id: String(conversationId) },
      select: { workerId: true, employerId: true },
    });
    const ids = conv ? [conv.workerId, conv.employerId] : [];
    if (!conv || !ids.includes(reporterId)) {
      return res.status(403).json({ error: "Not a participant" });
    }
    if (!ids.includes(reportedUserId)) {
      return res.status(400).json({ error: "Reported user is not part of this conversation" });
    }
  }

  // Ohne Conversation nur melden, wenn es eine Beziehung gibt (Conversation oder Apply auf einen Job des anderen)
  if (conversationId === undefined || conversationId === null) {
    const related = await prisma.conversation.findFirst({
      where: { OR: [
        { workerId: reporterId, employerId: reportedUserId },
        { workerId: reportedUserId, employerId: reporterId },
      ] },
      select: { id: true },
    }) || await prisma.apply.findFirst({
      where: { OR: [
        { userId: reporterId, job: { employerId: reportedUserId } },
        { userId: reportedUserId, job: { employerId: reporterId } },
      ] },
      select: { id: true },
    });
    if (!related) return res.status(403).json({ error: "You can only report users you have interacted with." });
  }

  const reported = await prisma.user.findUnique({
    where: { id: reportedUserId },
    select: { id: true, email: true, firstName: true, lastName: true },
  });
  if (!reported) return res.status(404).json({ error: "User not found" });

  const convId = conversationId ?? null;
  const existing = await prisma.userReport.findFirst({
    where: { reporterId, reportedUserId, conversationId: convId, status: "open" },
    select: { id: true },
  });
  if (existing) {
    return res.status(409).json({ error: "You already reported this user. Our team is reviewing it.", code: "ALREADY_REPORTED" });
  }

  const report = await prisma.userReport.create({
    data: { reporterId, reportedUserId, conversationId: convId, reason: check.value.reason, details: check.value.details },
  });

  // Mail an Support — Fehler duerfen den Request nicht scheitern lassen
  try {
    const reporter = await prisma.user.findUnique({ where: { id: reporterId }, select: { email: true } });
    await sendMail({
      to: process.env.SUPPORT_EMAIL || "support@swipeshift.app",
      subject: `[SwipeShift] User report ${report.id} (${report.reason})`,
      text: [
        `Report ID: ${report.id}`,
        `Reason: ${report.reason}`,
        `Reporter: ${reporterId} (${reporter?.email ?? "?"})`,
        `Reported: ${reportedUserId} (${reported.email})`,
        `Conversation: ${convId ?? "-"}`,
        "",
        report.details ?? "(no details)",
      ].join("\n"),
    });
  } catch (err) {
    console.error("POST /safety/reports mail error:", err);
  }

  return res.status(201).json({ ok: true, id: report.id });
}));

// ─── POST /safety/blocks { userId } (idempotent) ────────────────────────────
router.post("/blocks", requireAuth, blockLimiter, handle("POST /safety/blocks", async (req, res) => {
  const blockerId = req.auth.sub;
  const blockedId = req.body?.userId;
  if (typeof blockedId !== "string" || !blockedId) return res.status(400).json({ error: "userId required" });
  if (blockedId === blockerId) return res.status(400).json({ error: "You can't block yourself" });

  const target = await prisma.user.findUnique({ where: { id: blockedId }, select: { id: true } });
  if (!target) return res.status(404).json({ error: "User not found" });

  await prisma.userBlock.upsert({
    where:  { blockerId_blockedId: { blockerId, blockedId } },
    create: { blockerId, blockedId },
    update: {},
  });
  return res.json({ ok: true });
}));

// ─── DELETE /safety/blocks/:userId ──────────────────────────────────────────
router.delete("/blocks/:userId", requireAuth, blockLimiter, handle("DELETE /safety/blocks/:userId", async (req, res) => {
  await prisma.userBlock.deleteMany({ where: { blockerId: req.auth.sub, blockedId: req.params.userId } });
  return res.json({ ok: true });
}));

// ─── GET /safety/blocks ─────────────────────────────────────────────────────
router.get("/blocks", requireAuth, handle("GET /safety/blocks", async (req, res) => {
  const blocks = await prisma.userBlock.findMany({
    where: { blockerId: req.auth.sub },
    orderBy: { createdAt: "desc" },
  });
  const users = await prisma.user.findMany({
    where: { id: { in: blocks.map(b => b.blockedId) } },
    select: { id: true, firstName: true, lastName: true },
  });
  const map = Object.fromEntries(users.map(u => [u.id, u]));
  return res.json({
    blocks: blocks.map(b => ({
      userId: b.blockedId,
      name: `${map[b.blockedId]?.firstName ?? ""} ${map[b.blockedId]?.lastName ?? ""}`.trim() || "User",
      createdAt: b.createdAt,
    })),
  });
}));

module.exports = router;
