// src/routes.messages.js
const express = require("express");
const router  = express.Router();
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const {
  isTyping, isOnline, isReadByOther, participantFields,
} = require("./utils/chatPresence");

// Nachricht → iOS ChatMessageDTO. `otherLastReadAt` bestimmt die Lesebestaetigung
// fuer eigene Nachrichten (fremde Nachrichten haben kein Lese-Flag fuer uns).
function formatMessage(m, currentUserId, otherLastReadAt) {
  const isFromUser = m.senderId === currentUserId;
  return {
    id:              m.id,
    text:            m.text,
    isFromUser,
    timestamp:       m.createdAt,
    isSystemMessage: m.isSystem,
    isReadByOther:   isFromUser && !m.isSystem ? isReadByOther(m, otherLastReadAt) : false,
  };
}

// Setzt ein Presence-Zeitfeld OHNE @updatedAt zu veraendern (Prisma wuerde es sonst bei
// jedem Update anfassen und Typing-Pings/Lesen wuerden die Konversation "nach oben" schieben).
// Spaltenname kommt ausschliesslich aus participantFields() → Whitelist-Pruefung.
const PRESENCE_COLUMNS = new Set([
  "workerLastReadAt", "employerLastReadAt", "workerTypingAt", "employerTypingAt",
]);
async function setPresenceColumn(conversationId, column, value) {
  if (!PRESENCE_COLUMNS.has(column)) throw new Error(`Invalid presence column: ${column}`);
  await prisma.$executeRawUnsafe(
    `UPDATE "Conversation" SET "${column}" = $1 WHERE "id" = $2`,
    value,
    conversationId
  );
}

// Presence-Block der Gegenseite fuer die Chat-Ansicht
function formatPresence(conv, currentUserId, otherUser, now = new Date()) {
  const f = participantFields(conv, currentUserId);
  return {
    otherIsTyping:   isTyping(conv[f.otherTypingField], now),
    otherIsOnline:   isOnline(otherUser?.lastSeenAt, now),
    otherLastSeenAt: otherUser?.lastSeenAt ?? null,
    otherLastReadAt: conv[f.otherReadField] ?? null,
  };
}

// Faengt Fehler async Route-Handler ab. Express 4 behandelt abgelehnte Promises nicht —
// ohne Wrapper bekommt der Client keine Antwort und der Request haengt bis zum Timeout.
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
    messages:        conv.messages.map(m =>
      formatMessage(m, currentUserId, conv[participantFields(conv, currentUserId).otherReadField])
    ),
    presence:        formatPresence(conv, currentUserId, conv.otherUser),
  };
}

// ─── GET /messages ─────────────────────────────────────────────────────────
// Gibt alle Konversationen des eingeloggten Users zurück (worker oder employer)
router.get("/", requireAuth, handle("GET /messages", async (req, res) => {
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
      // Hinweis: Conversation hat KEINE worker-/employer-Relation (nur IDs). Namen und
      // lastSeenAt der Gegenseite werden unten separat ueber prisma.user nachgeladen.
      // Ein `include: { worker }` hier wirft PrismaClientValidationError.
    },
    orderBy: { updatedAt: "desc" },
  });

  // User-Daten der Gegenseite nachladen (Name fuer Employer-Sicht, lastSeenAt fuer Presence)
  const otherIds = [...new Set(
    conversations.map(c => (isWorker ? c.employerId : c.workerId)).filter(Boolean)
  )];
  const others = await prisma.user.findMany({
    where: { id: { in: otherIds } },
    select: { id: true, firstName: true, lastName: true, lastSeenAt: true },
  });
  const otherMap = Object.fromEntries(others.map(u => [u.id, u]));

  const result = conversations.map(conv => {
    const enriched = { ...conv };
    const otherId = isWorker ? conv.employerId : conv.workerId;
    enriched.otherUser = otherId ? (otherMap[otherId] ?? null) : null;
    if (!isWorker) {
      enriched.worker = enriched.otherUser;
    }
    return formatConversation(enriched, userId);
  });

  return res.json(result);
}));

