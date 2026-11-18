// src/pushDevices.js
// DB-Helper fuer registrierte APNs-Geraete (PushDevice).

const { prisma } = require("./prisma.js");

// Beim Abmelden/Widerruf einer Session: deren Geraete loeschen. Wirft nie (Aufraeumen darf Requests nicht kippen).
async function removeDevicesForSessions(where) {
  try {
    const { count } = await prisma.pushDevice.deleteMany({ where });
    return count;
  } catch (err) {
    console.error("removeDevicesForSessions failed:", err);
    return 0;
  }
}

// Geraete eines Users, deren Session noch lebt (Sicherheitsnetz: abgelaufene, nie explizit widerrufene Sessions)
async function loadLiveDevices(userId, now = new Date()) {
  const devices = await prisma.pushDevice.findMany({
    where: { userId },
    select: { token: true, environment: true, sessionId: true },
  });
  const sessionIds = [...new Set(devices.map((d) => d.sessionId).filter(Boolean))];
  if (sessionIds.length === 0) return devices;
  const live = await prisma.userSession.findMany({
    where: { id: { in: sessionIds }, revokedAt: null, expiresAt: { gt: now } },
    select: { id: true },
  });
  const liveIds = new Set(live.map((s) => s.id));
  return devices.filter((d) => !d.sessionId || liveIds.has(d.sessionId));
}

module.exports = { removeDevicesForSessions, loadLiveDevices };
