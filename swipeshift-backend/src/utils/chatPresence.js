// src/utils/chatPresence.js
// Reine, DB-freie Helper fuer Chat-Presence (Typing, Online-Status, Lesebestaetigungen).
// Das Chat-System ist bewusst Polling-basiert (kein WebSocket) — "Echtzeit" ergibt sich
// aus kurzen Zeitfenstern, die der Client per Polling abfragt.

// Typing gilt als aktiv, wenn der letzte Typing-Ping juenger als dieses Fenster ist.
// Der Client pingt waehrend des Tippens hoechstens alle ~3 s.
const TYPING_WINDOW_MS = 6 * 1000;

// Online, wenn der User innerhalb dieses Fensters irgendeinen authentifizierten Request gemacht hat.
const ONLINE_WINDOW_MS = 2 * 60 * 1000;

// lastSeenAt wird hoechstens so oft in die DB geschrieben (Drosselung in requireAuth).
const LAST_SEEN_THROTTLE_MS = 30 * 1000;

function toTime(value) {
  if (!value) return null;
  const t = new Date(value).getTime();
  return Number.isNaN(t) ? null : t;
}

function isTyping(typingAt, now = new Date()) {
  const t = toTime(typingAt);
  if (t === null) return false;
  const diff = toTime(now) - t;
  return diff >= 0 && diff <= TYPING_WINDOW_MS;
}

function isOnline(lastSeenAt, now = new Date()) {
  const t = toTime(lastSeenAt);
  if (t === null) return false;
  return toTime(now) - t <= ONLINE_WINDOW_MS;
}

// Eine eigene Nachricht gilt als gelesen, wenn die Gegenseite die Konversation
// nach dem Sendezeitpunkt geoeffnet hat — oder das alte isRead-Flag gesetzt ist.
function isReadByOther(message, otherLastReadAt) {
  if (message.isRead) return true;
  const readAt = toTime(otherLastReadAt);
  const sentAt = toTime(message.createdAt);
  if (readAt === null || sentAt === null) return false;
  return readAt >= sentAt;
}

function shouldTouchLastSeen(lastTouchedAt, now = Date.now()) {
  if (lastTouchedAt == null) return true;
  return now - lastTouchedAt >= LAST_SEEN_THROTTLE_MS;
}

// Liefert die Feldnamen der eigenen bzw. gegnerischen Seite einer Konversation.
function participantFields(conv, userId) {
  const isWorker = conv.workerId === userId;
  return {
    isWorker,
    otherUserId: isWorker ? conv.employerId : conv.workerId,
    myReadField:     isWorker ? "workerLastReadAt"   : "employerLastReadAt",
    myTypingField:   isWorker ? "workerTypingAt"     : "employerTypingAt",
    otherReadField:  isWorker ? "employerLastReadAt" : "workerLastReadAt",
    otherTypingField: isWorker ? "employerTypingAt"  : "workerTypingAt",
  };
}

module.exports = {
  TYPING_WINDOW_MS,
  ONLINE_WINDOW_MS,
  LAST_SEEN_THROTTLE_MS,
  isTyping,
  isOnline,
  isReadByOther,
  shouldTouchLastSeen,
  participantFields,
};
