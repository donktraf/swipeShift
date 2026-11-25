// src/scheduler.js
// Kleiner In-Process-Scheduler fuer verzoegerte Benachrichtigungen:
//   - Schicht-Erinnerung (E-Mail, "Job Activity"): je GEBUCHTER Schicht 24 h und 2 h vorher, jeweils genau einmal
//     (ShiftReminder, Insert = Claim; Fenster/Altbestand-Regel in utils/notifySchedule.dueShiftReminders)
//   - Ungelesen-Mail (Chat-Nachricht nach 15 min ungelesen, max. 1/h pro Konversation+Empfaenger)
//   - "Payment open" (Job vorbei, unbezahlte Worker, einmal pro Job)
//   - Auto-Anwesenheit (48 h nach Schichtende ohne Employer-Eintrag → "attended", Claim per bedingtem Update)
// Mehrere Server-Instanzen sind sicher: vor jedem Versand wird ein DB-Marker per bedingtem Update
// beansprucht (nur der Gewinner sendet). Deaktiviert bei NODE_ENV=test.

const { prisma } = require("./prisma.js");
const { notify } = require("./notify");
const copy = require("./utils/notificationCopy");
const events = require("./notifyEvents");
const { runAutoAttendance } = require("./reliability");
const { purgeExpiredTombstones } = require("./moderation");
const { sweepOrphanUploads } = require("./uploadCleanup");
const { purgeOldSessions, purgeExpiredTokens, purgeOldReports } = require("./retention");
const { bookedEnd } = require("./utils/shiftBooking");
const { collectPaged } = require("./utils/paged");
const { attendanceReminderWindow } = require("./utils/reliability");
const { isBlockedBetween } = require("./utils/safety");
const { describeBlockedUser } = require("./utils/blockedUsers");
const {
  shiftReminderWindow, dueShiftReminders, paymentOpenWindow, pickUnreadMessageEmailTargets,
  UNREAD_EMAIL_DELAY_MS, UNREAD_EMAIL_MAX_AGE_MS, EMAIL_COOLDOWN_MS,
} = require("./utils/notifySchedule");

const INTERVAL_MS = 5 * 60 * 1000;
const BATCH = 200;
const MESSAGE_PAGE_SIZE = 500;
const MESSAGE_PAGES = 4;

