// src/utils/emailCanonical.js
// Kanonische E-Mail fuer den Ban-Evasion-Check (rein, DB-frei). Nur zum VERGLEICH — die Login-E-Mail bleibt unveraendert.
//   - lowercase + trim
//   - "+tag" im Local-Part entfernen (alle Domains)
//   - gmail.com / googlemail.com: zusaetzlich Punkte im Local-Part entfernen, googlemail.com -> gmail.com
// Gegenstueck in SQL: Backfill in prisma/migrations/20261121000000_shift_booking_email_canonical.

const { normalizeEmail } = require("./socialLogin");

const GMAIL_DOMAINS = new Set(["gmail.com", "googlemail.com"]);

function canonicalEmail(value) {
  const email = normalizeEmail(value);
  const at = email.lastIndexOf("@");
  if (at < 1 || at === email.length - 1) return email; // keine gueltige Adresse → nur normalisiert
  let local = email.slice(0, at);
  let domain = email.slice(at + 1);

  const plain = local.split("+")[0];
  if (plain) local = plain; // "+x@…" (leerer Rest) bleibt unveraendert

  if (GMAIL_DOMAINS.has(domain)) {
    domain = "gmail.com";
    const noDots = local.replace(/\./g, "");
    if (noDots) local = noDots;
  }
  return `${local}@${domain}`;
}

module.exports = { canonicalEmail };
