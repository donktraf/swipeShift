// src/utils/jobData.js
// Gemeinsames, DB-freies Feld-Mapping fuer POST /jobs und PUT /jobs/:id.
// lat/lng werden hier nur aus dem Body uebernommen; Geocoding-Fallback passiert in der Route.

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
    payText:     payText || (payAmount ? `€${payAmount} / hour` : "On request"),
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
  };
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
  return null;
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

module.exports = { buildJobData, validateJobBody, checkDraftAccess };
