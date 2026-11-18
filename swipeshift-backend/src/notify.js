// src/notify.js
// Dispatcher fuer Benachrichtigungen (Push + E-Mail) nach den Einstellungen des Empfaengers.
//
//   notify(userId, { category, push?: {title, body, data}, email?: {subject, html, text} })
//   event.pausedOk: true → wird auch an pausierte Konten zugestellt (nur "Konto pausiert/fortgesetzt")
//   notify(userId, (user) => event)   // wenn der Text von Nutzerdaten (z.B. Zeitzone) abhaengt
//
// Fire-and-forget: das Promise wird NIE abgelehnt (Fehler werden geloggt) → an Aufrufstellen nicht awaiten.
// Sicherheits-Mails (Passwort, 2FA, neues Geraet, Backup-Codes) laufen bewusst NICHT hier durch.

const { shouldDeliver } = require("./utils/notifyPolicy");

function createNotifier({ loadUser, loadDevices, sendMail, sendPush, log = console, now = () => new Date() }) {
  return async function notify(userId, eventOrBuilder) {
    try {
      if (!userId) return { email: false, push: false };
      const user = await loadUser(userId);
      if (!user) return { email: false, push: false };
      const event = typeof eventOrBuilder === "function" ? eventOrBuilder(user) : eventOrBuilder;
      if (!event || !event.category) return { email: false, push: false };

      const at = now();
      const result = { email: false, push: false };

      if (event.email && shouldDeliver(user, event.category, "email", at, { pausedOk: event.pausedOk })) {
        try {
          await sendMail({ to: user.email, subject: event.email.subject, html: event.email.html, text: event.email.text });
          result.email = true;
        } catch (err) {
          log.error(`notify: email failed (${event.category}):`, err);
        }
      }

      if (event.push && shouldDeliver(user, event.category, "push", at, { pausedOk: event.pausedOk })) {
        try {
          const devices = await loadDevices(userId, at);
          if (devices.length > 0) {
            await sendPush(devices, { ...event.push, data: { ...event.push.data, userId } }); // userId: App verwirft Taps fremder Konten
            result.push = true;
          }
        } catch (err) {
          log.error(`notify: push failed (${event.category}):`, err);
        }
      }
      return result;
    } catch (err) {
      log.error("notify failed:", err);
      return { email: false, push: false, error: true };
    }
  };
}

// Produktiv-Instanz (Lazy-Requires: Prisma/Mailer erst bei Gebrauch laden)
const notify = createNotifier({
  loadUser: (id) => require("./prisma.js").prisma.user.findUnique({
    where: { id },
    select: { id: true, email: true, emailVerifiedAt: true, settings: true, timeZone: true, pausedAt: true, role: true },
  }),
  loadDevices: (id, at) => require("./pushDevices").loadLiveDevices(id, at),
  sendMail: (m) => require("./mailer").sendMail(m),
  sendPush: (devices, msg) => require("./push").sendPush(devices, msg),
});

module.exports = { createNotifier, notify };