// Fenster/Regeln: utils/notifySchedule.dueShiftReminders (24 h und 2 h vor JEDER gebuchten Schicht, je einmal).
// Bewusste Randfaelle:
//  - Wird eine Schicht nach einem gesendeten Reminder umgeplant (neue Zeit), gibt es dafuer KEINEN neuen Reminder
//    (der Marker haengt an Bewerbung+Schicht+Art).
//  - Wird ein Job weniger als 2 h vor Start angenommen/neu gestartet, kommt nur der 2h-Reminder.
//  - Versandfehler (Mail gewollt, sendMail warf): Claim wird zurueckgenommen → Retry im naechsten Tick, solange das
//    Fenster offen ist. Ist die Einstellung aus, bleibt der Claim (nichts zu wiederholen).
async function runShiftReminders(now = new Date()) {
  const { to } = shiftReminderWindow(now);
  // Job.startTime = fruehester Start, Job.endTime = spaetestes Ende ueber ALLE Schichten (spannt sie also auf). Eine
  // Schicht mit Start in (now, now+24h] gehoert damit immer zu einem Job mit startTime <= now+24h und endTime >= now;
  // mehr braucht der SQL-Filter nicht (kein pauschaler Lookback). Jobs ohne endTime (Altbestand) bleiben drin.
  // Pagination nach id, die genaue Pruefung (faellige Schichten, noch nicht gesendet) im Speicher.
  const candidates = await collectPaged({
    limit: BATCH, pageSize: BATCH,
    onMaxPages: () => console.warn("scheduler: shift reminders hit the page limit; some applies are deferred to the next tick"),
    fetchPage: (cursor, take) => prisma.apply.findMany({
      where: {
        status: "accepted",
        job: {
          status: { in: ["published", "inProgress"] },
          startTime: { lte: to },
          OR: [{ endTime: { gte: now } }, { endTime: null }],
        },
      },
      select: {
        id: true, userId: true, jobId: true, shiftIds: true, reminderSentAt: true,
        job: { select: { title: true, company: true, startTime: true, endTime: true, shifts: true, employerId: true } },
        conversation: { select: { id: true } },
        shiftReminders: { select: { shiftId: true, kind: true } },
      },
      orderBy: { id: "asc" },
      take,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    }),
    accept: (a) => {
      a.due = dueShiftReminders({ job: a.job, shiftIds: a.shiftIds, sent: a.shiftReminders, legacyReminderSentAt: a.reminderSentAt, now });
      return a.due.length > 0;
    },
  });
  const work = candidates.flatMap((a) => a.due.map((d) => ({ a, d }))).sort((x, y) => x.d.startMs - y.d.startMs);
  const blockedCache = new Map();
  let sent = 0;
  for (const { a, d } of work) {
    if (a.job.employerId) {
      if (!blockedCache.has(a.id)) {
        const blocks = await prisma.userBlock.findMany({
          where: { OR: [{ blockerId: a.userId, blockedId: a.job.employerId }, { blockerId: a.job.employerId, blockedId: a.userId }] },
          select: { blockerId: true, blockedId: true },
        });
        blockedCache.set(a.id, isBlockedBetween(blocks, a.userId, a.job.employerId));
      }
      if (blockedCache.get(a.id)) continue;
    }
    // Bewerbung/Schicht seit dem Laden noch gueltig? (Storno/Widerruf zwischen Query und Versand)
    const fresh = await prisma.apply.findUnique({ where: { id: a.id }, select: { status: true, shiftIds: true } });
    if (!fresh || fresh.status !== "accepted") continue;
    if (fresh.shiftIds.length && !fresh.shiftIds.includes(d.shiftId)) continue;
    // Claim = Insert; Unique-Konflikt → andere Instanz (oder Tick) war schneller
    let claimId;
    try {
      claimId = (await prisma.shiftReminder.create({ data: { applyId: a.id, shiftId: d.shiftId, kind: d.kind, sentAt: now } })).id;
    } catch (err) {
      if (err?.code !== "P2002") console.error("scheduler: shift reminder claim failed:", err);
      continue;
    }
    const result = await notify(a.userId, (user) => copy.shiftReminder({
      jobTitle: a.job.title, company: a.job.company, startTime: new Date(d.startMs), kind: d.kind, timeRange: d.timeRange,
      timeZone: user.timeZone, jobId: a.jobId, conversationId: a.conversation?.id, now,
    }));
    if (result?.attempted && result?.failed) {
      await prisma.shiftReminder.deleteMany({ where: { id: claimId } }).catch((err) => console.error("scheduler: shift reminder claim rollback failed:", err));
      continue;
    }
    sent += 1;
  }
  return sent;
}

// Spaltenname nur aus dieser Whitelist (Raw-SQL; kein @updatedAt-Touch der Conversation)
const EMAIL_COLUMNS = { worker: "workerEmailNotifiedAt", employer: "employerEmailNotifiedAt" };

async function claimConversationEmail(conversationId, role, now) {
  const column = EMAIL_COLUMNS[role];
  if (!column) return false;
  const boundary = new Date(now.getTime() - EMAIL_COOLDOWN_MS);
  const count = await prisma.$executeRawUnsafe(
    `UPDATE "Conversation" SET "${column}" = $1 WHERE "id" = $2 AND ("${column}" IS NULL OR "${column}" <= $3)`,
    now, conversationId, boundary
  );
  return count === 1;
}

