// Ungelesen-Zaehler fuer die Glocke. Benachrichtigungen sind dynamisch (kein DB-Model):
// ungelesen = Zeitstempel > notificationsSeenAt. Ohne seenAt (nie geoeffnet) zaehlen nur die letzten 7 Tage.
const DEFAULT_WINDOW_MS = 7 * 24 * 3_600_000;

function countUnread(notifications, seenAt, now = new Date(), windowMs = DEFAULT_WINDOW_MS) {
  if (!Array.isArray(notifications)) return 0;
  const seen = seenAt ? new Date(seenAt).getTime() : null;
  const floor = seen != null && !Number.isNaN(seen) ? seen : new Date(now).getTime() - windowMs;
  return notifications.filter((n) => {
    const t = new Date(n?.timestamp).getTime();
    return !Number.isNaN(t) && t > floor;
  }).length;
}

module.exports = { countUnread, DEFAULT_WINDOW_MS };
