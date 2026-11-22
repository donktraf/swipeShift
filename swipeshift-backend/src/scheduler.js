// src/scheduler.js
// Kleiner In-Process-Scheduler fuer verzoegerte Benachrichtigungen:
//   - Schicht-Erinnerung (Start der ersten anstehenden GEBUCHTEN Schicht in 0–24 h, einmal pro Bewerbung via reminderSentAt;
//     spaetere gebuchte Schichten derselben Bewerbung bekommen keine eigene Erinnerung — ein Marker pro Buchung)
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
const { nextBookedStart, bookedEnd } = require("./utils/shiftBooking");
const { collectPaged } = require("./utils/paged");
const { attendanceReminderWindow } = require("./utils/reliability");
const { isBlockedBetween } = require("./utils/safety");
const { describeBlockedUser } = require("./utils/blockedUsers");
const {
  shiftReminderWindow, paymentOpenWindow, pickUnreadMessageEmailTargets,
  UNREAD_EMAIL_DELAY_MS, UNREAD_EMAIL_MAX_AGE_MS, EMAIL_COOLDOWN_MS,
} = require("./utils/notifySchedule");

const INTERVAL_MS = 5 * 60 * 1000;
const BATCH = 200;
const SHIFT_REMINDER_LOOKBACK_MS = 30 * 24 * 3_600_000; // spaetere Schichten eines Mehrtages-Jobs
const MESSAGE_PAGE_SIZE = 500;
const MESSAGE_PAGES = 4;

async function runShiftReminders(now = new Date()) {
  const { from, to } = shiftReminderWindow(now);
  // Job.startTime = fruehester Start, Job.endTime = spaetestes Ende (ALLE Schichten). Die gebuchte Schicht kann spaeter
  // liegen → Rueckschau statt `gte: from`; bereits beendete Jobs (endTime < jetzt) sind raus. Pagination nach id,
  // die genaue Pruefung (naechste gebuchte Schicht im Fenster) im Speicher.
  const lookback = new Date(from.getTime() - SHIFT_REMINDER_LOOKBACK_MS);
  const candidates = await collectPaged({
    limit: BATCH, pageSize: BATCH,
    fetchPage: (cursor, take) => prisma.apply.findMany({
      where: {
        status: "accepted", reminderSentAt: null,
        job: {
          status: { in: ["published", "inProgress"] },
          startTime: { gte: lookback, lte: to },
          OR: [{ endTime: { gte: now } }, { endTime: null }],
        },
      },
      select: { id: true, userId: true, jobId: true, shiftIds: true, job: { select: { title: true, company: true, startTime: true, endTime: true, shifts: true, employerId: true } }, conversation: { select: { id: true } } },
      orderBy: { id: "asc" },
      take,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    }),
    accept: (a) => { const st = nextBookedStart(a.job, a.shiftIds, from); return !!st && st <= to; },
  });
  // Erste anstehende gebuchte Schicht im Fenster; baldigste zuerst
  const applies = candidates
    .map((a) => ({ ...a, shiftStart: nextBookedStart(a.job, a.shiftIds, from) }))
    .sort((x, y) => x.shiftStart - y.shiftStart);
  let sent = 0;
  for (const a of applies) {
    // Claim: nur eine Instanz gewinnt, und nur solange die Bewerbung noch angenommen ist
    const { count } = await prisma.apply.updateMany({
      where: { id: a.id, reminderSentAt: null, status: "accepted" },
      data: { reminderSentAt: now },
    });
    if (count !== 1) continue;
    if (a.job.employerId) {
      const blocks = await prisma.userBlock.findMany({
        where: { OR: [{ blockerId: a.userId, blockedId: a.job.employerId }, { blockerId: a.job.employerId, blockedId: a.userId }] },
        select: { blockerId: true, blockedId: true },
      });
      if (isBlockedBetween(blocks, a.userId, a.job.employerId)) continue;
    }
    await notify(a.userId, (user) => copy.shiftReminder({
      jobTitle: a.job.title, company: a.job.company, startTime: a.shiftStart,
      timeZone: user.timeZone, jobId: a.jobId, conversationId: a.conversation?.id,
    }));
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

async function runAll(now = new Date()) {
  for (const [name, fn] of [["shift reminders", runShiftReminders], ["unread message emails", runUnreadMessageEmails], ["payment open", runPaymentOpen], ["attendance reminders", runAttendanceReminders], ["auto attendance", runAutoAttendance]]) {
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

module.exports = { startScheduler, runAll, runAutoAttendance, runAttendanceReminders, runShiftReminders, runUnreadMessageEmails, runPaymentOpen, claimConversationEmail };
