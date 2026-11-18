// src/utils/payoutMail.js
// Sicherheitsmail bei geaenderten Auszahlungsdaten. Reine Funktion; nennt nur sichere Angaben
// (letzte 4 Ziffern, Methode) — nie Kontonummer, Routing Number oder PayPal-Adresse. Alle Werte escaped.

const { escapeHtml, plainLine } = require("./emailTemplate");

const SUPPORT = "support@swipeshift.app";

// settings = gespeicherte (neue) Settings nach withDefaults; changes = payoutChanges aus applyPatch
function payoutChangeMail(settings, changes, now = new Date()) {
  const payout = settings.payout;
  const lines = [];
  if (changes.bank && payout.bank) lines.push(`Bank account ending ${payout.bank.accountLast4} was saved.`);
  else if (changes.bank) lines.push("Your bank account details were removed.");
  if (changes.paypal) lines.push(payout.paypalEmail ? "Your PayPal account was changed." : "Your PayPal account was removed.");
  if (changes.method) lines.push(`Payout method changed to ${payout.method === "paypal" ? "PayPal" : "bank account"}.`);
  const when = `${now.toISOString().slice(0, 16).replace("T", " ")} UTC`;
  const closing = `If this wasn't you, change your password and contact ${SUPPORT}`;
  const subject = "Your SwipeShift payout details were changed";
  const intro = "Your payout details were changed on your SwipeShift account.";
  const clean = lines.map((l) => plainLine(l, 200));
  const text = [intro, "", ...clean, `When: ${when}`, "", `${closing}.`].join("\n");
  const html = `<p>${escapeHtml(intro)}</p><ul>${clean.map((l) => `<li>${escapeHtml(l)}</li>`).join("")}</ul>`
    + `<p>${escapeHtml(`When: ${when}`)}</p><p>${escapeHtml(`${closing}.`)}</p>`;
  return { subject, text, html };
}

module.exports = { payoutChangeMail };
