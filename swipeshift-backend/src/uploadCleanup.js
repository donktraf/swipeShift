// src/uploadCleanup.js — Upload-Dateien loeschen (Konto-Loeschung, Foto ersetzt). Wirft nie.
const path = require("path");
const fs = require("fs");
const { prisma } = require("./prisma.js");
const { uploadFilenameFromUrl, filenamesToRelease, normalizePhotoUrl, isOrphanOldEnough } = require("./utils/uploadFiles");

// Muss mit dem Speicherort in routes.upload.js uebereinstimmen (Projekt-Root/uploads)
const UPLOAD_DIR = path.join(__dirname, "..", "uploads");

// Absoluter Pfad nur, wenn er direkt im Upload-Ordner liegt (zweite Absicherung nach der Namens-Whitelist)
function resolveUploadPath(name, dir = UPLOAD_DIR) {
  const full = path.resolve(dir, name);
  return path.dirname(full) === path.resolve(dir) && path.basename(full) === name ? full : null;
}

// Wird der Dateiname noch von einem Datensatz referenziert? (Schutz: URLs sind nutzergesetzt, nie fremde Datei loeschen)
async function isUploadReferenced(name) {
  const suffix = `/uploads/${name}`;
  const [w, e] = await Promise.all([
    prisma.worker.count({ where: { profilePhotoUrl: { contains: suffix } } }),
    prisma.employer.count({ where: { companyLogoUrl: { contains: suffix } } }),
  ]);
  return w + e > 0;
}

async function deleteUploadFile(name, dir = UPLOAD_DIR) {
  const full = resolveUploadPath(name, dir);
  if (!full) return false;
  try {
    const st = await fs.promises.lstat(full);
    if (!st.isFile()) return false; // keine Symlinks/Ordner
    await fs.promises.unlink(full);
    return true;
  } catch (err) {
    if (err?.code !== "ENOENT") console.error("uploadCleanup: could not delete", name, err);
    return false;
  }
}

// URLs, die nicht mehr gebraucht werden (alte Werte; keepUrls = neue Werte). Nur Dateien ohne weitere Referenz.
async function releaseUploads(oldUrls, keepUrls = []) {
  try {
    let n = 0;
    for (const name of filenamesToRelease(oldUrls, keepUrls)) {
      if (await isUploadReferenced(name)) continue;
      if (await deleteUploadFile(name)) n += 1;
    }
    return n;
  } catch (err) {
    console.error("uploadCleanup: release failed:", err);
    return 0;
  }
}

// Erlaubte Hosts fuer eigene Upload-URLs: Request-Host (so baut routes.upload.js die URL) + PUBLIC_API_BASE_URL
function ownHosts(req) {
  const hosts = [req?.get?.("host")];
  try { if (process.env.PUBLIC_API_BASE_URL) hosts.push(new URL(process.env.PUBLIC_API_BASE_URL).host); } catch { /* ignorieren */ }
  return hosts.filter(Boolean);
}
// → { ok, value } (value: normalisierte eigene Upload-URL oder null)
// existing = aktuell gespeicherter Wert: unveraendert zurueckgeschickte URLs (evtl. anderer Host, Altbestand) bleiben erlaubt
const checkPhotoUrl = (raw, req, existing = null) =>
  existing && raw === existing ? { ok: true, value: existing } : normalizePhotoUrl(raw, ownHosts(req));
const INVALID_PHOTO_MESSAGE = "Invalid photo URL. Please upload the image again.";

// Verwaiste Uploads: Dateien im Upload-Ordner ohne referenzierenden Datensatz, aelter als 24 h.
// → { total, referenced, orphans: [name], skippedYoung, skippedOther }
async function findOrphanUploads(now = new Date(), dir = UPLOAD_DIR) {
  const [workers, employers] = await Promise.all([
    prisma.worker.findMany({ where: { profilePhotoUrl: { not: null } }, select: { profilePhotoUrl: true } }),
    prisma.employer.findMany({ where: { companyLogoUrl: { not: null } }, select: { companyLogoUrl: true } }),
  ]);
  const referenced = new Set([...workers.map((w) => w.profilePhotoUrl), ...employers.map((e) => e.companyLogoUrl)]
    .map(uploadFilenameFromUrl).filter(Boolean));
  const files = fs.existsSync(dir) ? await fs.promises.readdir(dir) : [];
  const out = { total: files.length, referenced: referenced.size, orphans: [], skippedYoung: 0, skippedOther: 0 };
  for (const name of files) {
    if (referenced.has(name)) continue;
    const full = resolveUploadPath(name, dir);
    const st = full && !name.startsWith(".") ? await fs.promises.lstat(full).catch(() => null) : null;
    if (!st || !st.isFile() || !uploadFilenameFromUrl(`http://x/uploads/${encodeURIComponent(name)}`)) { out.skippedOther += 1; continue; }
    if (!isOrphanOldEnough(st.mtimeMs, now.getTime())) { out.skippedYoung += 1; continue; }
    out.orphans.push(name);
  }
  return out;
}

// Loescht uebergebene Waisen; vor JEDEM Loeschen wird die Referenz erneut geprueft (Race mit gerade gespeichertem Foto)
async function deleteOrphans(names, dir = UPLOAD_DIR) {
  let n = 0;
  for (const name of names) {
    if (await isUploadReferenced(name)) continue;
    if (await deleteUploadFile(name, dir)) n += 1;
  }
  return n;
}

async function sweepOrphanUploads(now = new Date()) {
  const found = await findOrphanUploads(now);
  return deleteOrphans(found.orphans);
}

module.exports = { findOrphanUploads, deleteOrphans, sweepOrphanUploads, ownHosts, checkPhotoUrl, INVALID_PHOTO_MESSAGE, UPLOAD_DIR, resolveUploadPath, isUploadReferenced, deleteUploadFile, releaseUploads, uploadFilenameFromUrl };
