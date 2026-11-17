// src/utils/consents.js
// Rechtliche Zustimmungen: User.legalConsents ist eine Map  Key -> ISO-Zeitstempel.
// Widerruf = Key entfernen (ausser `terms`: nicht widerrufbar). Nur Whitelist-Keys werden akzeptiert.

const WORKER_CONSENT_KEYS = ["terms", "ratingSystem"];
const EMPLOYER_CONSENT_KEYS = ["terms", "ratingSystem", "paymentResponsibility", "accurateJobInfo", "legalHiring"];

function allowedKeysForRole(role) {
  if (role === "worker") return WORKER_CONSENT_KEYS;
  if (role === "employer") return EMPLOYER_CONSENT_KEYS;
  return [];
}

/**
 * Wendet ein Update `{ key: Bool }` auf die bestehende Map an.
 * true  -> Zeitstempel setzen, falls noch nicht vorhanden (bleibt sonst erhalten)
 * false -> Key entfernen
 * Unbekannte/nicht erlaubte Keys und Nicht-Booleans werden ignoriert.
 * Gibt immer eine neue Map zurück (Eingabe wird nicht verändert).
 */
function mergeConsents(existing, updates, allowedKeys, now = new Date()) {
  const result = {};
  if (existing && typeof existing === "object" && !Array.isArray(existing)) {
    for (const [k, v] of Object.entries(existing)) {
      if (typeof v === "string") result[k] = v;
    }
  }
  if (!updates || typeof updates !== "object" || Array.isArray(updates)) return result;
  for (const key of allowedKeys) {
    const value = updates[key];
    if (value === true) {
      if (!result[key]) result[key] = now.toISOString();
    } else if (value === false) {
      // AGB sind nicht widerrufbar (Nachweis bleibt); alle anderen Zustimmungen schon
      if (key !== "terms") delete result[key];
    }
  }
  return result;
}

/** Für den Client: Map Key -> Bool über alle bekannten Keys. */
function consentsToFlags(stored) {
  const flags = {};
  for (const key of EMPLOYER_CONSENT_KEYS) {
    flags[key] = !!(stored && typeof stored === "object" && stored[key]);
  }
  return flags;
}

module.exports = { WORKER_CONSENT_KEYS, EMPLOYER_CONSENT_KEYS, allowedKeysForRole, mergeConsents, consentsToFlags };
