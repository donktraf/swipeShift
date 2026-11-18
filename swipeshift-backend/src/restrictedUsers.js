// src/restrictedUsers.js
// IDs aktuell gesperrter/gebannter Employer — deren Jobs sind fuer Worker nicht sichtbar (Firmenprofil, Gespeichert, Detail).
const { prisma } = require("./prisma.js");
const { restrictedWhere } = require("./utils/moderation");

async function restrictedEmployerIds(now = new Date()) {
  const rows = await prisma.user.findMany({
    where: { role: "employer", ...restrictedWhere(now) },
    select: { id: true },
  });
  return new Set(rows.map((r) => r.id));
}

module.exports = { restrictedEmployerIds };
