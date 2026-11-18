const test = require("node:test");
const assert = require("node:assert/strict");
const m = require("./moderation");

const now = new Date("2026-11-18T12:00:00Z");
const day = 86400000;

test("restrictionState: none / suspended / pending / banned / expired", () => {
  assert.equal(m.restrictionState({}, now).state, "none");
  assert.equal(m.restrictionState({ suspendedUntil: new Date(now - 1) }, now).state, "none");
  const s = m.restrictionState({ suspendedUntil: new Date(+now + day), suspensionReason: "admin" }, now);
  assert.equal(s.state, "suspended");
  assert.equal(s.pendingReview, false);
  assert.ok(s.until instanceof Date);
  const p = m.restrictionState({ suspendedUntil: m.FAR_FUTURE, suspensionReason: m.PENDING_REVIEW }, now);
  assert.equal(p.pendingReview, true);
  assert.equal(p.until, null);
  assert.equal(m.restrictionState({ bannedAt: now, suspendedUntil: new Date(+now + day) }, now).state, "banned");
});

test("restrictionResponse: codes and null for free accounts", () => {
  assert.equal(m.restrictionResponse({}, now), null);
  assert.equal(m.restrictionResponse({ bannedAt: now }, now).body.code, "ACCOUNT_BANNED");
  const r = m.restrictionResponse({ suspendedUntil: new Date(+now + day), suspensionReason: "admin" }, now);
  assert.equal(r.status, 403);
  assert.equal(r.body.code, "ACCOUNT_SUSPENDED");
  assert.equal(r.body.until, new Date(+now + day).toISOString());
  assert.match(r.body.error, /until 2026-11-19/);
  assert.equal(m.restrictionResponse({ suspendedUntil: m.FAR_FUTURE, suspensionReason: "pending_review" }, now).body.until, null);
});

test("validateAction", () => {
  assert.equal(m.validateAction({ action: "nuke" }).ok, false);
  assert.equal(m.validateAction({ action: "suspend" }).ok, false);
  assert.equal(m.validateAction({ action: "suspend", durationDays: 14 }).ok, false);
  assert.equal(m.validateAction({ action: "suspend", durationDays: "7" }).ok, false);
  assert.deepEqual(m.validateAction({ action: "suspend", durationDays: 7, note: " hi " }).value, { action: "suspend", durationDays: 7, note: "hi" });
  assert.deepEqual(m.validateAction({ action: "ban", durationDays: 7 }).value, { action: "ban", durationDays: null, note: null });
  assert.equal(m.validateAction({ action: "warn", note: "x".repeat(501) }).ok, false);
  assert.equal(m.validateAction({ action: "warn", note: 5 }).ok, false);
  assert.equal(m.validateAction(null).ok, false);
});

test("canModerate: not self, not admin, must exist", () => {
  assert.equal(m.canModerate("a", null).status, 404);
  assert.equal(m.canModerate("a", { id: "a" }).ok, false);
  assert.equal(m.canModerate("a", { id: "b", isAdmin: true }).status, 403);
  assert.equal(m.canModerate("a", { id: "b", isAdmin: false }).ok, true);
});

test("userUpdateFor", () => {
  assert.equal(m.userUpdateFor({ action: "warn" }, now), null);
  assert.equal(m.userUpdateFor({ action: "dismiss" }, now), null);
  const pending = { suspendedUntil: m.FAR_FUTURE, suspensionReason: m.PENDING_REVIEW };
  assert.deepEqual(m.userUpdateFor({ action: "dismiss" }, now, pending), { suspendedUntil: null, suspensionReason: null });
  assert.deepEqual(m.userUpdateFor({ action: "warn" }, now, pending), { suspendedUntil: null, suspensionReason: null });
  assert.equal(m.userUpdateFor({ action: "warn" }, now, { suspendedUntil: m.FAR_FUTURE, suspensionReason: "admin" }), null);
  assert.equal(m.userUpdateFor({ action: "ban" }, now, pending).bannedAt.getTime(), +now);
  const s = m.userUpdateFor({ action: "suspend", durationDays: 30 }, now);
  assert.equal(+s.suspendedUntil, +now + 30 * day);
  assert.equal(m.userUpdateFor({ action: "ban" }, now).bannedAt.getTime(), +now);
});

test("resolutionFor / reporterFeedback", () => {
  assert.equal(m.resolutionFor("dismiss"), "dismissed");
  for (const a of ["warn", "suspend", "ban"]) assert.equal(m.resolutionFor(a), "action_taken");
  assert.equal(m.reporterFeedback("action_taken"), "We reviewed your report and took action.");
  assert.equal(m.reporterFeedback("dismissed"), "We reviewed your report and didn't find a violation of our guidelines.");
});

test("shouldAutoSuspend: needs 3 distinct reporters", () => {
  const r = (reporterId, extra = {}) => ({ reporterId, createdAt: new Date(+now - 1000), status: "open", ...extra });
  const target = { isAdmin: false };
  assert.equal(m.shouldAutoSuspend([r("a"), r("b")], target, { now }), false);
  assert.equal(m.shouldAutoSuspend([r("a"), r("a"), r("b")], target, { now }), false);
  assert.equal(m.shouldAutoSuspend([r("a"), r("b"), r("c")], target, { now }), true);
  assert.equal(m.shouldAutoSuspend([r("a"), r("b"), r("c", { status: "closed" })], target, { now }), false);
});

