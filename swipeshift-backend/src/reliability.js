// src/reliability.js
// DB-Teil der Zuverlaessigkeits-Funktion (Regeln und Rechenlogik: utils/reliability.js).
//   loadReliability        Zusammenfassung fuer mehrere Worker gebuendelt (1 Query)
//   recordEmployerAttendance  Employer erfasst attended/late/no_show (Compare-and-set)
//   runAutoAttendance      Scheduler: nach 48 h ohne Eintrag → "attended" (idempotenter Claim)

const { prisma } = require("./prisma");
const events = require("./notifyEvents");
const r = require("./utils/reliability");
const { bookedEnd } = require("./utils/shiftBooking");
const { collectPaged } = require("./utils/paged");

const BATCH = 200;
const ROW_SELECT = {
  userId: true, status: true, attendance: true, disputedAt: true, disputeResolvedAt: true,
  lateCancellation: true, cancelledAt: true, shiftIds: true,
  shiftCancellations: { select: { late: true, cancelledAt: true } }, // kurzfristige Teil-Absagen
  job: { select: { endTime: true, startTime: true, shifts: true } }, // Ende der GEBUCHTEN Schichten (utils/shiftBooking.js)
};

async function loadReliabilityRows(userIds, now = new Date(), windowDays = r.WINDOW_DAYS) {
  const ids = [...new Set((userIds || []).filter(Boolean))];
  if (!ids.length) return [];
  return prisma.apply.findMany({
    where: { userId: { in: ids }, ...r.reliabilityRowsWhere(now, windowDays) },
    select: ROW_SELECT,
  });
}

// → Map(userId → summary); Worker ohne Zeilen bekommen die "New"-Zusammenfassung
async function loadReliability(userIds, now = new Date(), windowDays = r.WINDOW_DAYS) {
  const ids = [...new Set((userIds || []).filter(Boolean))];
  const rows = await loadReliabilityRows(ids, now, windowDays);
  const byUser = new Map();
  for (const row of rows) {
    if (!byUser.has(row.userId)) byUser.set(row.userId, []);
    byUser.get(row.userId).push(row);
  }
  return new Map(ids.map((id) => [id, r.summarizeReliability(byUser.get(id) ?? [], now, { windowDays })]));
}

// → { ok:true, attendance, changed } | { ok:false, status, code?, error }
async function recordEmployerAttendance({ applyId, employerId, value, now = new Date() }) {
  const attendance = r.normalizeAttendance(value);
  if (!attendance) return { ok: false, status: 400, error: "status must be attended, late or no_show." };

  const apply = await prisma.apply.findUnique({
    where: { id: applyId },
    include: { job: { select: { employerId: true, status: true, startTime: true, endTime: true, shifts: true } } },
  });
  if (!apply) return { ok: false, status: 404, error: "Application not found" };
  if (apply.job.employerId !== employerId) return { ok: false, status: 403, error: "Forbidden" };
  if (apply.status !== "accepted") return { ok: false, status: 400, error: "Only accepted workers can be marked." };

  const state = r.attendanceState(apply, apply.job, now);
  if (!state.ended) return { ok: false, status: 409, code: "SHIFT_NOT_ENDED", error: "You can record attendance once the shift has ended." };
  if (apply.disputeResolvedAt) return { ok: false, status: 409, code: "DISPUTE_RESOLVED", error: "This entry was reviewed by our team and can't be changed." };
  if (apply.disputedAt) return { ok: false, status: 409, code: "DISPUTED", error: "The worker disputed this entry. It is now being reviewed." };
  if (!state.canRecord) return { ok: false, status: 409, code: "WINDOW_CLOSED", error: "The 48-hour window to record attendance has ended." };
  if (apply.attendance === attendance) return { ok: true, attendance, changed: false };

  // Compare-and-set: nur, wenn sich seit dem Lesen nichts geaendert hat (kein Einspruch, kein paralleler Eintrag)
  const { count } = await prisma.apply.updateMany({
    where: { id: applyId, status: "accepted", attendance: apply.attendance, disputedAt: null },
    data: { attendance, attendanceSetAt: now, attendanceSource: "employer" },
  });
  if (count !== 1) return { ok: false, status: 409, code: "CHANGED", error: "This entry just changed. Please reload and try again." };

  // fire-and-forget; die Erinnerung wird pro Bewerbung nur einmal verschickt (Marker noShowNotifiedAt)
  if (attendance === "no_show") events.noShowRecorded(applyId); // Claim (noShowNotifiedAt) in notifyEvents → hoechstens einmal
  return { ok: true, attendance, changed: true };
}

// Nach 48 h ohne Eintrag zaehlt die Schicht als "attended" — gemessen am Ende der GEBUCHTEN Schichten der Bewerbung.
// Nur Schichten der letzten 12 Monate. SQL grob (positiv): Job.endTime = spaetestes Schichtende >= oldest, Job.startTime
// (= fruehester Start) < cutoff; das genaue Fenster prueft attendanceState pro Bewerbung im Speicher.
async function runAutoAttendance(now = new Date()) {
  const cutoff = new Date(now.getTime() - r.AUTO_ATTEND_HOURS * 3_600_000);
  const oldest = new Date(now.getTime() - r.WINDOW_DAYS * 24 * 3_600_000);
  const rows = await collectPaged({
    limit: BATCH, pageSize: BATCH,
    fetchPage: (cursor, take) => prisma.apply.findMany({
      where: {
        status: "accepted", attendance: null,
        job: {
          status: { in: ["published", "inProgress", "completed"] },
          endTime: { gte: oldest },
          OR: [{ startTime: { lt: cutoff } }, { startTime: null }],
        },
      },
      select: { id: true, status: true, attendance: true, disputedAt: true, shiftIds: true, job: { select: { status: true, startTime: true, endTime: true, shifts: true } } },
      orderBy: { id: "asc" },
      take,
      ...(cursor ? { cursor: { id: cursor }, skip: 1 } : {}),
    }),
    accept: (a) => {
      const end = bookedEnd(a.job, a.shiftIds);
      return !!end && end.getTime() >= oldest.getTime() && r.attendanceState(a, a.job, now).autoDue;
    },
  });
  let claimed = 0;
  for (const row of rows) {
    const { count } = await prisma.apply.updateMany({
      where: { id: row.id, status: "accepted", attendance: null },
      data: { attendance: "attended", attendanceSetAt: now, attendanceSource: "auto" },
    });
    claimed += count;
  }
  return claimed;
}

module.exports = { loadReliability, loadReliabilityRows, recordEmployerAttendance, runAutoAttendance };
