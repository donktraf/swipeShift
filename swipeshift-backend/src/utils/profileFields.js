// src/utils/profileFields.js
// Reine, DB-freie Validierung/Normalisierung der Profil-Zusatzfelder
// (Worker: Tageszeiten, Schicht-Typen, Erfahrung; Employer: Gruendungsjahr, Slogan,
// Social-Links, Adresse, oeffentlicher Ansprechpartner).
//
// Konvention: jede Funktion liefert { value } oder { error } (lesbare Meldung fuer die App).

const AVAILABLE_TIMES = ["morning", "afternoon", "evening", "night"];

// Entscheidung: "lastMinute" ist KEIN Schicht-Typ-Chip. Der bestehende Schalter
// "Available for same-day jobs" (Worker.availableForSameDay) bleibt die einzige Quelle
// fuer Kurzfristigkeit, damit es keine doppelte/widerspruechliche Angabe gibt.
const SHIFT_TYPES = ["oneDay", "weekend", "eventBased"];

const CATEGORIES = [
  "Hospitality", "Events", "Logistics", "Retail",
  "Customer Service", "Warehouse", "Office", "Cleaning",
];
const EXPERIENCE_LEVELS = ["lt3m", "m3to12", "gt1y"];

const TAGLINE_MAX = 80;
const SOCIAL_KEYS = ["instagram", "linkedin", "facebook", "tiktok"];
const MIN_YEAR_FOUNDED = 1800;

// Whitelist-Liste (String[]); dedupliziert, Reihenfolge der Whitelist
function validateWhitelist(list, allowed, label) {
  if (list == null) return { value: [] };
  if (!Array.isArray(list)) return { error: `${label} must be a list.` };
  for (const item of list) {
    if (typeof item !== "string" || !allowed.includes(item)) {
      return { error: `Invalid ${label} value: ${String(item)}.` };
    }
  }
  return { value: allowed.filter((a) => list.includes(a)) };
}

const validateAvailableTimes = (list) => validateWhitelist(list, AVAILABLE_TIMES, "available time");
const validateShiftTypes = (list) => validateWhitelist(list, SHIFT_TYPES, "shift type");

// [{category, level}] - max. 1 Eintrag je Kategorie
function validateExperience(list) {
  if (list == null) return { value: [] };
  if (!Array.isArray(list)) return { error: "Experience must be a list." };
  const seen = new Set();
  const out = [];
  for (const item of list) {
    if (!item || typeof item !== "object") return { error: "Invalid experience entry." };
    const { category, level } = item;
    if (!CATEGORIES.includes(category)) return { error: `Invalid experience category: ${String(category)}.` };
    if (!EXPERIENCE_LEVELS.includes(level)) return { error: `Invalid experience level for ${category}.` };
    if (seen.has(category)) return { error: `Experience for ${category} was given more than once.` };
    seen.add(category);
    out.push({ category, level });
  }
  return { value: out };
}

// Fuer die Ausgabe: ungueltige/doppelte Eintraege (Bestandsdaten, manuelle DB-Eingriffe) still verwerfen
function cleanExperience(raw) {
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const out = [];
  for (const item of raw) {
    if (!item || !CATEGORIES.includes(item.category) || !EXPERIENCE_LEVELS.includes(item.level)) continue;
    if (seen.has(item.category)) continue;
    seen.add(item.category);
    out.push({ category: item.category, level: item.level });
  }
  return out;
}

function cleanWhitelist(raw, allowed) {
  return Array.isArray(raw) ? allowed.filter((a) => raw.includes(a)) : [];
}

function validateYearFounded(value, now = new Date()) {
  if (value === undefined || value === null || value === "") return { value: null };
  const n = typeof value === "string" && /^\d+$/.test(value.trim()) ? Number(value) : value;
  const max = now.getUTCFullYear();
  if (!Number.isInteger(n) || n < MIN_YEAR_FOUNDED || n > max) {
    return { error: `Year founded must be between ${MIN_YEAR_FOUNDED} and ${max}.` };
  }
  return { value: n };
}

