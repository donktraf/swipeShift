// src/utils/notifySchedule.js
// Reine, DB-freie Auswahllogik fuer den Scheduler (Schicht-Erinnerung, Ungelesen-Mails, Payment open).

const MIN = 60 * 1000;
const HOUR = 60 * MIN;

const UNREAD_EMAIL_DELAY_MS = 15 * MIN;       // Mail erst, wenn die Nachricht so lange ungelesen ist
const UNREAD_EMAIL_MAX_AGE_MS = 24 * HOUR;    // aeltere ungelesene Nachrichten loesen keine Mail mehr aus
const EMAIL_COOLDOWN_MS = HOUR;               // max. 1 Mail pro Konversation und Empfaenger und Stunde
const REMINDER_WINDOW_FROM_MS = 0;            // Erinnerung, wenn der Start 0–24 h entfernt ist (einmal pro Bewerbung → auch spaete Zusagen)
const REMINDER_WINDOW_TO_MS = 24 * HOUR;
const PAYMENT_OPEN_LOOKBACK_MS = 7 * 24 * HOUR; // nur Jobs, die in den letzten 7 Tagen endeten

const t = (v) => (v ? new Date(v).getTime() : null);

// startTime-Fenster (Date) fuer Schicht-Erinnerungen
function shiftReminderWindow(now = new Date()) {
  const n = new Date(now).getTime();
  return { from: new Date(n + REMINDER_WINDOW_FROM_MS), to: new Date(n + REMINDER_WINDOW_TO_MS) };
}

// Ende-Fenster fuer "Payment open": Job vorbei, aber nicht aelter als 7 Tage
function paymentOpenWindow(now = new Date()) {
  const n = new Date(now).getTime();
  return { endedAfter: new Date(n - PAYMENT_OPEN_LOOKBACK_MS), endedBefore: new Date(n) };
}

// Ziele fuer Ungelesen-Mails. messages: Message-Zeilen mit conversation (inkl. job.title und Lese-/Mail-Zeitstempeln).
// → [{ conversationId, recipientId, recipientRole, senderId, jobTitle, unreadCount }] (eine Zeile pro Konversation+Empfaenger)
function pickUnreadMessageEmailTargets(messages, now = new Date()) {
  const n = new Date(now).getTime();
  const groups = new Map();
  for (const m of messages ?? []) {
    const conv = m.conversation;
    if (!conv || m.isSystem || m.isRead) continue;
    const created = t(m.createdAt);
    if (created === null) continue;
    const age = n - created;
    if (age < UNREAD_EMAIL_DELAY_MS || age > UNREAD_EMAIL_MAX_AGE_MS) continue;

    let recipientId, recipientRole, readAt, lastEmail;
    if (m.senderId === conv.workerId) {
      recipientId = conv.employerId; recipientRole = "employer";
      readAt = t(conv.employerLastReadAt); lastEmail = t(conv.employerEmailNotifiedAt);
    } else if (m.senderId === conv.employerId) {
      recipientId = conv.workerId; recipientRole = "worker";
      readAt = t(conv.workerLastReadAt); lastEmail = t(conv.workerEmailNotifiedAt);
    } else continue;
    if (!recipientId) continue;
    if (readAt !== null && created <= readAt) continue;                 // inzwischen gelesen
    if (lastEmail !== null && n - lastEmail < EMAIL_COOLDOWN_MS) continue; // Cooldown
    if (lastEmail !== null && created <= lastEmail) continue;            // fuer diese Nachricht schon gemailt

    const key = `${conv.id}:${recipientId}`;
    const g = groups.get(key);
    if (g) g.unreadCount += 1;
    else groups.set(key, {
      conversationId: conv.id, recipientId, recipientRole, senderId: m.senderId,
      jobTitle: conv.job?.title ?? null, unreadCount: 1,
    });
  }
  return [...groups.values()];
}

module.exports = {
  UNREAD_EMAIL_DELAY_MS, UNREAD_EMAIL_MAX_AGE_MS, EMAIL_COOLDOWN_MS,
  shiftReminderWindow, paymentOpenWindow, pickUnreadMessageEmailTargets,
};
