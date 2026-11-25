// src/retention.js — Aufbewahrungsfristen (DB-Seite). Auswahl-Logik: utils/retention.js.
// Jede Funktion nimmt `now` (testbar) und liefert die Anzahl geloeschter Zeilen; `dryRun` zaehlt nur.
const { prisma } = require("./prisma.js");
const r = require("./utils/retention");

const BATCH = 1000;
const MAX_BATCHES = 20;

// Abgelaufene/widerrufene Sessions (inkl. IP) 30 Tage nach Ablauf/Widerruf; dazu deren Push-Geraete (sessionId ohne FK)
async function purgeOldSessions(now = new Date(), { dryRun = false } = {}) {
  const c = r.sessionCutoff(now);
  const where = { OR: [{ expiresAt: { lte: c } }, { revokedAt: { lte: c } }] };
  if (dryRun) return prisma.userSession.count({ where });
  let total = 0;
  for (let i = 0; i < MAX_BATCHES; i++) {
    const rows = await prisma.userSession.findMany({ where, select: { id: true }, take: BATCH });
    if (!rows.length) break;
    const ids = rows.map((x) => x.id);
    await prisma.pushDevice.deleteMany({ where: { sessionId: { in: ids } } });
    total += (await prisma.userSession.deleteMany({ where: { id: { in: ids } } })).count;
    if (rows.length < BATCH) break;
  }
  return total;
}

// Tokens/Challenges/Sperrzeilen: Ablauf (bzw. Verbrauch) + 7 Tage Karenz. Rueckgabe: { table: count }
async function purgeExpiredTokens(now = new Date(), { dryRun = false } = {}) {
  const c = r.tokenCutoff(now);
  const jobs = {
    passwordResetToken: { OR: [{ expiresAt: { lte: c } }, { usedAt: { lte: c } }] },
    emailVerificationToken: { OR: [{ expiresAt: { lte: c } }, { usedAt: { lte: c } }] },
    twoFactorCode: { OR: [{ expiresAt: { lte: c } }, { consumedAt: { lte: c } }] },
    // Sperrzeile: Zaehlfenster laengst vorbei und keine aktive Sperre (lockedUntil leer oder ebenfalls abgelaufen)
    twoFactorLock: { firstFailedAt: { lte: c }, OR: [{ lockedUntil: null }, { lockedUntil: { lte: c } }] },
  };
  const out = {};
  for (const [model, where] of Object.entries(jobs)) {
    out[model] = dryRun ? await prisma[model].count({ where }) : (await prisma[model].deleteMany({ where })).count;
  }
  return out;
}

// IDs mit aktivem Bann (User.bannedAt / DeletedAccount.bannedAt)
async function loadBannedIds() {
  const [users, tombs] = await Promise.all([
    prisma.user.findMany({ where: { bannedAt: { not: null } }, select: { id: true, bannedAt: true } }),
    prisma.deletedAccount.findMany({ where: { bannedAt: { not: null } }, select: { id: true, bannedAt: true } }),
  ]);
  return r.activeBanTargets(users, tombs);
}

// Abgeschlossene Meldungen (resolvedAt) und Moderationsmassnahmen (createdAt) nach 2 Jahren; nie offene Meldungen;
// nichts zu Personen mit aktivem Bann. Rueckgabe: { reports, actions }
async function purgeOldReports(now = new Date(), { dryRun = false } = {}) {
  const cutoff = r.reportCutoff(now);
  const banned = await loadBannedIds();
  const bannedList = [...banned];
  const out = { reports: 0, actions: 0 };

  const repWhere = { status: { not: "open" }, resolvedAt: { lte: cutoff }, ...(bannedList.length ? { reportedUserId: { notIn: bannedList } } : {}) };
  for (let i = 0; i < MAX_BATCHES; i++) {
    const rows = await prisma.userReport.findMany({ where: repWhere, select: { id: true, status: true, resolvedAt: true, reportedUserId: true }, orderBy: { id: "asc" }, take: BATCH });
    const ids = rows.filter((x) => r.isReportPurgeable(x, banned, now)).map((x) => x.id);
    if (dryRun) { out.reports = await prisma.userReport.count({ where: repWhere }); break; }
    if (ids.length) out.reports += (await prisma.userReport.deleteMany({ where: { id: { in: ids }, status: { not: "open" } } })).count;
    if (rows.length < BATCH || !ids.length) break;
  }

  const actWhere = { createdAt: { lte: cutoff }, ...(bannedList.length ? { targetUserId: { notIn: bannedList } } : {}) };
  for (let i = 0; i < MAX_BATCHES; i++) {
    const rows = await prisma.moderationAction.findMany({ where: actWhere, select: { id: true, targetUserId: true, createdAt: true }, orderBy: { id: "asc" }, take: BATCH });
    const ids = rows.filter((x) => r.isActionPurgeable(x, banned, now)).map((x) => x.id);
    if (dryRun) { out.actions = await prisma.moderationAction.count({ where: actWhere }); break; }
    if (ids.length) out.actions += (await prisma.moderationAction.deleteMany({ where: { id: { in: ids } } })).count;
    if (rows.length < BATCH || !ids.length) break;
  }
  return out;
}

module.exports = { purgeOldSessions, purgeExpiredTokens, purgeOldReports, loadBannedIds };
