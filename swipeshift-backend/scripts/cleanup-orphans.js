// scripts/cleanup-orphans.js
// Einmaliges Aufraeumen von Altlasten (Konto-Loeschung hat frueher Dateien/Jobs/Sessions zurueckgelassen):
//   npm run cleanup:orphans               → Dry-Run (nur Ausgabe)
//   npm run cleanup:orphans -- --apply --confirm-db=<dbname>   → fuehrt aus (dbname = Name aus DATABASE_URL)
//   (--force-remote hebt den Schutz gegen Produktion/Remote-Datenbank auf)
// Umfang:
//   1. Upload-Dateien ohne referenzierenden Datensatz (Worker.profilePhotoUrl / Employer.companyLogoUrl), aelter als 24 h
//   2. Offene Jobs (draft/published/inProgress), deren employerId keinen User mehr hat → cancelled (ohne Benachrichtigung)
//   3. Abgelaufene/widerrufene Sessions (> 30 Tage) und abgelaufene Tokens/Challenges (> 7 Tage Karenz)
// Geschuetzt (nie angefasst): Konten test1@example.de, test2@example.de, workk1@example.de, deren Uploads, [TEST]-Jobs.

require("dotenv").config();
const { prisma } = require("../src/prisma.js");
const { findOrphanUploads, deleteOrphans } = require("../src/uploadCleanup");
const { uploadFilenameFromUrl } = require("../src/utils/uploadFiles");
const { cancelOpenJobs } = require("../src/accountCleanup");
const { OPEN_JOB_STATUSES } = require("../src/utils/accountCleanup");
const { purgeOldSessions, purgeExpiredTokens } = require("../src/retention");

const PROTECTED_EMAILS = ["test1@example.de", "test2@example.de", "workk1@example.de"];
const TEST_PREFIX = "[TEST]";

function describeDatabase(url) {
  try {
    const u = new URL(url);
    return { host: u.hostname.replace(/^\[|\]$/g, ""), name: u.pathname.replace(/^\//, ""), port: u.port };
  } catch { return null; }
}

async function main() {
  const args = process.argv.slice(2);
  const apply = args.includes("--apply");
  const forceRemote = args.includes("--force-remote");
  if (process.env.NODE_ENV === "production" && !forceRemote) {
    console.error("Refusing to run: NODE_ENV=production. Use --force-remote to override.");
    return 1;
  }
  const db = describeDatabase(process.env.DATABASE_URL || "");
  if (!db) { console.error("Refusing to run: DATABASE_URL missing or unreadable."); return 1; }
  console.log(`Target database: ${db.host}${db.port ? ":" + db.port : ""}/${db.name}`);
  if (!["localhost", "127.0.0.1", "::1"].includes(db.host) && !forceRemote) {
    console.error(`Refusing to run: database host "${db.host}" is not local. Use --force-remote to override.`);
    return 1;
  }
  const confirm = (args.find((a) => a.startsWith("--confirm-db=")) || "").slice("--confirm-db=".length);
  if (apply && confirm !== db.name) {
    console.error(`Refusing to apply: pass --confirm-db=${db.name} (must match the database name in DATABASE_URL).`);
    return 1;
  }
  console.log(apply ? "Mode: APPLY (changes are made)\n" : "Mode: DRY-RUN (no changes; use --apply --confirm-db=<dbname> to execute)\n");

  const now = new Date();
  const protectedUsers = await prisma.user.findMany({
    where: { email: { in: PROTECTED_EMAILS } },
    select: { id: true, email: true, worker: { select: { profilePhotoUrl: true } }, employer: { select: { companyLogoUrl: true } } },
  });
  const protectedIds = new Set(protectedUsers.map((u) => u.id));
  console.log(`Protected accounts found: ${protectedUsers.map((u) => u.email).join(", ") || "none"}`);

  // 1. Upload-Dateien ohne Datensatz
  const found = await findOrphanUploads(now);
  const orphanFiles = found.orphans;
  console.log(`\n[uploads] ${found.total} files, ${found.referenced} referenced, ${orphanFiles.length} orphaned` +
    (found.skippedYoung ? `, ${found.skippedYoung} unreferenced but younger than 24 h (kept)` : "") + (found.skippedOther ? `, ${found.skippedOther} skipped (not a plain file)` : ""));
  orphanFiles.forEach((n) => console.log(`  - ${n}`));
  // Gegenprobe: geschuetzte Uploads duerfen nie in der Liste stehen
  const protectedFiles = protectedUsers.flatMap((u) => [u.worker?.profilePhotoUrl, u.employer?.companyLogoUrl]).map(uploadFilenameFromUrl).filter(Boolean);
  if (protectedFiles.some((n) => orphanFiles.includes(n))) throw new Error("Safety check failed: a protected upload is listed as orphan");
  console.log(`  protected uploads present and kept: ${protectedFiles.length}`);

  // 2. Jobs ohne existierenden Employer-User
  const jobGroups = await prisma.job.groupBy({ by: ["employerId"], where: { employerId: { not: null } } });
  const employerIds = jobGroups.map((g) => g.employerId);
  const existing = new Set((await prisma.user.findMany({ where: { id: { in: employerIds } }, select: { id: true } })).map((u) => u.id));
  const missingIds = employerIds.filter((id) => !existing.has(id) && !protectedIds.has(id));
  const orphanJobs = missingIds.length
    ? await prisma.job.findMany({ where: { employerId: { in: missingIds } }, select: { id: true, title: true, status: true, company: true, employerId: true } })
    : [];
  const protectedTestJobs = orphanJobs.filter((j) => j.title.startsWith(TEST_PREFIX));
  const toCancel = orphanJobs.filter((j) => OPEN_JOB_STATUSES.includes(j.status) && !j.title.startsWith(TEST_PREFIX));
  console.log(`\n[jobs] ${orphanJobs.length} jobs with missing employer user (${missingIds.length} dangling employerIds); ${toCancel.length} open → cancel` +
    (protectedTestJobs.length ? `; ${protectedTestJobs.length} [TEST] jobs left alone` : ""));
  toCancel.forEach((j) => console.log(`  - ${j.id} [${j.status}] "${j.title}" (${j.company})`));
  const testJobsAll = await prisma.job.count({ where: { title: { startsWith: TEST_PREFIX } } });
  console.log(`  [TEST] jobs in DB (untouched): ${testJobsAll}`);

  // 3. Sessions / Tokens
  const sessions = await purgeOldSessions(now, { dryRun: true });
  const tokens = await purgeExpiredTokens(now, { dryRun: true });
  console.log(`\n[sessions] ${sessions} sessions expired/revoked > 30 days`);
  console.log(`[tokens] ${Object.entries(tokens).map(([k, v]) => `${k}: ${v}`).join(", ")}`);

  if (!apply) { console.log("\nDry-run only. Re-run with --apply --confirm-db=${db.name} to execute."); return 0; }

  const deletedFiles = await deleteOrphans(orphanFiles); // prueft vor jedem Loeschen erneut auf Referenzen
  const cancelled = toCancel.length
    ? await prisma.$transaction((tx) => cancelOpenJobs(tx, { id: { in: toCancel.map((j) => j.id) } }))
    : [];
  const s = await purgeOldSessions(now);
  const t = await purgeExpiredTokens(now);
  console.log(`\nApplied: ${deletedFiles} files deleted, ${cancelled.length} jobs cancelled (no notifications), ${s} sessions deleted, tokens: ${JSON.stringify(t)}`);
  return 0;
}

main()
  .then((code) => { process.exitCode = code; })
  .catch((err) => { console.error(err); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
