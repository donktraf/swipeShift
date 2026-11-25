// src/accountCleanup.js — offene Jobs eines Arbeitgebers stornieren (Konto-Loeschung / Aufraeum-Skript)
const { ACCOUNT_CLOSED_REASON, ACCOUNT_CLOSED_CHAT_NOTE, OPEN_JOB_STATUSES } = require("./utils/accountCleanup");

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

// Job anlegen/veroeffentlichen serialisiert mit DELETE /auth/me: die User-Zeile wird mit FOR SHARE gesperrt (DELETE
// nimmt FOR UPDATE). Existiert der User nicht mehr → { gone: true }, fn laeuft dann nicht. Sonst { gone: false, value }.
async function withEmployerShareLock(prisma, userId, fn) {
  return prisma.$transaction(async (tx) => {
    const rows = await tx.$queryRaw`SELECT id FROM "User" WHERE id = ${userId} FOR SHARE`;
    if (!rows.length) return { gone: true };
    return { gone: false, value: await fn(tx) };
  });
}

module.exports = { cancelOpenJobs, withEmployerShareLock };
