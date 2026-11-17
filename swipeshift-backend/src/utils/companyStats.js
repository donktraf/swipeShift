// src/utils/companyStats.js
// Gemeinsame Firmen-Kennzahlen fuer Firmenprofil (routes.companies.js), Job-Detail und
// Saved Companies. Rein und DB-frei → testbar.

// Jobs einer Firma werden ueber den Firmennamen gefunden (case-insensitive)
function companyJobsWhere(companyName) {
  return { company: { equals: companyName, mode: "insensitive" } };
}

// "Abgeschlossene Schichten" der Firma = Jobs mit status "completed"
function isCompletedJob(job) {
  return job?.status === "completed";
}

function countCompletedJobs(jobs = []) {
  return jobs.filter(isCompletedJob).length;
}

// Kurztext fuer Karten: auf max. Zeichen (Graphem-Cluster, also nie mitten in Emoji/Surrogatpaaren)
// kuerzen, an Wortgrenze, "…" anhaengen
const segmenter = new Intl.Segmenter(undefined, { granularity: "grapheme" });

function truncateText(text, max = 120) {
  if (typeof text !== "string") return null;
  const clean = text.replace(/\s+/g, " ").trim();
  if (!clean) return null;
  const graphemes = Array.from(segmenter.segment(clean), (s) => s.segment);
  if (graphemes.length <= max) return clean;
  const cut = graphemes.slice(0, max);
  const lastSpace = cut.lastIndexOf(" ");
  const kept = (lastSpace > max * 0.6 ? cut.slice(0, lastSpace) : cut).join("");
  return kept.replace(/[\s.,;:!?-]+$/, "") + "…";
}

module.exports = { companyJobsWhere, isCompletedJob, countCompletedJobs, truncateText };
