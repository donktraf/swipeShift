// src/utils/retention.js — Aufbewahrungsfristen und Auswahl-Logik (rein, DB-frei)
//   - Sessions (inkl. IP): 30 Tage nach Ablauf bzw. Widerruf
//   - Token/Challenges/Sperrzeilen: Ablauf (bzw. Verbrauch) + Karenz
//   - Meldungen/Moderation: 2 Jahre, ausser bei aktivem Bann

const DAY_MS = 86400000;
const SESSION_RETENTION_DAYS = 30;
const TOKEN_GRACE_DAYS = 7;
const REPORT_RETENTION_DAYS = 730;

const ms = (d) => new Date(d).getTime();
const cutoffFor = (now, days) => new Date(ms(now) - days * DAY_MS);
const sessionCutoff = (now = new Date()) => cutoffFor(now, SESSION_RETENTION_DAYS);
const tokenCutoff = (now = new Date()) => cutoffFor(now, TOKEN_GRACE_DAYS);
const reportCutoff = (now = new Date()) => cutoffFor(now, REPORT_RETENTION_DAYS);

// Session loeschbar: Ablauf ODER Widerruf liegt mindestens 30 Tage zurueck
function isSessionPurgeable(s, now = new Date()) {
  const c = ms(sessionCutoff(now));
  return (!!s.expiresAt && ms(s.expiresAt) <= c) || (!!s.revokedAt && ms(s.revokedAt) <= c);
}

// Aktive Banns: Set aller Ziel-IDs (User.bannedAt bzw. DeletedAccount.bannedAt gesetzt)
function activeBanTargets(users = [], tombstones = []) {
  return new Set([...users, ...tombstones].filter((x) => x.bannedAt).map((x) => x.id));
}

// Meldung loeschbar: abgeschlossen, resolvedAt >= 2 Jahre her, kein aktiver Bann gegen die gemeldete Person.
// Offene Meldungen nie.
function isReportPurgeable(r, bannedIds, now = new Date()) {
  if (r.status === "open" || !r.resolvedAt) return false;
  if (bannedIds.has(r.reportedUserId)) return false;
  return ms(r.resolvedAt) <= ms(reportCutoff(now));
}

// Moderationsmassnahme loeschbar: createdAt >= 2 Jahre her, kein aktiver Bann gegen die Zielperson
function isActionPurgeable(a, bannedIds, now = new Date()) {
  if (bannedIds.has(a.targetUserId)) return false;
  return ms(a.createdAt) <= ms(reportCutoff(now));
}

module.exports = {
  DAY_MS, SESSION_RETENTION_DAYS, TOKEN_GRACE_DAYS, REPORT_RETENTION_DAYS,
  sessionCutoff, tokenCutoff, reportCutoff,
  isSessionPurgeable, activeBanTargets, isReportPurgeable, isActionPurgeable,
};
