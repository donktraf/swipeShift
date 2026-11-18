// src/utils/blockedUsers.js
// Reine, DB-freie Helper fuer GET /safety/blocks (Liste "Blocked users").
// Anzeige konsistent zum Chat-Header: Employer = Firmenname, Worker = Vor- + Nachname.

function trimmedOrNull(v) {
  return typeof v === "string" && v.trim() ? v.trim() : null;
}

// user: { id, role, firstName, lastName }, employer: { companyName, companyLogoUrl } | null,
// worker: { profilePhotoUrl } | null
function describeBlockedUser(user, employer, worker) {
  const isEmployer = !!employer || user?.role === "employer";
  const personName = [trimmedOrNull(user?.firstName), trimmedOrNull(user?.lastName)].filter(Boolean).join(" ");
  const name = (isEmployer ? trimmedOrNull(employer?.companyName) : null) || personName || "User";
  const photoUrl = isEmployer ? trimmedOrNull(employer?.companyLogoUrl) : trimmedOrNull(worker?.profilePhotoUrl);
  return { role: isEmployer ? "employer" : "worker", name, photoUrl };
}

// blocks: UserBlock-Zeilen, users/employers/workers: Arrays aus je EINER Batch-Query.
function buildBlockedList(blocks, users, employers, workers) {
  const byId = (list) => new Map((list ?? []).map(x => [x.userId ?? x.id, x]));
  const userMap = byId(users), empMap = byId(employers), wkMap = byId(workers);
  return (blocks ?? []).map(b => ({
    userId: b.blockedId,
    ...describeBlockedUser(userMap.get(b.blockedId) ?? {}, empMap.get(b.blockedId) ?? null, wkMap.get(b.blockedId) ?? null),
    createdAt: b.createdAt,
  }));
}

module.exports = { describeBlockedUser, buildBlockedList };
