// scripts/seed-test-shifts.js
// Entwickler-Skript: legt Test-Jobs fuer manuelle Simulator-Tests an (nie in production).
//   npm run seed:test-shifts
//   npm run seed:test-shifts -- --employer workk1@example.de --workers test1@example.de,test2@example.de
//
// Jobs (Titel-Praefix "[TEST] "):
//   1. Past shift   — gestern 09:00-13:00 (LA-Zeit), 2 Worker accepted, Attendance offen
//                     → Anwesenheit erfassen / No-Show / Widerspruch / Zahlung
//   2. Starts soon  — beginnt in ~5 h, 3 h lang, Worker 2 accepted → "late cancellation"-Warnung (< 24 h)
//   3. Multi shift  — 3 Schichten (in ~6 h, ~30 h, ~54 h), Worker 2 accepted fuer alle drei
//                     → "Cancel shift" pro Schicht (eine < 24 h = kurzfristig, zwei > 24 h)
// Idempotent: ersetzt vorher alle "[TEST] "-Jobs des Employers, die zusaetzlich den Seed-Marker in der Beschreibung
// tragen (Apply/Conversation/Message/Review... per Cascade; UserReports der Conversations werden vorher entfernt).
// Alles in EINER Transaktion.
// Schutz: lehnt NODE_ENV=production und Nicht-Localhost-Datenbanken ab (Override nur mit --force-remote).
// Hinweis: Es gibt keinen Cron, der Jobs automatisch auf "completed" setzt; der "Past shift" bleibt "published",
// Anwesenheit/Zahlung funktionieren trotzdem nach Schichtende.
// Accept wie im echten Handler: status accepted + respondedAt + acceptedAt; kein openSpots-Abzug (Kapazitaet
// wird aus den accepted-Applies berechnet) und keine Accept-Systemnachricht (nur Push).

require("dotenv").config();
const { prisma } = require("../src/prisma.js");
const { buildJobData } = require("../src/utils/jobData");
const { platformFeePercent } = require("../src/utils/fees");

const PREFIX = "[TEST] ";
const MARKER = "Test data created by scripts/seed-test-shifts.js.";
const TIME_ZONE = "America/Los_Angeles";
const HOUR = 3_600_000;

function parseArgs(argv) {
  const out = { employer: "workk1@example.de", workers: "test1@example.de,test2@example.de" };
  let forceRemote = false;
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--force-remote") { forceRemote = true; continue; }
    const m = argv[i].match(/^--(employer|workers)(?:=(.*))?$/);
    if (!m) continue;
    out[m[1]] = m[2] !== undefined ? m[2] : argv[++i];
  }
  return {
    forceRemote,
    employer: String(out.employer || "").trim().toLowerCase(),
    workers: String(out.workers || "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean),
  };
}

// Offset (ms) der Zeitzone zu UTC an einem Zeitpunkt
function zoneOffsetMs(zone, date) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", {
    timeZone: zone, hourCycle: "h23", year: "numeric", month: "2-digit", day: "2-digit", hour: "2-digit", minute: "2-digit", second: "2-digit",
  }).formatToParts(date).map((x) => [x.type, x.value]));
  return Date.UTC(p.year, p.month - 1, p.day, p.hour, p.minute, p.second) - Math.floor(date.getTime() / 1000) * 1000;
}
// Lokale Wandzeit (y, m, d, h) in zone → UTC-Date
function zonedToUtc(zone, y, m, d, h) {
  const guess = Date.UTC(y, m - 1, d, h);
  return new Date(guess - zoneOffsetMs(zone, new Date(guess - zoneOffsetMs(zone, new Date(guess)))));
}
function localParts(zone, date) {
  const p = Object.fromEntries(new Intl.DateTimeFormat("en-US", { timeZone: zone, year: "numeric", month: "numeric", day: "numeric" })
    .formatToParts(date).map((x) => [x.type, x.value]));
  return { y: +p.year, m: +p.month, d: +p.day };
}
// Formate wie PostJobView: "EE, MMM dd" / "HH:mm–HH:mm" / "4h" bzw. "3h 30min" / "$80.00 total"
const fmtDate = (d) => new Intl.DateTimeFormat("en-US", { timeZone: TIME_ZONE, weekday: "short", month: "short", day: "2-digit" }).format(d);
const fmtTime = (d) => new Intl.DateTimeFormat("en-GB", { timeZone: TIME_ZONE, hour: "2-digit", minute: "2-digit", hourCycle: "h23" }).format(d);

