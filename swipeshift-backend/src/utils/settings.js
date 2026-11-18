// src/utils/settings.js
// Reine, DB-freie Logik fuer User.settings (JSON): Standardwerte, Validierung,
// Zusammenfuehren mit Aenderungen und sichere Ausgabe (Kontonummer nie im Klartext).
//
// Form:
// {
//   notifications: { jobActivity: {push, email}, payments: {...}, messages: {...}, account: {...} },
//   quietHours:    { enabled, from: "HH:MM", to: "HH:MM" },
//   payout:        { method: "bank"|"paypal", bank, paypalEmail, frequency: "instant"|"weekly"|"monthly" }
//   payout.bank:   null | { accountHolderName, routingNumber, accountType, accountEnc (verschluesselt), accountLast4 }
// }

const { z } = require("zod");
const bankDetails = require("./bankDetails");

const NOTIFICATION_CATEGORIES = ["jobActivity", "payments", "messages", "account"];

const DEFAULT_SETTINGS = Object.freeze({
  notifications: {
    jobActivity: { push: true, email: true },
    payments:    { push: true, email: false },
    messages:    { push: true, email: false },
    account:     { push: false, email: true },
  },
  quietHours: { enabled: false, from: "22:00", to: "07:00" },
  payout: { method: "bank", bank: null, paypalEmail: null, frequency: "weekly" },
});

const time = z.string().regex(/^([01]\d|2[0-3]):[0-5]\d$/, "Use HH:MM");
const channel = z.object({ push: z.boolean(), email: z.boolean() }).partial();

const patchSchema = z.object({
  notifications: z.object(Object.fromEntries(NOTIFICATION_CATEGORIES.map((c) => [c, channel]))).partial().optional(),
  quietHours: z.object({ enabled: z.boolean(), from: time, to: time }).partial().optional(),
  payout: z.object({
    method: z.enum(["bank", "paypal"]),
    // null = loeschen, weglassen = unveraendert; Teil-Objekt: nur die gesendeten Felder aendern
    bank: z.object({
      accountHolderName: z.string().max(200).refine(bankDetails.isValidHolderName, "Invalid account holder name"),
      routingNumber: z.string().max(30).refine(bankDetails.isValidRoutingNumber, "Invalid routing number"),
      accountNumber: z.string().max(40).refine(bankDetails.isValidAccountNumber, "Invalid account number"),
      accountType: z.enum(bankDetails.ACCOUNT_TYPES),
    }).partial().strict().nullable(),
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
    // Alte IBAN (s.payout.iban) wird bewusst ignoriert → beim naechsten Schreiben entfernt
    out.payout.bank = bankDetails.sanitizeStoredBank(s.payout.bank);
    if (typeof s.payout.paypalEmail === "string" && s.payout.paypalEmail) out.payout.paypalEmail = s.payout.paypalEmail;
    if (["instant", "weekly", "monthly"].includes(s.payout.frequency)) out.payout.frequency = s.payout.frequency;
  }
  return out;
}

// Aenderung validieren und auf die gespeicherten Settings anwenden.
// ctx = { userId, keyring? } — noetig, wenn eine Kontonummer gesendet wird (Verschluesselung).
// Rueckgabe: { settings, payoutDetailsChanged } oder { error }
function applyPatch(stored, patch, ctx = {}) {
  const parsed = patchSchema.safeParse(patch ?? {});
  if (!parsed.success) {
    const issue = parsed.error.issues[0];
    return { error: issue ? `${issue.path.join(".") || "settings"}: ${issue.message}` : "Invalid settings" };
  }
  const p = parsed.data;
  const next = withDefaults(stored);
  const before = clone(next.payout);
  let accountNumberChanged = false;

  for (const cat of NOTIFICATION_CATEGORIES) {
    const v = p.notifications?.[cat];
    if (v) Object.assign(next.notifications[cat], v);
  }
  if (p.quietHours) Object.assign(next.quietHours, p.quietHours);
  if (p.payout) {
    if (p.payout.method !== undefined) next.payout.method = p.payout.method;
    if (p.payout.frequency !== undefined) next.payout.frequency = p.payout.frequency;
    if (p.payout.bank !== undefined) {
      if (p.payout.bank === null) {
        next.payout.bank = null;
      } else {
        const r = mergeBank(next.payout.bank, p.payout.bank, ctx);
        if (r.error) return { error: r.error };
        next.payout.bank = r.bank;
        accountNumberChanged = r.accountNumberChanged;
      }
    }
    if (p.payout.paypalEmail !== undefined) {
      next.payout.paypalEmail = p.payout.paypalEmail && p.payout.paypalEmail.trim()
        ? p.payout.paypalEmail.trim().toLowerCase() : null;
    }
  }
  const bankChanged = accountNumberChanged
    || JSON.stringify(withoutEnc(before.bank)) !== JSON.stringify(withoutEnc(next.payout.bank));
  const paypalChanged = before.paypalEmail !== next.payout.paypalEmail;
  const methodChanged = before.method !== next.payout.method;
  // Haeufigkeit allein loest keine Sicherheitsmail aus
  const payoutDetailsChanged = bankChanged || paypalChanged || methodChanged;
  return { settings: next, payoutDetailsChanged, payoutChanges: { bank: bankChanged, paypal: paypalChanged, method: methodChanged } };
}

function withoutEnc(bank) {
  if (!bank) return null;
  const { accountEnc, ...rest } = bank;
  return rest;
}

// Teil-Aenderung der Bankdaten auf bestehende anwenden; Ergebnis muss vollstaendig sein
function mergeBank(existing, patch, ctx) {
  const next = { ...(existing || {}) };
  let accountNumberChanged = false;
  if (patch.accountHolderName !== undefined) next.accountHolderName = patch.accountHolderName.trim();
  if (patch.routingNumber !== undefined) next.routingNumber = bankDetails.normalizeDigits(patch.routingNumber);
  if (patch.accountType !== undefined) next.accountType = patch.accountType;
  if (patch.accountNumber !== undefined) {
    if (!ctx.userId) throw new Error("applyPatch: ctx.userId is required to store an account number");
    const digits = bankDetails.normalizeDigits(patch.accountNumber);
    let same = false;
    if (existing?.accountEnc) {
      try {
        same = bankDetails.decryptAccountNumber(existing.accountEnc, ctx.userId, ctx.keyring) === digits;
      } catch {
        // Nie Payload/Klartext loggen
        console.warn(`[settings] could not decrypt stored bank account number for userId=${ctx.userId}`);
        same = false;
      }
    }
    if (!same) {
      next.accountEnc = bankDetails.encryptAccountNumber(digits, ctx.userId, ctx.keyring);
      next.accountLast4 = digits.slice(-4);
      accountNumberChanged = true;
    }
  }
  for (const f of ["accountHolderName", "routingNumber", "accountType", "accountEnc"]) {
    if (!next[f]) return { error: `payout.bank.${f === "accountEnc" ? "accountNumber" : f}: Required` };
  }
  return { bank: bankDetails.sanitizeStoredBank(next), accountNumberChanged };
}

// Fuer die App: Kontonummer nie zurueckgeben, nur die letzten 4 Ziffern
function publicSettings(stored) {
  const s = withDefaults(stored);
  return { ...s, payout: { ...s.payout, bank: bankDetails.publicBank(s.payout.bank) } };
}

module.exports = {
  NOTIFICATION_CATEGORIES,
  DEFAULT_SETTINGS,
  withDefaults,
  applyPatch,
  publicSettings,
};
