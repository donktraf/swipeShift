// src/utils/uploadFiles.js — Upload-URL → Dateiname (rein, DB-/FS-frei)
// Uploads liegen flach in uploads/ und sind unter <host>/uploads/<name> erreichbar (routes.upload.js).
// Der Dateiname wird strikt aus dieser Struktur abgeleitet: genau ein Pfadsegment, nur [A-Za-z0-9._-],
// kein fuehrender Punkt → kein Traversal, keine Unterordner, keine versteckten Dateien.

const NAME_RE = /^[A-Za-z0-9_-][A-Za-z0-9._-]{0,200}$/;

function uploadFilenameFromUrl(url) {
  if (typeof url !== "string" || !url) return null;
  let u;
  try { u = new URL(url); } catch { return null; }
  if (u.protocol !== "http:" && u.protocol !== "https:") return null;
  if (u.search || u.hash) return null;
  const m = u.pathname.match(/^\/uploads\/([^/]+)$/);
  if (!m) return null;
  let name;
  try { name = decodeURIComponent(m[1]); } catch { return null; }
  if (name.includes("..") || !NAME_RE.test(name)) return null;
  return name;
}

// Dateinamen, die nach einer Aenderung nicht mehr gebraucht werden: alte \ neue (jeweils URLs, null erlaubt)
function filenamesToRelease(oldUrls = [], newUrls = []) {
  const keep = new Set(newUrls.map(uploadFilenameFromUrl).filter(Boolean));
  return [...new Set(oldUrls.map(uploadFilenameFromUrl).filter((n) => n && !keep.has(n)))];
}

// Datei-Alter-Check fuer verwaiste Uploads (Upload ohne Datensatz erst nach Karenz loeschen, sonst Race mit laufendem Speichern)
const ORPHAN_MIN_AGE_MS = 24 * 3600000;
function isOrphanOldEnough(mtimeMs, now = Date.now()) {
  return now - mtimeMs >= ORPHAN_MIN_AGE_MS;
}

// Foto-/Logo-URL beim SCHREIBEN pruefen: leer/null → null (erlaubt); sonst nur eigene Upload-URL (Host in allowedHosts),
// Query/Hash werden entfernt. Rueckgabe { ok, value }. Externe URLs (z.B. Social-Login-Fotos) landen heute nicht in
// profilePhotoUrl/companyLogoUrl (User hat kein Foto-Feld) und werden daher abgelehnt.
function normalizePhotoUrl(raw, allowedHosts = []) {
  if (raw === null || raw === undefined || raw === "") return { ok: true, value: null };
  if (typeof raw !== "string") return { ok: false, value: null };
  let u;
  try { u = new URL(raw); } catch { return { ok: false, value: null }; }
  if (!allowedHosts.filter(Boolean).map((h) => h.toLowerCase()).includes(u.host.toLowerCase())) return { ok: false, value: null };
  u.search = ""; u.hash = "";
  const clean = u.toString();
  if (!uploadFilenameFromUrl(clean)) return { ok: false, value: null };
  return { ok: true, value: clean };
}

module.exports = { normalizePhotoUrl, uploadFilenameFromUrl, filenamesToRelease, ORPHAN_MIN_AGE_MS, isOrphanOldEnough };
