// src/utils/jobData.js
// Gemeinsames, DB-freies Feld-Mapping fuer POST /jobs und PUT /jobs/:id.
// lat/lng werden hier nur aus dem Body uebernommen; Geocoding-Fallback passiert in der Route.

// Waehrung: US-Dollar (US-Launch). Einziger Ort fuer das Symbol im Backend.
const CURRENCY_SYMBOL = "$";
// Regel (identisch zu Money.swift in der App): ganze Betraege ohne Nachkommastellen,
// sonst immer 2 ("$18", "$15.50"); Rundung auf Cent. Format: "$X / hr".
function formatAmount(amount) {
  const cents = Math.round(Number(amount) * 100);
  const text = cents % 100 === 0 ? String(cents / 100) : (cents / 100).toFixed(2);
  return `${CURRENCY_SYMBOL}${text}`;
}
function formatPayText(amount) {
  return `${formatAmount(amount)} / hr`;
}

// Erlaubte Werte der optionalen Zusatzfelder (Strings identisch zur iOS-App)
const ALLOWED = {
  requiredSkills:       ["Communication", "Teamwork", "Reliability", "Working under Pressure"],
  physicalRequirements: ["Standing for long periods", "Lifting up to 25 lbs", "Lifting up to 50 lbs", "Walking / on feet", "Bending / kneeling", "Working outdoors"],
  certifications:       ["Food Handler Card", "Alcohol Server Certification", "Forklift License", "First Aid / CPR", "Security Guard License", "Driver's License"],
  educationLevel:       ["None required", "High School Diploma / GED", "Vocational Training", "College Degree"],
  urgency:              ["normal", "urgent"],
  locationType:         ["single", "multiple"],
  cancellationPolicy:   ["flexible", "24h", "48h", "strict"],
  breakMinutes:         [15, 30, 45, 60],
};
const ALLOWED_ARRAY_FIELDS = ["requiredSkills", "physicalRequirements", "certifications"];
const BOOLEAN_FIELDS = ["workAuthorizationRequired", "breakIncluded", "sameDayPay", "tipsIncluded", "repeatWork", "bonusAvailable", "instantMatch"];
const MAX_LEN = { bonusDescription: 200, cancellationNotes: 300, jobNotes: 500 };

// Strikt: nur echtes true zaehlt (kein "false"-String, keine 1)
const toBool = (v) => v === true;
const isBlank = (v) => v == null || v === "";
const cleanText = (v, max) => {
  if (typeof v !== "string") return null;
  const t = v.trim();
  return t ? t.slice(0, max) : null;
};
const uniqueAllowed = (v, allowed) => (Array.isArray(v) ? [...new Set(v.filter((x) => allowed.includes(x)))] : []);

const { ageFromBirthDate } = require("./workerProfile");

function buildJobData(body = {}) {
  const {
    title, company, location, lat: bodyLat, lng: bodyLng, category, tags,
    shifts, openSpots, payAmount, payText,
    jobDescription, tasks, dressCode, languages,
    experienceLevel, minAge, paymentMethod, contractType,
  } = body;

  return {
    title,
    company:     company || "Unknown",
    location:    location || "",
    lat:         bodyLat != null && bodyLat !== "" ? parseFloat(bodyLat) : null,
    lng:         bodyLng != null && bodyLng !== "" ? parseFloat(bodyLng) : null,
    category:    category || null,
    tags:        tags || [],
    payText:     payText || (payAmount ? formatPayText(payAmount) : "On request"),
    payAmount:   payAmount ? parseFloat(payAmount) : null,
    shiftText:   shifts?.[0] ? `${shifts[0].date}, ${shifts[0].timeRange}` : "",
    startTime:   shifts?.[0]?.startTimeISO ? new Date(shifts[0].startTimeISO) : null,
    endTime:     shifts?.[0]?.endTimeISO   ? new Date(shifts[0].endTimeISO)   : null,
    duration:    shifts?.[0]?.duration || null,
    shortInfo:   jobDescription ? jobDescription.slice(0, 120) : "",
    jobDescription: jobDescription || null,
    tasks:       tasks || [],
    openSpots:   openSpots || 1,
    shifts:      shifts || [],
    dressCode:   dressCode || null,
    languages:   languages || [],
    experienceLevel: experienceLevel || null,
    minAge:      minAge ? parseInt(minAge) : null,
    paymentMethod: paymentMethod || null,
    contractType:  contractType || null,
    logoEmoji:   "🏢",
    ...buildExtraFields(body),
  };
}