test("shouldAutoSuspend: skips admins, restricted users, reports before last lift", () => {
  const r = (id, ms) => ({ reporterId: id, createdAt: new Date(ms), status: "open" });
  const three = [r("a", 1000), r("b", 2000), r("c", 3000)];
  assert.equal(m.shouldAutoSuspend(three, { isAdmin: true }, { now }), false);
  assert.equal(m.shouldAutoSuspend(three, { bannedAt: now }, { now }), false);
  assert.equal(m.shouldAutoSuspend(three, { suspendedUntil: m.FAR_FUTURE }, { now }), false);
  assert.equal(m.shouldAutoSuspend(three, { suspendedUntil: new Date(0) }, { now }), true);
  assert.equal(m.shouldAutoSuspend(three, {}, { now, lastLiftAt: new Date(2500) }), false);
  assert.equal(m.shouldAutoSuspend([...three, r("d", 4000)], {}, { now, lastLiftAt: new Date(2500) }), false);
  assert.equal(m.shouldAutoSuspend([...three, r("d", 4000), r("e", 5000)], {}, { now, lastLiftAt: new Date(2500) }), true);
  assert.equal(m.shouldAutoSuspend(null, {}, { now }), false);
  assert.equal(m.shouldAutoSuspend(three, null, { now }), false);
});

test("targetNotice texts", () => {
  const n = m.targetNotice("suspend", { reason: "spam", until: new Date("2026-12-01T00:00:00Z") });
  assert.match(n.paragraphs[0], /2026-12-01/);
  assert.match(n.paragraphs.join(" "), /support@swipeshift\.app/);
  assert.match(m.targetNotice("ban", { reason: "harassment" }).paragraphs[0], /harassment/);
  assert.equal(m.targetNotice("auto_suspend", {}).heading, "Your account is temporarily suspended");
  assert.equal(m.targetNotice("nope", {}), null);
  assert.equal(m.reasonLabel("weird"), "a violation of our guidelines");
});

test("restrictedWhere shape", () => {
  const w = m.restrictedWhere(now);
  assert.equal(w.OR.length, 2);
  assert.equal(+w.OR[1].suspendedUntil.gt, +now);
});

test("planUserUpdate: suspend never lifts a ban", () => {
  const p = m.planUserUpdate({ action: "suspend", durationDays: 7 }, now, { bannedAt: now });
  assert.equal(p.ok, false);
  assert.equal(p.status, 409);
  assert.equal(p.code, "ALREADY_BANNED");
  assert.equal(m.userUpdateFor({ action: "suspend", durationDays: 7 }, now, { bannedAt: now }), null);
});

test("planUserUpdate: suspend keeps a longer existing admin suspension, replaces shorter / pending", () => {
  const longer = { suspendedUntil: new Date(+now + 60 * day), suspensionReason: "admin" };
  assert.equal(+m.planUserUpdate({ action: "suspend", durationDays: 30 }, now, longer).update.suspendedUntil, +now + 60 * day);
  const shorter = { suspendedUntil: new Date(+now + 3 * day), suspensionReason: "admin" };
  assert.equal(+m.planUserUpdate({ action: "suspend", durationDays: 7 }, now, shorter).update.suspendedUntil, +now + 7 * day);
  const pending = { suspendedUntil: m.FAR_FUTURE, suspensionReason: m.PENDING_REVIEW };
  assert.equal(+m.planUserUpdate({ action: "suspend", durationDays: 7 }, now, pending).update.suspendedUntil, +now + 7 * day);
  const expired = { suspendedUntil: new Date(+now - day), suspensionReason: "admin" };
  assert.equal(+m.planUserUpdate({ action: "suspend", durationDays: 7 }, now, expired).update.suspendedUntil, +now + 7 * day);
});

test("planUserUpdate: ban keeps original bannedAt", () => {
  const early = new Date(+now - 10 * day);
  assert.equal(+m.planUserUpdate({ action: "ban" }, now, { bannedAt: early }).update.bannedAt, +early);
});

test("applicant visibility helpers: no NOT over nullable comparisons (SQL NULL logic)", () => {
  const c = m.hiddenPendingClause(now);
  assert.equal(c.status, "pending");
  assert.equal(c.user.OR.length, 2);
  const f = m.visibleApplyFilter(now);
  assert.equal(JSON.stringify(f).includes('"NOT"'), false);
  assert.deepEqual(f.OR[0], { status: { not: "pending" } });
  assert.equal(f.OR[1].user.bannedAt, null);
  assert.deepEqual(f.OR[1].user.OR[0], { suspendedUntil: null });
  assert.equal(+f.OR[1].user.OR[1].suspendedUntil.lte, +now);
  const w = m.withVisibleApplicants({ jobId: "j" }, now);
  assert.deepEqual(w.AND[0], { jobId: "j" });
  assert.deepEqual(w.AND[1], f);
});
