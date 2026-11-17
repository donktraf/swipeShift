// src/applicantSummaries.js
// Laedt Bewertungen/Jobzahlen/Profilfelder fuer MEHRERE Worker gebuendelt (3 Queries, kein N+1)
// und bildet je Worker die Zusammenfassung aus utils/applicantSummary.js.

const { prisma } = require("./prisma");
const { groupBy, summarizeApplicant } = require("./utils/applicantSummary");

// → Map(userId → summary)
async function loadApplicantSummaries(userIds, now = new Date()) {
  const ids = [...new Set((userIds || []).filter(Boolean))];
  if (!ids.length) return new Map();

  const [workers, reviews, applies] = await Promise.all([
    prisma.worker.findMany({
      where: { userId: { in: ids } },
      select: { userId: true, dateOfBirth: true, experience: true, skills: true, availability: true, availableTimes: true },
    }),
    prisma.review.findMany({
      where: { workerId: { in: ids } },
      select: { workerId: true, communication: true, teamwork: true, reliability: true, underPressure: true, workQuality: true, topWorker: true },
    }),
    prisma.apply.findMany({
      where: { userId: { in: ids }, status: "accepted" },
      select: { userId: true, status: true, isPaid: true, job: { select: { category: true, endTime: true, status: true, cancellationReason: true } } },
    }),
  ]);

  const workerById = new Map(workers.map((w) => [w.userId, w]));
  const reviewsBy = groupBy(reviews, "workerId");
  const appliesBy = groupBy(applies, "userId");

  return new Map(ids.map((id) => [id, summarizeApplicant({
    worker: workerById.get(id) ?? null,
    reviews: reviewsBy.get(id) ?? [],
    applies: appliesBy.get(id) ?? [],
    now,
  })]));
}

module.exports = { loadApplicantSummaries };
