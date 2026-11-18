// src/utils/jobNotes.js
// Job-Notizen des Employers ("Notes from the employer") sind fuer einen Worker nur sichtbar,
// solange seine Bewerbung offen (pending) oder angenommen ist. Rein und DB-frei → testbar.

function jobNotesForApply(applyStatus, jobNotes) {
  if (applyStatus !== "pending" && applyStatus !== "accepted") return null;
  const text = typeof jobNotes === "string" ? jobNotes.trim() : "";
  return text || null;
}

module.exports = { jobNotesForApply };