// Freitext: trim, leer -> null, Laengenlimit
function validateText(value, label, max) {
  if (value === undefined || value === null) return { value: null };
  if (typeof value !== "string") return { error: `${label} must be text.` };
  const t = value.trim();
  if (!t) return { value: null };
  if (t.length > max) return { error: `${label} must be at most ${max} characters.` };
  return { value: t };
}

const validateTagline = (v) => validateText(v, "Tagline", TAGLINE_MAX);

function validateZip(value) {
  if (value === undefined || value === null) return { value: null };
  if (typeof value !== "string") return { error: "ZIP code must be text." };
  const t = value.trim();
  if (!t) return { value: null };
  if (!/^\d{5}(-\d{4})?$/.test(t)) return { error: "ZIP code must be 5 digits or ZIP+4 (12345 or 12345-6789)." };
  return { value: t };
}

// Lat/Lng nur als gueltiges Paar (oder beide leer); nur Zahlen oder dezimale Zahl-Strings
function toCoordinate(v) {
  if (typeof v === "number") return Number.isFinite(v) ? v : NaN;
  if (typeof v === "string" && /^-?\d+(\.\d+)?$/.test(v.trim())) return Number(v.trim());
  return NaN;
}

function validateCoordinates(lat, lng) {
  const empty = (v) => v === undefined || v === null || v === "";
  if (empty(lat) && empty(lng)) return { value: { lat: null, lng: null } };
  if (empty(lat) || empty(lng)) return { error: "Address coordinates need both latitude and longitude." };
  const la = toCoordinate(lat);
  const ln = toCoordinate(lng);
  if (Number.isNaN(la) || Number.isNaN(ln)) return { error: "Address coordinates must be numbers." };
  if (la < -90 || la > 90 || ln < -180 || ln > 180) return { error: "Address coordinates are out of range." };
  return { value: { lat: la, lng: ln } };
}

const SOCIAL_LABELS = { instagram: "Instagram", linkedin: "LinkedIn", facebook: "Facebook", tiktok: "TikTok" };

// Erlaubte Hosts je Netzwerk (jeweils auch mit www./m.)
const SOCIAL_HOSTS = {
  instagram: ["instagram.com"],
  linkedin:  ["linkedin.com"],
  facebook:  ["facebook.com", "fb.com"],
  tiktok:    ["tiktok.com"],
};
const SOCIAL_MAX_LENGTH = 300;

// @handle -> Profil-URL je Netzwerk
function handleToUrl(key, handle) {
  switch (key) {
    case "instagram": return `https://instagram.com/${handle}`;
    case "tiktok":    return `https://www.tiktok.com/@${handle}`;
    case "linkedin":  return `https://www.linkedin.com/company/${handle}`;
    default:          return `https://facebook.com/${handle}`;
  }
}

function hostAllowed(key, hostname) {
  const host = hostname.toLowerCase().replace(/^(www|m)\./, "");
  return SOCIAL_HOSTS[key].includes(host);
}

function normalizeSocialValue(key, raw) {
  const label = SOCIAL_LABELS[key];
  const t = String(raw).trim();
  if (t.length > SOCIAL_MAX_LENGTH) return { error: `${label}: link is too long (max ${SOCIAL_MAX_LENGTH} characters).` };
  if (/^@[A-Za-z0-9._-]{1,50}$/.test(t)) return { value: handleToUrl(key, t.slice(1)) };
  if (/\s/.test(t)) return { error: `${label}: enter a link (https://...) or an @handle.` };
  // Nur http(s):// gilt als Schema; "evil.com:8080/x" ist ein Host mit Port, kein Schema
  const withScheme = /^[a-z][a-z0-9+.-]*:\/\//i.test(t) ? t
    : (/^(javascript|data|mailto|tel|file|ftp|vbscript):/i.test(t) ? t : `https://${t}`);
  let url;
  try { url = new URL(withScheme); } catch (_) { return { error: `${label}: enter a link (https://...) or an @handle.` }; }
  if (url.protocol !== "http:" && url.protocol !== "https:") {
    return { error: `${label}: only http(s) links or an @handle are allowed.` };
  }
  if (url.username || url.password) return { error: `${label}: links must not contain a username or password.` };
  if (!hostAllowed(key, url.hostname)) {
    return { error: `${label}: the link must point to ${SOCIAL_HOSTS[key].join(" or ")}.` };
  }
  return { value: url.toString() };
}

