// src/utils/tombstones.js — Retention fuer DeletedAccount (rein, DB-frei)
// Eintraege OHNE Bann und ohne aktive Sperre werden 90 Tage nach deletedAt geloescht (nach einem Unban: ab dem
// Unban-Zeitpunkt), aber nie, solange noch offene Reports gegen die ID existieren.

const TOMBSTONE_RETENTION_DAYS = 90;
const DAY_MS = 86400000;

const ms = (d) => new Date(d).getTime();

// Zeitpunkt, ab dem die Frist laeuft: max(deletedAt, unbannedAt)
function retentionStart(t) {
  return Math.max(ms(t.deletedAt), t.unbannedAt ? ms(t.unbannedAt) : 0);
}

// Spaetestes retentionStart, das jetzt schon abgelaufen ist (fuer die DB-Vorauswahl)
function retentionCutoff(now = new Date(), days = TOMBSTONE_RETENTION_DAYS) {
  return new Date(ms(now) - days * DAY_MS);
}

// tombs: [{ id, deletedAt, unbannedAt?, bannedAt?, suspendedUntil? }], openReportedIds: Set|Array → Array der zu loeschenden IDs
function selectExpiredTombstones(tombs, openReportedIds = [], now = new Date(), days = TOMBSTONE_RETENTION_DAYS) {
  const open = new Set(openReportedIds);
  const nowMs = ms(now);
  return tombs
    .filter((t) =>
      !t.bannedAt &&
      !(t.suspendedUntil && ms(t.suspendedUntil) > nowMs) &&
      !open.has(t.id) &&
      retentionStart(t) + days * DAY_MS <= nowMs)
    .map((t) => t.id);
}

// Darf `admin` die E-Mail eines geloeschten Kontos entbannen? Nicht, wenn er selbst dazu gemeldet hat (Interessenkonflikt).
function canUnbanDeleted(adminId, tombstone, reporterIds = []) {
  if (!tombstone) return { ok: false, status: 404, error: "Deleted account not found" };
  if (!tombstone.bannedAt) return { ok: false, status: 409, error: "This email address is not banned.", code: "NOT_BANNED" };
  if (reporterIds.includes(adminId)) return { ok: false, status: 403, error: "You can't handle a report you filed" };
  return { ok: true };
}

module.exports = { TOMBSTONE_RETENTION_DAYS, retentionStart, retentionCutoff, selectExpiredTombstones, canUnbanDeleted };
