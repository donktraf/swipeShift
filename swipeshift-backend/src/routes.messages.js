// src/routes.messages.js
const express = require("express");
const router  = express.Router();
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");

// ─── Conversation-Status → iOS ConversationStatus ───────────────────────────
// "active"    → today (shift within 24h) oder upcoming
// "completed" → completed
// "cancelled" → cancelled
function deriveStatus(job, convStatus) {
  if (convStatus === "completed") return "completed";
  if (convStatus === "cancelled") return "cancelled";
  if (!job?.startTime) return "upcoming";
  const diff = new Date(job.startTime) - new Date();
  if (diff >= 0 && diff <= 24 * 3600 * 1000) return "today";
  return "upcoming";
}

// Conversation-Response-Shape für iOS
function formatConversation(conv, currentUserId) {
  const job      = conv.job;
  const isWorker = conv.workerId === currentUserId;

  // Worker sieht: company als Titel, logoEmoji des Jobs
  // Employer sieht: worker firstName+lastName als Titel, Person-Emoji
  const lastMsg = conv.messages.length > 0
    ? conv.messages[conv.messages.length - 1]
    : null;

  const unreadCount = conv.messages.filter(
    m => !m.isRead && m.senderId !== currentUserId
  ).length;

  return {
    id:              conv.id,
    applyId:         conv.applyId,
    jobId:           job.id,
    jobTitle:        job.title,
    company:         isWorker
                       ? job.company
                       : (() => {
                           const w = conv.worker;
                           return w ? `${w.firstName ?? ""} ${w.lastName ?? ""}`.trim() : "Worker";
                         })(),
    logoEmoji:       isWorker ? job.logoEmoji : "👤",
    status:          deriveStatus(job, conv.status),
    jobDate:         job.startTime ?? conv.createdAt,
    lastMessage:     lastMsg?.text ?? "",
    lastMessageTime: lastMsg?.createdAt ?? conv.createdAt,
    isRead:          unreadCount === 0,
    messages:        conv.messages.map(m => ({
      id:            m.id,
      text:          m.text,
      isFromUser:    m.senderId === currentUserId,
      timestamp:     m.createdAt,
      isSystemMessage: m.isSystem,
    })),
  };
}

// ─── GET /messages ─────────────────────────────────────────────────────────
// Gibt alle Konversationen des eingeloggten Users zurück (worker oder employer)
router.get("/", requireAuth, async (req, res) => {
  const userId = req.auth.sub;

  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { role: true, firstName: true, lastName: true },
  });

  if (!user) return res.status(401).json({ error: "User not found" });

  const isWorker = user.role === "worker";

  const conversations = await prisma.conversation.findMany({
    where: isWorker
      ? { workerId: userId }
      : { employerId: userId },
    include: {
      job: {
        select: {
          id: true, title: true, company: true, logoEmoji: true,
          startTime: true, payAmount: true, payText: true,
        },
      },
      messages: {
        orderBy: { createdAt: "asc" },
      },
      ...(isWorker ? {} : {
        worker: { // brauchen wir für den Employer (zeigt Worker-Name)
          // Worker ist ein separates Model, wir brauchen den User
        }
      }),
    },
    orderBy: { updatedAt: "desc" },
  });

  // Worker-User-Daten für Employer-Sicht nachladen
  let workerMap = {};
  if (!isWorker) {
    const workerIds = [...new Set(conversations.map(c => c.workerId))];
    const workers = await prisma.user.findMany({
      where: { id: { in: workerIds } },
      select: { id: true, firstName: true, lastName: true },
    });
    workerMap = Object.fromEntries(workers.map(w => [w.id, w]));
  }

  const result = conversations.map(conv => {
    const enriched = { ...conv };
    if (!isWorker) {
      enriched.worker = workerMap[conv.workerId] ?? null;
    }
    return formatConversation(enriched, userId);
  });

  return res.json(result);
});

// ─── POST /messages/:conversationId ─────────────────────────────────────────
// Nachricht senden
router.post("/:conversationId", requireAuth, async (req, res) => {
  const userId         = req.auth.sub;
  const { conversationId } = req.params;
  const { text } = req.body;

  if (!text?.trim()) return res.status(400).json({ error: "Empty message" });

  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: { workerId: true, employerId: true, status: true },
  });

  if (!conv) return res.status(404).json({ error: "Conversation not found" });

  if (conv.workerId !== userId && conv.employerId !== userId) {
    return res.status(403).json({ error: "Not a participant" });
  }

  if (conv.status !== "active") {
    return res.status(409).json({ error: "Conversation is closed" });
  }

  const message = await prisma.message.create({
    data: {
      conversationId,
      senderId: userId,
      text:     text.trim(),
      isSystem: false,
      isRead:   false,
    },
  });

  // updatedAt der Conversation aktualisieren
  await prisma.conversation.update({
    where: { id: conversationId },
    data: { updatedAt: new Date() },
  });

  return res.json({
    id:            message.id,
    text:          message.text,
    isFromUser:    true,
    timestamp:     message.createdAt,
    isSystemMessage: false,
  });
});

// ─── GET /messages/:conversationId ──────────────────────────────────────────
// Gibt einzelne Nachrichten zurück. ?since=<ISO8601> liefert nur neue Nachrichten.
router.get("/:conversationId", requireAuth, async (req, res) => {
  try {
    const userId             = req.auth.sub;
    const { conversationId } = req.params;
    const { since }          = req.query;

    const conv = await prisma.conversation.findUnique({
      where:  { id: conversationId },
      select: { workerId: true, employerId: true },
    });

    if (!conv) return res.status(404).json({ error: "Conversation not found" });
    if (conv.workerId !== userId && conv.employerId !== userId) {
      return res.status(403).json({ error: "Not a participant" });
    }

    const messages = await prisma.message.findMany({
      where: {
        conversationId,
        ...(since ? { createdAt: { gt: new Date(since) } } : {}),
      },
      orderBy: { createdAt: "asc" },
    });

    return res.json({
      messages: messages.map(m => ({
        id:              m.id,
        text:            m.text,
        isFromUser:      m.senderId === userId,
        timestamp:       m.createdAt,
        isSystemMessage: m.isSystem,
      })),
    });
  } catch (err) {
    console.error("GET /messages/:conversationId error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─── PATCH /messages/:conversationId/read ────────────────────────────────────
// Alle ungelesenen Nachrichten einer Konversation als gelesen markieren
router.patch("/:conversationId/read", requireAuth, async (req, res) => {
  const userId         = req.auth.sub;
  const { conversationId } = req.params;

  const conv = await prisma.conversation.findUnique({
    where: { id: conversationId },
    select: { workerId: true, employerId: true },
  });

  if (!conv) return res.status(404).json({ error: "Conversation not found" });
  if (conv.workerId !== userId && conv.employerId !== userId) {
    return res.status(403).json({ error: "Not a participant" });
  }

  // Nur Nachrichten vom anderen markieren
  await prisma.message.updateMany({
    where: {
      conversationId,
      senderId: { not: userId },
      isRead: false,
    },
    data: { isRead: true },
  });

  return res.json({ ok: true });
});

module.exports = router;