function fmtDuration(ms) {
  const h = Math.floor(ms / HOUR);
  const m = Math.floor((ms % HOUR) / 60_000);
  return m === 0 ? `${h}h` : `${h}h ${m}min`;
}

function makeShift(id, start, end, payPerHour) {
  const hours = (end - start) / HOUR;
  return {
    id, date: fmtDate(start), timeRange: `${fmtTime(start)}–${fmtTime(end)}`,
    duration: fmtDuration(end - start), totalPay: `$${(hours * payPerHour).toFixed(2)} total`,
    startTimeISO: start.toISOString(), endTimeISO: end.toISOString(),
  };
}

async function findUsers(args) {
  const emails = [args.employer, ...args.workers];
  const users = await prisma.user.findMany({ where: { email: { in: emails } }, select: { id: true, email: true, role: true } });
  const byEmail = new Map(users.map((u) => [u.email, u]));
  const missing = emails.filter((e) => !byEmail.has(e));
  if (missing.length) throw new Error(`Users not found: ${missing.join(", ")}`);
  const employer = byEmail.get(args.employer);
  if (employer.role !== "employer") throw new Error(`${employer.email} is not an employer (role=${employer.role})`);
  const workers = args.workers.map((e) => byEmail.get(e));
  for (const w of workers) if (w.role !== "worker") throw new Error(`${w.email} is not a worker (role=${w.role})`);
  return { employer, workers };
}

