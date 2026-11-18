// src/utils/savedCompanyDates.js
// "Last worked" / "Last posted" fuer gespeicherte Firmen. Rein und DB-frei → testbar.

function ms(v) {
  const t = v ? new Date(v).getTime() : NaN;
  return Number.isNaN(t) ? null : t;
}

/**
 * @param {Array} acceptedJobs  Jobs der Firma, bei denen der Worker angenommen wurde { status, startTime, endTime }
 * @param {Array} companyJobs   alle Jobs der Firma { status, createdAt }
 * @returns {{ kind: "worked"|"posted", date: Date } | null}
 *   worked = Start des juengsten VERGANGENEN (nicht stornierten) Jobs mit angenommener Bewerbung,
 *   sonst posted = createdAt des juengsten veroeffentlichten (nicht Entwurf) Jobs der Firma.
 */
function lastCompanyActivity(acceptedJobs, companyJobs, now = new Date()) {
  const nowMs = now.getTime();
  let worked = null;
  for (const j of Array.isArray(acceptedJobs) ? acceptedJobs : []) {
    if (!j || j.status === "cancelled" || j.status === "draft") continue;
    const start = ms(j.startTime);
    const end = ms(j.endTime) ?? start;
    if (start === null || end === null || end >= nowMs) continue;
    if (worked === null || start > worked) worked = start;
  }
  if (worked !== null) return { kind: "worked", date: new Date(worked) };

  let posted = null;
  for (const j of Array.isArray(companyJobs) ? companyJobs : []) {
    if (!j || j.status === "draft") continue;
    const created = ms(j.createdAt);
    if (created !== null && (posted === null || created > posted)) posted = created;
  }
  return posted !== null ? { kind: "posted", date: new Date(posted) } : null;
}

module.exports = { lastCompanyActivity };
