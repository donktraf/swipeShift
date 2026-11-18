// src/utils/notifyPolicy.js
// Reine, DB-freie Entscheidungslogik fuer Benachrichtigungen: Zeitzone, Ruhezeiten, Kanal-Freigabe.

const { withDefaults, NOTIFICATION_CATEGORIES } = require("./settings");

// Gueltige IANA-Zeitzone (per Intl geprueft) → Name, sonst null. Auch Header-Werte mit Muell/zu lang → null.
function sanitizeTimeZone(value) {
  if (typeof value !== "string") return null;
  const v = value.trim();
  if (!v || v.length > 64 || !/^[A-Za-z0-9_+\-/]+$/.test(v)) return null;
  try {
    new Intl.DateTimeFormat("en-US", { timeZone: v });
    return v;
  } catch {
    return null;
  }
}

function toMinutes(hhmm) {
  const m = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(String(hhmm));
  return m ? Number(m[1]) * 60 + Number(m[2]) : null;
}

// Minuten seit Mitternacht in der Zeitzone (null bei ungueltiger Zone)
function minutesOfDay(now, timeZone) {
  try {
    const parts = new Intl.DateTimeFormat("en-GB", { timeZone, hour: "2-digit", minute: "2-digit", hourCycle: "h23" })
      .formatToParts(new Date(now));
    const h = Number(parts.find((p) => p.type === "hour").value);
    const m = Number(parts.find((p) => p.type === "minute").value);
    return h * 60 + m;
  } catch {
    return null;
  }
}

// quietHours: { enabled, from, to } ("HH:MM", Ortszeit). Ueber Mitternacht moeglich (22:00–07:00).
// Intervall ist [from, to): from == to → leer (nie ruhig). Unbekannte/ungueltige Zone → false.
function isWithinQuietHours(quietHours, timeZone, now = new Date()) {
  if (!quietHours || quietHours.enabled !== true) return false;
  const zone = sanitizeTimeZone(timeZone);
  if (!zone) return false;
  const from = toMinutes(quietHours.from);
  const to = toMinutes(quietHours.to);
  if (from === null || to === null || from === to) return false;
  const cur = minutesOfDay(now, zone);
  if (cur === null) return false;
  return from < to ? cur >= from && cur < to : cur >= from || cur < to;
}

// Entscheidet pro Kanal. user: { settings, timeZone, pausedAt, emailVerifiedAt, email }
//  - Kategorie unbekannt → nichts
//  - pausiertes Konto: nichts — ausser Ereignisse mit opts.pausedOk (nur Konto pausiert/fortgesetzt)
//  - email: Einstellung + verifizierte Adresse; Ruhezeiten gelten NICHT
//  - push: Einstellung + nicht in Ruhezeit
function shouldDeliver(user, category, channel, now = new Date(), opts = {}) {
  if (!NOTIFICATION_CATEGORIES.includes(category)) return false;
  if (channel !== "push" && channel !== "email") return false;
  if (!user) return false;
  if (user.pausedAt && opts.pausedOk !== true) return false;
  const settings = withDefaults(user.settings);
  if (settings.notifications[category][channel] !== true) return false;
  if (channel === "email") return !!user.emailVerifiedAt && !!user.email;
  return !isWithinQuietHours(settings.quietHours, user.timeZone, now);
}

module.exports = { sanitizeTimeZone, isWithinQuietHours, shouldDeliver };