// Ziel-DB ohne Passwort; null bei fehlender/unlesbarer URL
function describeDatabase(url) {
  try {
    const u = new URL(url);
    return { host: u.hostname.replace(/^\[|\]$/g, ""), name: u.pathname.replace(/^\//, ""), port: u.port };
  } catch { return null; }
}

async function main() {
  if (process.env.NODE_ENV === "production") {
    console.error("Refusing to run: NODE_ENV=production. This script only creates test data for development.");
    return 1;
  }
  const args = parseArgs(process.argv.slice(2));
  const db = describeDatabase(process.env.DATABASE_URL || "");
  if (!db) { console.error("Refusing to run: DATABASE_URL missing or unreadable."); return 1; }
  console.log(`Target database: ${db.host}${db.port ? ":" + db.port : ""}/${db.name}`);
  if (!["localhost", "127.0.0.1", "::1"].includes(db.host) && !args.forceRemote) {
    console.error(`Refusing to run: database host "${db.host}" is not local. Use --force-remote to override.`);
    return 1;
  }
  if (args.workers.length < 2) {
    console.error("Need at least two workers: --workers a@x.de,b@x.de");
    return 1;
  }
  let users;
  try { users = await findUsers(args); } catch (e) { console.error(e.message); return 1; }
  const { employer, workers } = users;
  const profile = await prisma.employer.findUnique({ where: { userId: employer.id }, select: { companyName: true } });
  if (!profile?.companyName) {
    console.error(`${employer.email} has no employer profile (finish employer onboarding first).`);
    return 1;
  }
  const company = profile.companyName;

  const now = new Date();
  const pay = 20;
  const yday = localParts(TIME_ZONE, new Date(now.getTime() - 24 * HOUR));
  const pastShift = makeShift("s1", zonedToUtc(TIME_ZONE, yday.y, yday.m, yday.d, 9), zonedToUtc(TIME_ZONE, yday.y, yday.m, yday.d, 13), pay);
  const soonStart = new Date(Math.ceil((now.getTime() + 5 * HOUR) / 60_000) * 60_000);
  const soonShift = makeShift("s1", soonStart, new Date(soonStart.getTime() + 3 * HOUR), pay);

  const multiStart = (h) => new Date(Math.ceil((now.getTime() + h * HOUR) / 60_000) * 60_000);
  const multiShifts = [6, 30, 54].map((h, i) => {
    const st = multiStart(h);
    return makeShift(`s${i + 1}`, st, new Date(st.getTime() + 3 * HOUR), pay);
  });

  const specs = [
    { title: "Past shift", shifts: [pastShift], accepted: workers },
    { title: "Starts soon", shifts: [soonShift], accepted: [workers[1]] },
    { title: "Multi shift", shifts: multiShifts, accepted: [workers[1]] },
  ];

  const created = await prisma.$transaction(async (tx) => {
    // Aufraeumen: nur [TEST]-Jobs dieses Employers MIT Seed-Marker; abhaengige Daten gehen per onDelete: Cascade mit
    const oldJobs = await tx.job.findMany({
      where: { employerId: employer.id, title: { startsWith: PREFIX }, jobDescription: { contains: MARKER } },
      select: { id: true },
    });
    if (oldJobs.length) {
      const jobIds = oldJobs.map((j) => j.id);
      const convs = await tx.conversation.findMany({ where: { jobId: { in: jobIds } }, select: { id: true } });
      // UserReport hat nur eine lose conversationId (keine Relation) → sonst bleiben Waisen zurueck
      await tx.userReport.deleteMany({ where: { conversationId: { in: convs.map((c) => c.id) } } });
      await tx.job.deleteMany({ where: { id: { in: jobIds } } });
      console.log(`Replaced ${oldJobs.length} old test job(s).`);
    }

    const result = [];
    for (const spec of specs) {
      const data = buildJobData({
        title: PREFIX + spec.title, company, location: "Los Angeles, CA", lat: 34.0522, lng: -118.2437,
        category: "Hospitality", tags: ["Test"], payAmount: pay, shifts: spec.shifts, openSpots: 2,
        jobDescription: MARKER, tasks: ["Serve guests", "Set up and clean up"],
        dressCode: "Black shirt, dark trousers", experienceLevel: "Beginner", paymentMethod: "Same-day Pay", contractType: "Temporary",
      });
      const job = await tx.job.create({
        data: {
          ...data, status: "published", employerId: employer.id, isVerified: true,
          termsAcceptedAt: new Date(), platformFeePercent: platformFeePercent(), // wie beim echten Publish
        },
      });
      for (const w of spec.accepted) {
        const acceptedAt = new Date();
        const apply = await tx.apply.create({
          data: { userId: w.id, jobId: job.id, shiftIds: spec.shifts.map((x) => x.id), status: "accepted", respondedAt: acceptedAt, acceptedAt },
        });
        const conv = await tx.conversation.create({ data: { applyId: apply.id, jobId: job.id, workerId: w.id, employerId: employer.id } });
        // Wie beim echten Apply: System-Nachricht mit senderId = Worker
        await tx.message.create({
          data: {
            conversationId: conv.id, senderId: w.id, isSystem: true, isRead: true,
            text: `Your application for "${job.title}" has been submitted. The employer will review your profile and get back to you.`,
          },
        });
      }
      result.push({ job, spec });
    }
    return result;
  }, { timeout: 30_000 });

  console.log(`\nTest data created for employer ${employer.email} (workers: ${workers.map((w) => w.email).join(", ")})\n`);
  for (const { job, spec } of created) {
    console.log(`${job.title}\n  id:       ${job.id}\n  shifts:   ${spec.shifts.map((x) => `${x.id}: ${x.date} ${x.timeRange} (${TIME_ZONE}), ${x.startTimeISO} -> ${x.endTimeISO}`).join("\n            ")}\n  accepted: ${spec.accepted.map((w) => w.email).join(", ")}`);
  }
  console.log(`
Try in the app:
  - "[TEST] Past shift": as employer record attendance (attended / late / no-show), then as worker dispute a late/no-show,
    and test payment after shift end. Attendance is still open (auto "attended" after 48 h).
  - "[TEST] Starts soon": as ${workers[1].email} cancel the shift -> "late cancellation" warning (< 24 h before start).
  - "[TEST] Multi shift": as ${workers[1].email} cancel single shifts (first one < 24 h = late warning, the others not);
    cancelling the last remaining shift withdraws the application.
Note: no cron marks jobs "completed"; the past job stays "published" (attendance/payment still work after shift end).`);
  return 0;
}

main()
  .then((code) => { process.exitCode = code; })
  .catch((err) => { console.error(err); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
