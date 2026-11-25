const { test } = require("node:test");
const assert = require("node:assert/strict");
const { unpaidByJob, planJobClosure, splitBookedShifts } = require("./accountCleanup");

const H = 3_600_000;
const NOW = new Date("2026-11-25T12:00:00Z");
const sh = (id, startH, endH) => ({ id, startTimeISO: new Date(NOW.getTime() + startH * H).toISOString(), endTimeISO: new Date(NOW.getTime() + endH * H).toISOString() });
const job = (shifts, applies, status = "inProgress") => ({ id: "j1", title: "T", status, shifts, applies });
const ap = (o) => ({ id: "a1", userId: "u1", status: "accepted", isPaid: false, shiftIds: [], ...o });
const PAST = sh("p", -30, -26), FUT = sh("f", 24, 28);

test("splitBookedShifts: beendet vs. zukuenftig, shiftIds beachtet", () => {
  const j = job([PAST, FUT], []);
  assert.deepEqual(splitBookedShifts(j, [], NOW).ended.map((s) => s.id), ["p"]);
  assert.deepEqual(splitBookedShifts(j, ["f"], NOW).upcoming.map((s) => s.id), ["f"]);
  assert.equal(splitBookedShifts(j, ["f"], NOW).ended.length, 0);
});

test("unpaidByJob: zaehlt nur beendete, unbezahlte, bezahlbare angenommene", () => {
  const r = unpaidByJob([job([PAST, FUT], [
    ap({ id: "x1" }),                                        // ja
    ap({ id: "x2", shiftIds: ["f"] }),                       // nur Zukunft
    ap({ id: "x3", isPaid: true }),                          // bezahlt
    ap({ id: "x4", attendance: "no_show" }),                 // No-Show endgueltig
    ap({ id: "x5", attendance: "no_show", disputedAt: new Date() }), // Widerspruch offen → blockiert nicht
    ap({ id: "x6", status: "pending" }),
    ap({ id: "x7", attendance: "late" }),                    // ja
  ])], NOW);
  assert.deepEqual(r, [{ jobId: "j1", title: "T", unpaidWorkers: 2, applyIds: ["x1", "x7"] }]);
});

test("unpaidByJob: completed zaehlt, cancelled nicht", () => {
  assert.equal(unpaidByJob([job([PAST], [ap({})], "completed")], NOW).length, 1);
  assert.equal(unpaidByJob([job([PAST], [ap({})], "cancelled")], NOW).length, 0);
});

test("planJobClosure: ohne beendete Schicht → cancelled", () => {
  const p = planJobClosure(job([FUT], []), [ap({}), ap({ id: "a2", status: "pending" })], NOW);
  assert.deepEqual(p, { finalStatus: "cancelled", applyPlans: [] });
  assert.equal(planJobClosure(job([PAST], []), [ap({ status: "pending" })], NOW).finalStatus, "cancelled");
});

test("planJobClosure: completed mit decline/trim/keep", () => {
  const p = planJobClosure(job([PAST, FUT], []), [
    ap({ id: "mixed" }),
    ap({ id: "past", shiftIds: ["p"] }),
    ap({ id: "fut", shiftIds: ["f"] }),
    ap({ id: "pend", status: "pending" }),
    ap({ id: "gone", status: "declined" }),
  ], NOW);
  assert.equal(p.finalStatus, "completed");
  const by = Object.fromEntries(p.applyPlans.map((x) => [x.applyId, x]));
  assert.equal(by.mixed.action, "trim"); assert.deepEqual(by.mixed.shiftIds, ["p"]);
  assert.equal(by.past.action, "keep"); assert.equal(by.past.notify, false);
  assert.equal(by.fut.action, "decline");
  assert.equal(by.pend.action, "decline");
  assert.equal(by.gone, undefined);
});

test("Altbestand: leere shiftIds = alle Schichten des Jobs", () => {
  const j = job([PAST, FUT], []);
  const s = splitBookedShifts(j, [], NOW);
  assert.equal(s.ended.length, 1); assert.equal(s.upcoming.length, 1);
  assert.equal(unpaidByJob([job([PAST], [ap({ shiftIds: [] })])], NOW).length, 1);
});

test("Schicht ohne endTimeISO: erst job.endTime, dann start+Dauer", () => {
  const noEnd = [{ id: "s1", duration: "4 hours" }];
  const endedJob = { ...job(noEnd, []), startTime: new Date(NOW.getTime() - 10 * H), endTime: new Date(NOW.getTime() - 6 * H) };
  assert.equal(splitBookedShifts(endedJob, [], NOW).ended.length, 1);
  const futureJob = { ...job(noEnd, []), startTime: new Date(NOW.getTime() + 2 * H), endTime: new Date(NOW.getTime() + 6 * H) };
  assert.equal(splitBookedShifts(futureJob, [], NOW).upcoming.length, 1);
  const noTimes = { ...job([{ id: "s1", duration: "4 hours" }], []) };
  assert.equal(splitBookedShifts(noTimes, [], NOW).ended.length, 0); // unbekannt = nicht beendet
});

test("pending-only-Job mit beendeter Schicht → cancelled; pending bekommt kind", () => {
  assert.deepEqual(planJobClosure(job([PAST], []), [ap({ status: "pending" })], NOW), { finalStatus: "cancelled", applyPlans: [] });
  const p = planJobClosure(job([PAST, FUT], []), [ap({ id: "m" }), ap({ id: "pe", status: "pending" }), ap({ id: "fu", shiftIds: ["f"] })], NOW);
  const by = Object.fromEntries(p.applyPlans.map((x) => [x.applyId, x.kind]));
  assert.deepEqual(by, { m: "shifts", pe: "pending", fu: "shifts" });
});
