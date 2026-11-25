// src/accountCleanup.js — offene Jobs eines Arbeitgebers stornieren (Konto-Loeschung / Aufraeum-Skript)
const {
  ACCOUNT_CLOSED_REASON, ACCOUNT_CLOSED_CHAT_NOTE, OPEN_JOB_STATUSES, FUTURE_SHIFTS_CHAT_NOTE, COMPLETED_CHAT_NOTE, FUTURE_SHIFTS_REASON,
  unpaidByJob, planJobClosure,
} = require("./utils/accountCleanup");

// Wie PATCH /jobs/:id/status → cancelled (Status + Grund; Benachrichtigung macht events.jobCancelled nach dem Commit),
// zusaetzlich: Chats der Jobs schliessen (Gegenseite existiert nicht mehr) + Systemnachricht.
// `where` waehlt die Jobs (z.B. { employerId } oder { id: { in } }); tx = Prisma-Transaktionsclient.
// Rueckgabe: IDs der stornierten Jobs.
async function cancelOpenJobs(tx, where, { note = true } = {}) {
  const jobs = await tx.job.findMany({ where: { ...where, status: { in: OPEN_JOB_STATUSES } }, select: { id: true } });
  if (!jobs.length) return [];
  const candidates = jobs.map((j) => j.id);
  await tx.job.updateMany({
    where: { id: { in: candidates }, status: { in: OPEN_JOB_STATUSES } },
    data: { status: "cancelled", cancellationReason: ACCOUNT_CLOSED_REASON },
  });
  // Tatsaechlich von uns geaendert (parallel anders umgestellte Jobs zaehlen nicht)
  const ids = (await tx.job.findMany({
    where: { id: { in: candidates }, status: "cancelled", cancellationReason: ACCOUNT_CLOSED_REASON }, select: { id: true },
  })).map((j) => j.id);
  if (!ids.length) return [];
  const convs = await tx.conversation.findMany({ where: { jobId: { in: ids }, status: "active" }, select: { id: true, employerId: true } });
  if (convs.length) {
    await tx.conversation.updateMany({ where: { id: { in: convs.map((c) => c.id) } }, data: { status: "cancelled" } });
    if (note) {
      await tx.message.createMany({
        data: convs.map((c) => ({
          conversationId: c.id, senderId: c.employerId ?? "system", text: ACCOUNT_CLOSED_CHAT_NOTE, isSystem: true, isRead: false,
        })),
      });
    }
  }
  return ids;
}

const JOB_FIELDS = { id: true, title: true, company: true, status: true, shifts: true, startTime: true, endTime: true };

// Unbezahlte Posten des Arbeitgebers (beendete Schichten, angenommen, nicht bezahlt) → [{ jobId, title, unpaidWorkers }]
async function findUnpaidWorkers(tx, employerId, now = new Date()) {
  const jobs = await tx.job.findMany({
    where: { employerId, status: { not: "cancelled" }, applies: { some: { status: "accepted", isPaid: false } } },
    select: { ...JOB_FIELDS, applies: { where: { status: "accepted", isPaid: false }, select: { id: true, status: true, isPaid: true, shiftIds: true, attendance: true, disputedAt: true, disputeResolvedAt: true } } },
  });
  return unpaidByJob(jobs, now).map(({ jobId, title, unpaidWorkers }) => ({ id: jobId, title, unpaidWorkers }));
}

// Konto-Loeschung (alles bezahlt): offene Jobs mit beendeter gebuchter Schicht → completed (Chats completed, zukuenftige
// Schichten entfallen), alle anderen → cancelled (cancelOpenJobs). Rueckgabe: { cancelledIds, completedIds, notices }
// notices = Worker, deren (zukuenftige) Schichten entfallen sind → events.accountClosedShifts nach dem Commit.
async function closeJobsForDeletedEmployer(tx, employerId, now = new Date()) {
  const jobs = await tx.job.findMany({
    where: { employerId, status: { in: OPEN_JOB_STATUSES } },
    select: { ...JOB_FIELDS, applies: { where: { status: { in: ["accepted", "pending"] } }, select: { id: true, userId: true, status: true, shiftIds: true } } },
  });
  const toCancel = [], completedIds = [], notices = [];
  for (const job of jobs) {
    const plan = planJobClosure(job, job.applies, now);
    if (plan.finalStatus === "cancelled") { toCancel.push(job.id); continue; }
    const { count } = await tx.job.updateMany({ where: { id: job.id, status: { in: OPEN_JOB_STATUSES } }, data: { status: "completed" } });
    if (!count) continue;
    completedIds.push(job.id);
    const byApply = new Map(plan.applyPlans.map((p) => [p.applyId, p]));
    const declined = plan.applyPlans.filter((p) => p.action === "decline").map((p) => p.applyId);
    if (declined.length) await tx.apply.updateMany({ where: { id: { in: declined } }, data: { status: "declined", cancelReason: FUTURE_SHIFTS_REASON } });
    for (const p of plan.applyPlans) {
      if (p.action === "trim") await tx.apply.update({ where: { id: p.applyId }, data: { shiftIds: p.shiftIds } });
      if (p.notify) notices.push({ userId: p.userId, jobId: job.id, jobTitle: job.title, company: job.company, kind: p.kind });
    }
    const convs = await tx.conversation.findMany({ where: { jobId: job.id, status: "active" }, select: { id: true, applyId: true, employerId: true } });
    for (const c of convs) {
      const p = byApply.get(c.applyId);
      const gone = p?.action === "decline";
      await tx.conversation.update({ where: { id: c.id }, data: { status: gone ? "cancelled" : "completed" } });
      await tx.message.create({ data: {
        conversationId: c.id, senderId: c.employerId ?? "system", isSystem: true, isRead: false,
        text: p?.action === "keep" || !p ? COMPLETED_CHAT_NOTE : FUTURE_SHIFTS_CHAT_NOTE,
      } });
    }
  }
  const cancelledIds = toCancel.length ? await cancelOpenJobs(tx, { id: { in: toCancel } }) : [];
  return { cancelledIds, completedIds, notices };
}

// Job anlegen/veroeffentlichen serialisiert mit DELETE /auth/me: die User-Zeile wird mit FOR SHARE gesperrt (DELETE
// nimmt FOR UPDATE). Existiert der User nicht mehr → { gone: true }, fn laeuft dann nicht. Sonst { gone: false, value }.
async function withEmployerShareLock(prisma, userId, fn) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId} FOR SHARE`;
    if (!rows.length) return { gone: true };
    return { gone: false, value: await fn(tx) };
  });
}

module.exports = { cancelOpenJobs, withEmployerShareLock, findUnpaidWorkers, closeJobsForDeletedEmployer };