// { instagram, linkedin, facebook, tiktok } -> normalisiertes Objekt (nur belegte Keys) oder null
function normalizeSocialLinks(input) {
  if (input === undefined || input === null) return { value: null };
  if (typeof input !== "object" || Array.isArray(input)) return { error: "Social links must be an object." };
  const out = {};
  for (const key of SOCIAL_KEYS) {
    const raw = input[key];
    if (raw === undefined || raw === null || String(raw).trim() === "") continue;
    if (typeof raw !== "string") return { error: `${SOCIAL_LABELS[key]}: enter a link or an @handle.` };
    const r = normalizeSocialValue(key, raw);
    if (r.error) return r;
    out[key] = r.value;
  }
  return { value: Object.keys(out).length ? out : null };
}

// Ausgabe: nur bekannte Keys mit http(s)-URLs
function cleanSocialLinks(raw) {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return null;
  const out = {};
  for (const key of SOCIAL_KEYS) {
    const v = raw[key];
    if (typeof v === "string" && /^https?:\/\//i.test(v)) out[key] = v;
  }
  return Object.keys(out).length ? out : null;
}

// Worker-Body -> Update-Daten; { data, errors } (nur uebergebene Felder)
function validateWorkerProfileFields(body = {}) {
  const data = {};
  const errors = [];
  const apply = (key, fn) => {
    if (body[key] === undefined) return;
    const r = fn(body[key]);
    if (r.error) errors.push(r.error); else data[key] = r.value;
  };
  apply("availableTimes", validateAvailableTimes);
  apply("shiftTypes", validateShiftTypes);
  apply("experience", validateExperience);
  return { data, errors };
}

// Employer-Body -> Update-Daten (Prisma-Feldnamen); { data, errors } (nur uebergebene Felder)
function validateEmployerProfileFields(body = {}, now = new Date()) {
  const data = {};
  const errors = [];
  const take = (key, field, fn) => {
    if (body[key] === undefined) return;
    const r = fn(body[key]);
    if (r.error) errors.push(r.error); else data[field] = r.value;
  };
  take("yearFounded", "yearFounded", (v) => validateYearFounded(v, now));
  take("tagline", "tagline", validateTagline);
  take("socialLinks", "socialLinks", normalizeSocialLinks);
  take("streetAddress", "streetAddress", (v) => validateText(v, "Street address", 120));
  take("zipCode", "zipCode", validateZip);
  take("publicContactName", "publicContactName", (v) => validateText(v, "Contact name", 80));
  take("publicContactRole", "publicContactRole", (v) => validateText(v, "Contact role", 80));
  for (const key of ["postsInMultipleStates", "remoteFriendly"]) {
    if (body[key] === undefined) continue;
    if (typeof body[key] !== "boolean") errors.push(`${key} must be true or false.`);
    else data[key] = body[key];
  }
  if (body.addressLat !== undefined || body.addressLng !== undefined) {
    const r = validateCoordinates(body.addressLat, body.addressLng);
    if (r.error) errors.push(r.error);
    else { data.addressLat = r.value.lat; data.addressLng = r.value.lng; }
  }
  return { data, errors };
}

module.exports = {
  AVAILABLE_TIMES, SHIFT_TYPES, CATEGORIES, EXPERIENCE_LEVELS, TAGLINE_MAX, SOCIAL_KEYS,
  validateAvailableTimes, validateShiftTypes, validateExperience, cleanExperience, cleanWhitelist,
  validateYearFounded, validateTagline, validateZip, validateCoordinates,
  normalizeSocialLinks, cleanSocialLinks,
  validateWorkerProfileFields, validateEmployerProfileFields,
};