// ─── POST /messages/:conversationId ─────────────────────────────────────────
// Nachricht senden
router.post("/:conversationId", requireAuth, handle("POST /messages/:conversationId", async (req, res) => {
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

  // updatedAt der Conversation aktualisieren + eigenen Typing-Status beenden
  const { myTypingField } = participantFields(conv, userId);
  await prisma.conversation.update({
    where: { id: conversationId },
    data: { updatedAt: new Date(), [myTypingField]: null },
  });

  return res.json(formatMessage(message, userId, null));
}));

// ─── GET /messages/:conversationId ──────────────────────────────────────────
// Gibt einzelne Nachrichten zurück. ?since=<ISO8601> liefert nur neue Nachrichten.
router.get("/:conversationId", requireAuth, async (req, res) => {
  try {
    const userId             = req.auth.sub;
    const { conversationId } = req.params;
    const { since }          = req.query;

    const conv = await prisma.conversation.findUnique({
      where:  { id: conversationId },
      select: {
        workerId: true, employerId: true,
        workerLastReadAt: true, employerLastReadAt: true,
        workerTypingAt: true, employerTypingAt: true,
      },
    });

    if (!conv) return res.status(404).json({ error: "Conversation not found" });
    if (conv.workerId !== userId && conv.employerId !== userId) {
      return res.status(403).json({ error: "Not a participant" });
    }

    const { otherUserId, otherReadField } = participantFields(conv, userId);
    const otherUser = otherUserId
      ? await prisma.user.findUnique({ where: { id: otherUserId }, select: { lastSeenAt: true } })
      : null;

    const messages = await prisma.message.findMany({
      where: {
        conversationId,
        ...(since ? { createdAt: { gt: new Date(since) } } : {}),
      },
      orderBy: { createdAt: "asc" },
    });

    return res.json({
      messages: messages.map(m => formatMessage(m, userId, conv[otherReadField])),
      presence: formatPresence(conv, userId, otherUser),
    });
  } catch (err) {
    console.error("GET /messages/:conversationId error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// ─── PATCH /messages/:conversationId/read ────────────────────────────────────
// Alle ungelesenen Nachrichten einer Konversation als gelesen markieren
router.patch("/:conversationId/read", requireAuth, handle("PATCH /messages/:conversationId/read", async (req, res) => {
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

  // Pro-Teilnehmer-Lesezeitpunkt fuer Lesebestaetigungen der Gegenseite
  const { myReadField } = participantFields(conv, userId);
  await setPresenceColumn(conversationId, myReadField, new Date());

  return res.json({ ok: true });
}));

// ─── POST /messages/:conversationId/typing ───────────────────────────────────
// Body: { isTyping: boolean }. Client pingt waehrend des Tippens (gedrosselt);
// der Status laeuft nach TYPING_WINDOW_MS automatisch ab.
router.post("/:conversationId/typing", requireAuth, async (req, res) => {
  try {
    const userId             = req.auth.sub;
    const { conversationId } = req.params;
    const typing             = req.body?.isTyping !== false;

    const conv = await prisma.conversation.findUnique({
      where:  { id: conversationId },
      select: { workerId: true, employerId: true, status: true },
    });

    if (!conv) return res.status(404).json({ error: "Conversation not found" });
    if (conv.workerId !== userId && conv.employerId !== userId) {
      return res.status(403).json({ error: "Not a participant" });
    }
    if (conv.status !== "active") {
      return res.status(409).json({ error: "Conversation is closed" });
    }

    const { myTypingField } = participantFields(conv, userId);
    await setPresenceColumn(conversationId, myTypingField, typing ? new Date() : null);

    return res.json({ ok: true });
  } catch (err) {
    console.error("POST /messages/:conversationId/typing error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
