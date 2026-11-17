// src/utils/settings.js
// Reine, DB-freie Logik fuer User.settings (JSON): Standardwerte, Validierung,
// Zusammenfuehren mit Aenderungen und sichere Ausgabe (IBAN maskiert).
//
// Form:
// {
//   notifications: { jobActivity: {push, email}, payments: {...}, messages: {...}, account: {...} },
//   quietHours:    { enabled, from: "HH:MM", to: "HH:MM" },
//   payout:        { method: "bank"|"paypal", iban, paypalEmail, frequency: "instant"|"weekly"|"monthly" }
// }

const { z } = require("zod");

const NOTIFICATION_CATEGORIES = ["jobActivity", "payments", "messages", "account"];

const DEFAULT_SETTINGS = Object.freeze({
  notifications: {
    jobActivity: { push: true, email: true },
    payments:    { push: true, email: false },
    messages:    { push: true, email: false },
    account:     { push: false, email: true },
  },
  quietHours: { enabled: false, from: "22:00", to: "07:00" },
  payout: { method: "bank", iban: null, paypalEmail: null, frequency: "weekly" },
});

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM");
const channel = z.object({ push: z.boolean(), email: z.boolean() }).partial();

// IBAN: Leerzeichen raus, Grossbuchstaben, 15–34 Zeichen, Laendercode + Pruefziffern
function normalizeIban(value) {
  return String(value).replace(/\s+/g, "").toUpperCase();
}
function isValidIban(value) {
  const iban = normalizeIban(value);
  if (!/^[A-Z]{2}\d{2}[A-Z0-9]{11,30}$/.test(iban)) return false;
  // Mod-97-Pruefung (ISO 13616)
  const rearranged = iban.slice(4) + iban.slice(0, 4);
  const digits = rearranged.replace(/[A-Z]/g, (c) => String(c.charCodeAt(0) - 55));
  let rest = 0;
  for (const ch of digits) rest = (rest * 10 + Number(ch)) % 97;
  return rest === 1;
}

const patchSchema = z.object({
  notifications: z.object(Object.fromEntries(NOTIFICATION_CATEGORIES.map((c) => [c, channel]))).partial().optional(),
  quietHours: z.object({ enabled: z.boolean(), from: time, to: time }).partial().optional(),
  payout: z.object({
    method: z.enum(["bank", "paypal"]),
    // null = loeschen, weglassen = unveraendert
    iban: z.string().max(40).nullable().refine((v) => v === null || v.trim() === "" || isValidIban(v), "Invalid IBAN"),
    paypalEmail: z.string().max(254).nullable().refine((v) => v === null || v.trim() === "" || z.string().email().safeParse(v.trim()).success, "Invalid email"),
    frequency: z.enum(["instant", "weekly", "monthly"]),
  }).partial().optional(),
}).strict();

function clone(obj) {
  return JSON.parse(JSON.stringify(obj));
}

// Gespeichertes JSON (evtl. alt/unvollstaendig) mit Standardwerten auffuellen
function withDefaults(stored) {
  const out = clone(DEFAULT_SETTINGS);
  const s = stored && typeof stored === "object" ? stored : {};
  for (const cat of NOTIFICATION_CATEGORIES) {
    const v = s.notifications?.[cat];
    if (v && typeof v === "object") {
      if (typeof v.push === "boolean") out.notifications[cat].push = v.push;
      if (typeof v.email === "boolean") out.notifications[cat].email = v.email;
    }
  }
  if (s.quietHours && typeof s.quietHours === "object") {
    if (typeof s.quietHours.enabled === "boolean") out.quietHours.enabled = s.quietHours.enabled;
    if (time.safeParse(s.quietHours.from).success) out.quietHours.from = s.quietHours.from;
    if (time.safeParse(s.quietHours.to).success) out.quietHours.to = s.quietHours.to;
  }
  if (s.payout && typeof s.payout === "object") {
    if (["bank", "paypal"].includes(s.payout.method)) out.payout.method = s.payout.method;
    if (typeof s.payout.iban === "string" && s.payout.iban) out.payout.iban = s.payout.iban;
    if (typeof s.payout.paypalEmail === "string" && s.payout.paypalEmail) out.payout.paypalEmail = s.payout.paypalEmail;
    if (["instant", "weekly", "monthly"].includes(s.payout.frequency)) out.payout.frequency = s.payout.frequency;
  }
  return out;
}

// Aenderung validieren und auf die gespeicherten Settings anwenden.
// Rueckgabe: { settings } oder { error }
function applyPatch(stored, patch) {
  const parsed = patchSchema.safeParse(patch ?? {});
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return { error: issue ? `${issue.path.join(".") || "settings"}: ${issue.message}` : "Invalid settings" };
  }
  const p = parsed.data;
  const next = withDefaults(stored);

  for (const cat of NOTIFICATION_CATEGORIES) {
    const v = p.notifications?.[cat];
    if (v) Object.assign(next.notifications[cat], v);
  }
  if (p.quietHours) Object.assign(next.quietHours, p.quietHours);
  if (p.payout) {
    if (p.payout.method !== undefined) next.payout.method = p.payout.method;
    if (p.payout.frequency !== undefined) next.payout.frequency = p.payout.frequency;
    if (p.payout.iban !== undefined) {
      next.payout.iban = p.payout.iban && p.payout.iban.trim() ? normalizeIban(p.payout.iban) : null;
    }
    if (p.payout.paypalEmail !== undefined) {
      next.payout.paypalEmail = p.payout.paypalEmail && p.payout.paypalEmail.trim()
        ? p.payout.paypalEmail.trim().toLowerCase() : null;
    }
  }
  return { settings: next };
}

// Fuer die App: IBAN nie komplett zurueckgeben
function maskIban(iban) {
  if (!iban) return null;
  const clean = normalizeIban(iban);
  return `${clean.slice(0, 2)}•• •••• ${clean.slice(-4)}`;
}

function publicSettings(stored) {
  const s = withDefaults(stored);
  const { iban, ...payout } = s.payout;
  return {
    ...s,
    payout: { ...payout, hasIban: !!iban, ibanMasked: maskIban(iban) },
  };
}

module.exports = {
  NOTIFICATION_CATEGORIES,
  DEFAULT_SETTINGS,
  isValidIban,
  withDefaults,
  applyPatch,
  maskIban,
  publicSettings,
};