// Optionale Zusatzfelder; abhaengige Felder werden bereinigt (Break nur mit breakIncluded, Bonus-Text nur mit bonusAvailable)
function buildExtraFields(body) {
  const breakIncluded  = toBool(body.breakIncluded);
  const bonusAvailable = toBool(body.bonusAvailable);
  const breakMinutes   = isBlank(body.breakMinutes) ? null : Number(body.breakMinutes);
  return {
    requiredSkills:       uniqueAllowed(body.requiredSkills, ALLOWED.requiredSkills),
    physicalRequirements: uniqueAllowed(body.physicalRequirements, ALLOWED.physicalRequirements),
    certifications:       uniqueAllowed(body.certifications, ALLOWED.certifications),
    educationLevel:       ALLOWED.educationLevel.includes(body.educationLevel) ? body.educationLevel : null,
    workAuthorizationRequired: toBool(body.workAuthorizationRequired),
    urgency:              body.urgency === "urgent" ? "urgent" : "normal",
    locationType:         body.locationType === "multiple" ? "multiple" : "single",
    breakIncluded,
    breakMinutes:         breakIncluded && ALLOWED.breakMinutes.includes(breakMinutes) ? breakMinutes : null,
    sameDayPay:           toBool(body.sameDayPay),
    tipsIncluded:         toBool(body.tipsIncluded),
    repeatWork:           toBool(body.repeatWork),
    bonusAvailable,
    bonusDescription:     bonusAvailable ? cleanText(body.bonusDescription, MAX_LEN.bonusDescription) : null,
    cancellationPolicy:   ALLOWED.cancellationPolicy.includes(body.cancellationPolicy) ? body.cancellationPolicy : null,
    cancellationNotes:    cleanText(body.cancellationNotes, MAX_LEN.cancellationNotes),
    jobNotes:             cleanText(body.jobNotes, MAX_LEN.jobNotes),
    instantMatch:         toBool(body.instantMatch),
  };
}

// Validierung der Zusatzfelder; liefert Fehlermeldung oder null
function validateExtraFields(body) {
  for (const f of ALLOWED_ARRAY_FIELDS) {
    const v = body[f];
    if (v == null) continue;
    if (!Array.isArray(v)) return `${f} must be an array.`;
    if (!v.every((x) => ALLOWED[f].includes(x))) return `${f} contains an unsupported value.`;
  }
  for (const f of ["educationLevel", "urgency", "locationType", "cancellationPolicy"]) {
    if (!isBlank(body[f]) && !ALLOWED[f].includes(body[f])) return `${f} has an unsupported value.`;
  }
  if (!isBlank(body.breakMinutes) && !ALLOWED.breakMinutes.includes(Number(body.breakMinutes))) {
    return "breakMinutes must be 15, 30, 45 or 60.";
  }
  for (const f of BOOLEAN_FIELDS) {
    if (body[f] != null && typeof body[f] !== "boolean") return `${f} must be a boolean.`;
  }
  for (const [f, max] of Object.entries(MAX_LEN)) {
    const v = body[f];
    if (v == null) continue;
    if (typeof v !== "string") return `${f} must be a string.`;
    if (v.length > max) return `${f} must be at most ${max} characters.`;
  }
  return null;
}

// Veroeffentlichen braucht die Zustimmung zu den Employer-AGB (strikt true). Drafts nicht.
const TERMS_REQUIRED_ERROR = {
  error: "You must accept the Terms for Employers to publish a job.",
  code: "TERMS_REQUIRED",
};
function hasAcceptedTerms(body = {}) {
  return body.termsAccepted === true;
}