async function runUnreadMessageEmails(now = new Date()) {
  // Neueste zuerst + Cursor-Seiten (max. MESSAGE_PAGES x 500): ein Berg alter, bereits behandelter Nachrichten
  // kann neuere nicht aushungern. Idempotenz kommt allein aus dem Claim pro Konversation+Empfaenger.
  const where = {
    isSystem: false, isRead: false,
    createdAt: { gt: new Date(now.getTime() - UNREAD_EMAIL_MAX_AGE_MS), lte: new Date(now.getTime() - UNREAD_EMAIL_DELAY_MS) },
  };
  const select = {
    id: true, senderId: true, isSystem: true, isRead: true, createdAt: true,
    conversation: { select: {
      id: true, workerId: true, employerId: true, workerLastReadAt: true, employerLastReadAt: true,
      workerEmailNotifiedAt: true, employerEmailNotifiedAt: true, job: { select: { title: true } },
    } },
  };
  const messages = [];
  let cursor = null;
  for (let page = 0; page < MESSAGE_PAGES; page++) {
    const rows = await prisma.message.findMany({
      where, select, orderBy: [{ createdAt: "desc" }, { id: "desc" }], take: MESSAGE_PAGE_SIZE,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    });
    messages.push(...rows);
    if (rows.length < MESSAGE_PAGE_SIZE) break;
    cursor = rows[rows.length - 1].id;
  }
  const targets = pickUnreadMessageEmailTargets(messages, now);
  let sent = 0;
  for (const t of targets) {
    const blocks = await prisma.userBlock.findMany({
      where: { OR: [{ blockerId: t.senderId, blockedId: t.recipientId }, { blockerId: t.recipientId, blockedId: t.senderId }] },
      select: { blockerId: true, blockedId: true },
    });
    if (isBlockedBetween(blocks, t.senderId, t.recipientId)) continue;
    if (!(await claimConversationEmail(t.conversationId, t.recipientRole, now))) continue;
    const sender = await prisma.user.findUnique({
      where: { id: t.senderId },
      select: { role: true, firstName: true, lastName: true, employer: { select: { companyName: true } } },
    });
    const senderName = sender ? describeBlockedUser(sender, sender.employer, null).name : "Someone";
    // Nur E-Mail (Push kam sofort beim Eintreffen); Text der Nachricht ist bewusst NICHT enthalten
    await notify(t.recipientId, { category: "messages", email: copy.unreadMessageEmail({ senderName, jobTitle: t.jobTitle }) });
    sent += 1;
  }
  return sent;
}

// Jobs mit mindestens einer passenden Bewerbung, deren GEBUCHTES Schichtende im Fenster (endedAfter, endedBefore) liegt.
// SQL grob und positiv: Job.endTime (spaetestes Ende) > endedAfter, Job.startTime (fruehester Start) < endedBefore;
// pro Bewerbung im Speicher: bookedEnd im Fenster. → [{ id, eligible }] (eligible = Anzahl passender Bewerbungen)
async function jobsWithBookedEndIn({ endedAfter, endedBefore, applyWhere, claimField }) {
  const afterMs = endedAfter.getTime(), beforeMs = endedBefore.getTime();
  const found = await collectPaged({
    limit: BATCH, pageSize: BATCH,
    fetchPage: (cursor, take) => prisma.job.findMany({
      where: {
        [claimField]: null, employerId: { not: null },
        status: { in: ["published", "inProgress", "completed"] },
        endTime: { gt: endedAfter },
        OR: [{ startTime: { lt: endedBefore } }, { startTime: null }],
        applies: { some: applyWhere },
      },
      select: { id: true, startTime: true, endTime: true, shifts: true, applies: { where: applyWhere, select: { shiftIds: true } } },
      orderBy: { id: "asc" },
      take,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    }),
    accept: (j) => { j.eligible = j.applies.filter((a) => { const e = bookedEnd(j, a.shiftIds); return e && e.getTime() > afterMs && e.getTime() < beforeMs; }).length; return j.eligible > 0; },
  });
  return found.map((j) => ({ id: j.id, eligible: j.eligible }));
}

