// src/notifyEvents.js
// Ereignisse → Benachrichtigungen. Jede Funktion laedt die noetigen Daten, prueft Blocks und ruft notify().
// ALLE Funktionen sind fire-and-forget: sie werfen nie und werden an Aufrufstellen nicht awaited
// (nur der Scheduler wartet darauf). Fehler werden geloggt.

const { prisma } = require("./prisma.js");
const { notify } = require("./notify");
const copy = require("./utils/notificationCopy");
const { isBlockedBetween } = require("./utils/safety");
const { describeBlockedUser } = require("./utils/blockedUsers");

function safe(label, fn) {
  return async (...args) => {
    try {
      return await fn(...args);
    } catch (err) {
      console.error(`notifyEvents.${label} failed:`, err);
      return null;
    }
  };
}

async function blockedBetween(a, b) {
  if (!a || !b) return false;
  const blocks = await prisma.userBlock.findMany({
    where: { OR: [{ blockerId: a, blockedId: b }, { blockerId: b, blockedId: a }] },
    select: { blockerId: true, blockedId: true },
  });
  return isBlockedBetween(blocks, a, b);
}

// Anzeigename: Employer = Firmenname, Worker = Vor-/Nachname
async function displayNameOf(userId, fallback = null) {
  if (!userId) return fallback;
  const u = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, role: true, firstName: true, lastName: true, employer: { select: { companyName: true } } },
  });
  if (!u) return fallback;
  const name = describeBlockedUser(u, u.employer, null).name;
  return name === "User" ? fallback : name;
}

// Worker: Bewerbung angenommen/abgelehnt
const applicationDecided = safe("applicationDecided", async (applyId, decision) => {
  const apply = await prisma.apply.findUnique({
    where: { id: applyId },
    select: { userId: true, jobId: true, job: { select: { title: true, company: true, employerId: true } }, conversation: { select: { id: true } } },
  });
  if (!apply) return;
  if (await blockedBetween(apply.job.employerId, apply.userId)) return;
  const args = { jobTitle: apply.job.title, company: apply.job.company, jobId: apply.jobId, conversationId: apply.conversation?.id };
  await notify(apply.userId, decision === "accepted" ? copy.applicationAccepted(args) : copy.applicationDeclined(args));
});

// Worker: Job vom Employer storniert (angenommene + offene Bewerbungen)
const jobCancelled = safe("jobCancelled", async (jobId) => {
  const job = await prisma.job.findUnique({
    where: { id: jobId },
    select: { id: true, title: true, company: true, employerId: true, cancellationReason: true, status: true },
  });
  if (!job || job.status !== "cancelled") return;
  const applies = await prisma.apply.findMany({
    where: { jobId, status: { in: ["accepted", "pending"] } },
    select: { userId: true },
  });
  for (const a of applies) {
    if (await blockedBetween(job.employerId, a.userId)) continue;
    await notify(a.userId, copy.jobCancelled({ jobTitle: job.title, company: job.company, reason: job.cancellationReason, jobId }));
  }
});

// Employer: neue Bewerbung bzw. Instant Match gebucht
const workerApplied = safe("workerApplied", async ({ employerId, workerId, jobId, jobTitle, autoAccepted }) => {
  if (!employerId) return;
  if (await blockedBetween(employerId, workerId)) return;
  const workerName = await displayNameOf(workerId, "A worker");
  const args = { workerName, jobTitle, jobId };
  await notify(employerId, autoAccepted ? copy.instantMatchBooked(args) : copy.newApplication(args));
});

// Neue Chat-Nachricht (keine System-Nachricht) an die Gegenseite — nur Push; die Ungelesen-Mail macht der Scheduler
const newChatMessage = safe("newChatMessage", async ({ conversationId, senderId, recipientId, text }) => {
  if (!recipientId || recipientId === senderId) return;
  if (await blockedBetween(senderId, recipientId)) return;
  const conv = await prisma.conversation.findUnique({ where: { id: conversationId }, select: { job: { select: { title: true } } } });
  const senderName = await displayNameOf(senderId, "New message");
  await notify(recipientId, {
    category: "messages",
    push: copy.newMessagePush({ senderName, jobTitle: conv?.job?.title, text, conversationId }),
  });
});

// Worker: als bezahlt markiert (applyIds = nur frisch bezahlte)
const paymentReceived = safe("paymentReceived", async (applyIds) => {
  if (!applyIds?.length) return;
  const applies = await prisma.apply.findMany({
    where: { id: { in: applyIds } },
    select: { userId: true, jobId: true, job: { select: { title: true, company: true, employerId: true } } },
  });
  for (const a of applies) {
    if (await blockedBetween(a.job.employerId, a.userId)) continue;
    await notify(a.userId, copy.paymentReceived({ jobTitle: a.job.title, company: a.job.company, jobId: a.jobId }));
  }
});

// Employer: Job vorbei/abgeschlossen, unbezahlte Worker. Einmal pro Job (Claim ueber Job.paymentReminderSentAt;
// Raw-SQL, damit @updatedAt unberuehrt bleibt — PATCH /jobs/:id/status nutzt es als Optimistic Lock).
const paymentOpen = safe("paymentOpen", async (jobId) => {
  const claimed = await prisma.$executeRaw`UPDATE "Job" SET "paymentReminderSentAt" = ${new Date()} WHERE "id" = ${jobId} AND "paymentReminderSentAt" IS NULL`;
  if (claimed !== 1) return;
  const job = await prisma.job.findUnique({ where: { id: jobId }, select: { id: true, title: true, employerId: true, status: true } });
  if (!job?.employerId || job.status === "cancelled" || job.status === "draft") return;
  const unpaidCount = await prisma.apply.count({ where: { jobId, status: "accepted", isPaid: false } });
  if (unpaidCount === 0) return;
  await notify(job.employerId, copy.paymentOpen({ jobTitle: job.title, unpaidCount, jobId }));
});

// Neue, veroeffentlichte Bewertung (Employer→Worker oder Worker→Employer)
const reviewReceived = safe("reviewReceived", async ({ fromUserId, toUserId, jobId }) => {
  if (!toUserId || !fromUserId) return;
  if (await blockedBetween(fromUserId, toUserId)) return;
  const [fromName, job] = await Promise.all([
    displayNameOf(fromUserId, "Someone"),
    prisma.job.findUnique({ where: { id: jobId }, select: { title: true } }),
  ]);
  await notify(toUserId, copy.reviewReceived({ fromName, jobTitle: job?.title, jobId }));
});

const accountPauseChanged = safe("accountPauseChanged", async (userId, paused) => {
  await notify(userId, paused ? copy.accountPaused() : copy.accountResumed());
});

module.exports = {
  applicationDecided, jobCancelled, workerApplied, newChatMessage,
  paymentReceived, paymentOpen, reviewReceived, accountPauseChanged,
};
