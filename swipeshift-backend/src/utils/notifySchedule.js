// src/utils/notifySchedule.js
// Reine, DB-freie Auswahllogik fuer den Scheduler (Schicht-Erinnerung, Ungelesen-Mails, Payment open).

const MIN = 60 * 1000;
const HOUR = 60 * MIN;

const UNREAD_EMAIL_DELAY_MS = 15 * MIN;       // Mail erst, wenn die Nachricht so lange ungelesen ist
const UNREAD_EMAIL_MAX_AGE_MS = 24 * HOUR;    // aeltere ungelesene Nachrichten loesen keine Mail mehr aus
const EMAIL_COOLDOWN_MS = HOUR;               // max. 1 Mail pro Konversation und Empfaenger und Stunde
const REMINDER_WINDOW_FROM_MS = 0;            // aeusserstes Fenster aller Schicht-Erinnerungen: Start 0–24 h entfernt
const REMINDER_WINDOW_TO_MS = 24 * HOUR;
const REMINDER_2H_MS = 2 * HOUR;
const PAYMENT_OPEN_LOOKBACK_MS = 7 * 24 * HOUR; // nur Jobs, die in den letzten 7 Tagen endeten

const { bookedShifts } = require("./shiftBooking");

const t = (v) => (v ? new Date(v).getTime() : null);

// startTime-Fenster (Date) fuer Schicht-Erinnerungen
function shiftReminderWindow(now = new Date()) {
  const n = new Date(now).getTime();
  return { from: new Date(n + REMINDER_WINDOW_FROM_MS), to: new Date(n + REMINDER_WINDOW_TO_MS) };
}

// Faellige Schicht-Erinnerungen einer angenommenen Bewerbung (rein, DB-frei).
//   "24h" faellig, wenn Start - jetzt in (2h, 24h]; "2h" faellig, wenn Start - jetzt in (0, 2h]. Begonnene Schichten: nie.
//   Spaet Angenommene bekommen nur das, was noch in der Zukunft liegt (1 h vorher → nur "2h").
//   sent: [{ shiftId, kind }] bereits verschickt (ShiftReminder) → uebersprungen.
//   legacyReminderSentAt: Apply.reminderSentAt (Altbestand, eine Erinnerung je Bewerbung). Wurde sie innerhalb der 24 h
//   vor dieser Schicht verschickt, gilt sie als der 24h-Reminder dieser Schicht → kein Duplikat ("2h" kommt trotzdem).
// → [{ shiftId, kind, startMs, timeRange }] sortiert nach Start, "24h" vor "2h"
function dueShiftReminders({ job, shiftIds, sent = [], legacyReminderSentAt = null, now = new Date() }) {
  const n = new Date(now).getTime();
  const legacy = t(legacyReminderSentAt);
  const done = new Set((sent ?? []).map((r) => `${r.shiftId}:${r.kind}`));
  const out = [];
  for (const sh of bookedShifts(job, shiftIds)) {
    if (sh.startMs === null) continue;
    const until = sh.startMs - n;
    if (until <= 0 || until > REMINDER_WINDOW_TO_MS) continue;
    const kind = until <= REMINDER_2H_MS ? "2h" : "24h";
    if (kind === "24h" && legacy !== null && legacy >= sh.startMs - REMINDER_WINDOW_TO_MS && legacy <= sh.startMs) continue;
    if (done.has(`${sh.id}:${kind}`)) continue;
    out.push({ shiftId: sh.id, kind, startMs: sh.startMs, timeRange: sh.timeRange });
  }
  return out.sort((a, b) => a.startMs - b.startMs);
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
  shiftReminderWindow, dueShiftReminders, paymentOpenWindow, pickUnreadMessageEmailTargets,
};