async function runPaymentOpen(now = new Date()) {
  const { endedAfter, endedBefore } = paymentOpenWindow(now);
  const jobs = await jobsWithBookedEndIn({
    endedAfter, endedBefore, claimField: "paymentReminderSentAt",
    applyWhere: { status: "accepted", isPaid: false },
  });
  for (const j of jobs) await events.paymentOpen(j.id, { unpaidCount: j.eligible });
  return jobs.length;
}

// ~24 h nach Schichtende (der GEBUCHTEN Schichten): Employer erinnern, wenn die Anwesenheit noch fehlt (einmal pro Job)
async function runAttendanceReminders(now = new Date()) {
  const { endedAfter, endedBefore } = attendanceReminderWindow(now);
  const jobs = await jobsWithBookedEndIn({
    endedAfter, endedBefore, claimField: "attendanceReminderSentAt",
    applyWhere: { status: "accepted", attendance: null },
  });
  for (const j of jobs) await events.attendanceReminder(j.id, { pendingCount: j.eligible });
  return jobs.length;
}

// Tombstone-Retention: hoechstens alle 24 h (erster Tick nach dem Start laeuft sofort mit)
const PURGE_INTERVAL_MS = 24 * 3_600_000;
let lastPurgeAt = 0;
async function runTombstonePurge(now = new Date()) {
  if (now.getTime() - lastPurgeAt < PURGE_INTERVAL_MS) return 0;
  const n = await purgeExpiredTombstones(now);
  lastPurgeAt = now.getTime(); // nur nach Erfolg → bei Fehler naechster Tick erneut
  return n;
}

// Weitere Retention-Laeufe (Sessions/Tokens, Meldungen/Moderation): je hoechstens alle 24 h, Fehler → Retry im naechsten Tick
const lastRetentionAt = new Map();
async function runDailyPurge(key, fn, now = new Date()) {
  if (now.getTime() - (lastRetentionAt.get(key) ?? 0) < PURGE_INTERVAL_MS) return 0;
  const n = await fn(now);
  lastRetentionAt.set(key, now.getTime());
  return n;
}
const runSessionTokenPurge = (now = new Date()) => runDailyPurge("sessions-tokens", async (t) => [await purgeOldSessions(t), await purgeExpiredTokens(t)], now);
const runUploadSweep = (now = new Date()) => runDailyPurge("upload-sweep", sweepOrphanUploads, now);
const runReportPurge = (now = new Date()) => runDailyPurge("reports", purgeOldReports, now);

async function runAll(now = new Date()) {
  for (const [name, fn] of [["tombstone purge", runTombstonePurge], ["session/token purge", runSessionTokenPurge], ["report purge", runReportPurge], ["upload sweep", runUploadSweep], ["shift reminders", runShiftReminders], ["unread message emails", runUnreadMessageEmails], ["payment open", runPaymentOpen], ["attendance reminders", runAttendanceReminders], ["auto attendance", runAutoAttendance]]) {
    try {
      await fn(now);
    } catch (err) {
      console.error(`scheduler: ${name} failed:`, err);
    }
  }
}

let timer = null;
let running = false;

function startScheduler() {
  if (process.env.NODE_ENV === "test" || timer) return null;
  const tick = async () => {
    if (running) return; // kein Ueberlappen
    running = true;
    try { await runAll(); } finally { running = false; }
  };
  timer = setInterval(tick, INTERVAL_MS);
  timer.unref();
  setTimeout(tick, 30_000).unref(); // erster Lauf kurz nach dem Start
  return timer;
}

module.exports = { runUploadSweep, runSessionTokenPurge, runReportPurge, startScheduler, runAll, runAutoAttendance, runAttendanceReminders, runShiftReminders, runUnreadMessageEmails, runPaymentOpen, claimConversationEmail };