// POST /jobs: Status ist nur "draft" oder "published" (Default "published"). Liefert { status } oder { error }.
function resolveCreateStatus(raw) {
  const status = raw ?? "published";
  if (status !== "draft" && status !== "published") return { error: "status must be 'draft' or 'published'." };
  return { status };
}

const ALL_STATUSES = ["published", "draft", "cancelled", "completed", "inProgress"];
// Von "draft" aus sind nur Veroeffentlichen oder Verwerfen sinnvoll
const DRAFT_TARGETS = ["draft", "published", "cancelled"];

// Entscheidung fuer PATCH /jobs/:id/status (rein, testbar).
// Ergebnis: { ok: true, publishing } oder { ok: false, status, body }.
// publishing = jeder Wechsel nach "published" aus einem anderen Status → braucht Terms, setzt termsAcceptedAt.
function evaluateStatusChange(currentStatus, nextStatus, body = {}) {
  if (!ALL_STATUSES.includes(nextStatus)) {
    return { ok: false, status: 400, body: { error: `Invalid status. Allowed: ${ALL_STATUSES.join(", ")}` } };
  }
  if (currentStatus === "draft" && !DRAFT_TARGETS.includes(nextStatus)) {
    return { ok: false, status: 409, body: { error: "A draft can only be published or cancelled.", code: "INVALID_TRANSITION" } };
  }
  const publishing = nextStatus === "published" && currentStatus !== "published";
  if (publishing && !hasAcceptedTerms(body)) return { ok: false, status: 400, body: TERMS_REQUIRED_ERROR };
  return { ok: true, publishing };
}

// Instant Match: automatische Annahme nur, wenn noch Plaetze frei sind UND der Worker die harten
// Anforderungen erfuellt (Mindestalter, Arbeitserlaubnis); sonst normale "pending"-Bewerbung.
// worker: { dateOfBirth, workAuthorization } | null. Fehlendes Geburtsdatum zaehlt bei minAge als nicht erfuellt.
// TODO: Zertifikate koennen nicht geprueft werden (kein Worker-Feld dafuer).
function shouldAutoAccept({ job, worker, acceptedCount, now = new Date() }) {
  if (!job?.instantMatch) return false;
  if (!(acceptedCount < (job.openSpots ?? 1))) return false;
  if (job.minAge) {
    const age = ageFromBirthDate(worker?.dateOfBirth, now);
    if (age == null || age < job.minAge) return false;
  }
  if (job.workAuthorizationRequired && worker?.workAuthorization !== true) return false;
  return true;
}

// Validiert den Body (POST + PUT identisch). Liefert lesbare Fehlermeldung oder null.
function validateJobBody(body = {}) {
  for (const f of ["shifts", "tags", "tasks", "languages"]) {
    if (body[f] != null && !Array.isArray(body[f])) return `${f} must be an array.`;
  }
  const isBlank = (v) => v == null || v === "";
  for (const f of ["lat", "lng", "payAmount", "minAge"]) {
    const v = body[f];
    if (isBlank(v)) continue;
    // 0 / false werden von buildJobData ohnehin zu null; hier nur nicht-endliche Zahlen abfangen
    const n = f === "minAge" ? parseInt(v, 10) : Number(v);
    if (!Number.isFinite(n)) return `${f} must be a valid number.`;
  }
  if (!isBlank(body.openSpots)) {
    const n = Number(body.openSpots);
    if (!Number.isInteger(n) || n < 0) return "openSpots must be a whole number.";
  }
  return validateExtraFields(body);
}

// Owner-/Draft-Pruefung fuer PUT/DELETE. null = erlaubt, sonst { status, error, code? }.
function checkDraftAccess(job, userId) {
  if (!job) return { status: 404, error: "Job not found" };
  if (job.employerId !== userId) return { status: 403, error: "Forbidden" };
  if (job.status !== "draft") {
    return { status: 409, error: "Only drafts can be edited or deleted.", code: "NOT_DRAFT" };
  }
  return null;
}

module.exports = { resolveCreateStatus, evaluateStatusChange, shouldAutoAccept, TERMS_REQUIRED_ERROR, hasAcceptedTerms, CURRENCY_SYMBOL, formatAmount, formatPayText, buildJobData, validateJobBody, checkDraftAccess };
