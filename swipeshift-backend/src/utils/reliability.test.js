// src/utils/reliability.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const r = require("./reliability");
const copy = require("./notificationCopy");
const { deriveApplicationStatus } = require("./applicationStatus");

const now = new Date("2026-11-18T12:00:00Z");
const h = (n) => new Date(now.getTime() + n * 3_600_000);
const d = (n) => new Date(now.getTime() + n * 24 * 3_600_000);

const done = (attendance, endDaysAgo = 5, extra = {}) =>
  ({ status: "accepted", attendance, job: { endTime: d(-endDaysAgo) }, ...extra });

test("isLateCancellation: < 24 h vor Start", () => {
  assert.equal(r.isLateCancellation(h(23.9), now), true);
  assert.equal(r.isLateCancellation(h(24), now), false);
  assert.equal(r.isLateCancellation(h(48), now), false);
  assert.equal(r.isLateCancellation(null, now), false);
});

test("evaluateWorkerCancel: nur angenommen + Zukunft + Job offen", () => {
  const job = { status: "published", startTime: h(30) };
  assert.deepEqual(r.evaluateWorkerCancel({ status: "accepted" }, job, now), { ok: true, lateCancellation: false });
  assert.equal(r.evaluateWorkerCancel({ status: "accepted" }, { ...job, startTime: h(2) }, now).lateCancellation, true);
  assert.equal(r.evaluateWorkerCancel({ status: "pending" }, job, now).code, "NOT_ACCEPTED");
  assert.equal(r.evaluateWorkerCancel({ status: "accepted" }, { ...job, startTime: h(-1) }, now).code, "SHIFT_STARTED");
  assert.equal(r.evaluateWorkerCancel({ status: "accepted" }, { ...job, status: "cancelled" }, now).code, "JOB_CLOSED");
  assert.equal(r.evaluateWorkerCancel({ status: "accepted" }, { ...job, startTime: null }, now).code, "SHIFT_STARTED");
  assert.equal(r.canWorkerCancel({ status: "cancelled_by_worker" }, job, now), false);
});

test("attendanceState: Fenster 0–48 h nach Schichtende", () => {
  const apply = { status: "accepted", attendance: null, disputedAt: null };
  const job = (endH) => ({ status: "published", endTime: h(endH) });
  assert.equal(r.attendanceState(apply, job(1), now).ended, false);
  const open = r.attendanceState(apply, job(-1), now);
  assert.deepEqual([open.ended, open.canRecord, open.pending, open.autoDue], [true, true, true, false]);
  const edge = r.attendanceState(apply, job(-47.9), now);
  assert.equal(edge.canRecord, true);
  const closed = r.attendanceState(apply, job(-48), now);
  assert.deepEqual([closed.canRecord, closed.pending, closed.autoDue], [false, false, true]);
  // bereits erfasst: kein pending / autoDue
  const recorded = r.attendanceState({ ...apply, attendance: "late" }, job(-1), now);
  assert.deepEqual([recorded.canRecord, recorded.pending], [true, false]);
  assert.equal(r.attendanceState({ ...apply, attendance: "late" }, job(-60), now).autoDue, false);
  // Einspruch sperrt Employer-Aenderung
  assert.equal(r.attendanceState({ ...apply, attendance: "no_show", disputedAt: now }, job(-1), now).canRecord, false);
  // storniert / nicht angenommen / ohne Ende
  assert.equal(r.attendanceState(apply, { status: "cancelled", endTime: h(-1) }, now).ended, false);
  assert.equal(r.attendanceState({ ...apply, status: "cancelled_by_worker" }, job(-1), now).ended, false);
  assert.equal(r.attendanceState(apply, { status: "published", endTime: null }, now).ended, false);
});

test("Einspruch: einmal, nur late/no_show, Notiz <= 300", () => {
  const set = (days) => ({ attendanceSetAt: d(-days) });
  assert.equal(r.canDispute({ status: "accepted", attendance: "no_show", ...set(1) }, now), true);
  assert.equal(r.canDispute({ status: "accepted", attendance: "late", ...set(13.9) }, now), true);
  assert.equal(r.canDispute({ status: "accepted", attendance: "late", ...set(14.1) }, now), false); // 14-Tage-Frist
  assert.equal(r.canDispute({ status: "accepted", attendance: "no_show" }, now), false);           // ohne Zeitstempel
  assert.equal(r.canDispute({ status: "accepted", attendance: "attended", ...set(1) }, now), false);
  assert.equal(r.canDispute({ status: "accepted", attendance: null }, now), false);
  assert.equal(r.canDispute({ status: "accepted", attendance: "no_show", disputedAt: now, ...set(1) }, now), false);
  assert.equal(r.disputeStatus({}), null);
  assert.equal(r.disputeStatus({ disputedAt: now }), "pending");
  assert.equal(r.disputeStatus({ disputedAt: now, disputeResolvedAt: now }), "resolved");
  assert.deepEqual(r.validateDisputeNote("  Bus broke down \u0000 "), { ok: true, note: "Bus broke down" });
  assert.equal(r.validateDisputeNote("   ").ok, false);
  assert.equal(r.validateDisputeNote(42).ok, false);
  assert.equal(r.validateDisputeNote("x".repeat(300)).ok, true);
  assert.equal(r.validateDisputeNote("x".repeat(301)).ok, false);
});

test("parseDisputeResolution", () => {
  assert.deepEqual(r.parseDisputeResolution({ uphold: true }), { ok: true, resolution: "upheld", attendance: null });
  assert.deepEqual(r.parseDisputeResolution({ attendance: "attended" }), { ok: true, resolution: "changed", attendance: "attended" });
  assert.equal(r.parseDisputeResolution({ attendance: "bogus" }).ok, false);
  assert.equal(r.parseDisputeResolution({}).ok, false);
  assert.equal(r.parseDisputeResolution(null).ok, false);
});

test("summarizeReliability: unter 3 Schichten → New, kein Prozentwert", () => {
  const s = r.summarizeReliability([done("attended"), done("late")], now);
  assert.equal(s.isNew, true);
  assert.equal(s.showUpRate, null);
  assert.equal(s.finishedShifts, 2);
  assert.equal(s.text, "New");
  assert.equal(r.summarizeReliability([], now).text, "New");
  const withNoShow = r.summarizeReliability([done("no_show")], now);
  assert.equal(withNoShow.text, "New · 1 no-show");
});

test("summarizeReliability: Quote zaehlt late als erschienen, Text wie im Beispiel", () => {
  const rows = [...Array(23).fill(0).map(() => done("attended")), done("late"), done("no_show")];
  const s = r.summarizeReliability(rows, now);
  assert.equal(s.showUpRate, 96);
  assert.deepEqual([s.attended, s.late, s.noShows], [23, 1, 1]);
  const clean = r.summarizeReliability([done("attended"), done("attended"), done("late")], now);
  assert.equal(clean.text, "100% showed up · 1 late · 0 late cancellations");
});

test("summarizeReliability: 12-Monats-Fenster, offene Einsprueche, Zukunft, Fremdstatus", () => {
  const rows = [
    done("attended"), done("attended"), done("attended"),
    done("no_show", 400),                                              // zu alt
    done("no_show", 5, { disputedAt: now }),                           // Einspruch offen → ignoriert
    done("no_show", 5, { disputedAt: now, disputeResolvedAt: now }),   // entschieden → zaehlt
    { status: "accepted", attendance: null, job: { endTime: d(-1) } }, // noch nicht erfasst
    { status: "declined", attendance: "no_show", job: { endTime: d(-1) } },
    { status: "accepted", attendance: "no_show", job: { endTime: d(2) } }, // Zukunft
    { status: "accepted", attendance: "bogus", job: { endTime: d(-1) } },
    null,
  ];
  const s = r.summarizeReliability(rows, now);
  assert.deepEqual([s.finishedShifts, s.noShows], [4, 1]);
  assert.equal(s.showUpRate, 75);
});

test("summarizeReliability: kurzfristige Stornos zaehlen nur mit Flag und im Fenster", () => {
  const c = (late, daysAgo) => ({ status: "cancelled_by_worker", lateCancellation: late, cancelledAt: d(-daysAgo) });
  const s = r.summarizeReliability([c(true, 3), c(true, 400), c(false, 2), done("attended"), done("attended"), done("attended")], now);
  assert.equal(s.lateCancellations, 1);
  assert.equal(s.text, "100% showed up · 0 late · 1 late cancellation");
  // 90-Tage-Fenster (Admin)
  const admin = r.summarizeReliability([c(true, 3), c(true, 100)], now, { windowDays: r.ADMIN_WINDOW_DAYS });
  assert.equal(admin.lateCancellations, 1);
});

test("isConspicuous: >= 2 No-Shows oder >= 3 Late Cancellations", () => {
  assert.equal(r.isConspicuous({ noShows: 2, lateCancellations: 0 }), true);
  assert.equal(r.isConspicuous({ noShows: 1, lateCancellations: 2 }), false);
  assert.equal(r.isConspicuous({ noShows: 0, lateCancellations: 3 }), true);
  assert.equal(r.isConspicuous(null), false);
});

test("reliabilityRowsWhere: positiv formuliert (kein NOT)", () => {
  const w = JSON.stringify(r.reliabilityRowsWhere(now));
  assert.equal(w.includes('"NOT"'), false);
  assert.equal(w.includes('"not"'), false);
});

test("deriveApplicationStatus: cancelled_by_worker", () => {
  const s = deriveApplicationStatus({ status: "cancelled_by_worker" }, { status: "published", endTime: h(5) }, now);
  assert.deepEqual([s.displayStatus, s.cancellationKind, s.cancellationReason], ["cancelled", "workerCancelled", "You cancelled this shift."]);
  // bleibt "workerCancelled", auch wenn der Job spaeter storniert wird
  assert.equal(deriveApplicationStatus({ status: "cancelled_by_worker" }, { status: "cancelled" }, now).cancellationKind, "workerCancelled");
});

test("Mails: No-Show freundlich, erwaehnt Einspruch, escaped", () => {
  const n = copy.noShowRecorded({ jobTitle: "<b>Bar</b> shift", company: "Café <script>", jobId: "j1" });
  assert.equal(n.category, "jobActivity");
  assert.match(n.email.text, /dispute/i);
  assert.equal(n.email.html.includes("<script>"), false);
  assert.equal(n.email.html.includes("<b>Bar</b>"), false);
  assert.equal(n.push.data.type, "job");
});

test("Texte: Late Cancellation, Employer-Info, Dispute-Ergebnis", () => {
  assert.match(copy.lateCancellationRecorded({ jobTitle: "Bar", jobId: "j" }).push.body, /24 hours/);
  assert.match(copy.workerCancelledShift({ workerName: "Ann", jobTitle: "Bar", jobId: "j", late: true }).push.body, /less than 24 hours/);
  assert.equal(copy.workerCancelledShift({ workerName: "Ann", jobTitle: "Bar", jobId: "j", late: false }).push.body.includes("24 hours"), false);
  assert.match(copy.attendanceDisputeResolved({ jobTitle: "Bar", jobId: "j", resolution: "changed", attendance: "attended" }).push.body, /showed up/);
  assert.match(copy.attendanceDisputeResolved({ jobTitle: "Bar", jobId: "j", resolution: "upheld", attendance: "no_show" }).push.body, /stays/);
});

test("Abrechnung: No-Show nicht bezahlbar/berechnet, Einspruch offen = on hold, spaeter wieder bezahlbar", () => {
  const ns = { attendance: "no_show", isPaid: false };
  const review = { ...ns, disputedAt: now };
  const upheld = { ...ns, disputedAt: now, disputeResolvedAt: now };
  const cleared = { attendance: "attended", disputedAt: now, disputeResolvedAt: now };
  assert.deepEqual([r.isFinalNoShow(ns), r.isPayable(ns), r.paymentState(ns)], [true, false, "no_show"]);
  assert.deepEqual([r.isFinalNoShow(review), r.isNoShowUnderReview(review), r.isPayable(review), r.paymentState(review)], [false, true, false, "under_review"]);
  assert.deepEqual([r.isFinalNoShow(upheld), r.paymentState(upheld)], [true, "no_show"]);
  assert.deepEqual([r.isPayable(cleared), r.paymentState(cleared)], [true, "pending"]);
  assert.equal(r.isPayable({ attendance: "late" }), true);
  assert.equal(r.paymentState({ attendance: "late", isPaid: true }), "paid");
  assert.equal(r.billable([ns, review, upheld, cleared, { attendance: "late" }, {}]).length, 3); // ns, upheld und Einspruch-offen raus
  assert.deepEqual(r.onHold([ns, review, upheld, cleared]), [review]);
});

test("jobCosts: endgueltige No-Shows zaehlen nicht", () => {
  const { jobCosts } = require("./jobCost");
  const job = { payAmount: 10, startTime: d(-1), endTime: new Date(d(-1).getTime() + 2 * 3_600_000), openSpots: 3 };
  const c = jobCosts(job, [{ isPaid: true }, { isPaid: false, attendance: "late" }, { isPaid: false, attendance: "no_show" }]);
  assert.equal(c.completed, 40);
  assert.equal(c.paidOut, 20);
  const held = jobCosts({ ...job, platformFeePercent: null }, [{ attendance: "no_show", disputedAt: now }]);
  assert.equal(held.completed, 0); // Einspruch offen: noch nicht berechnet
  assert.equal(held.onHold, 20);
});

test("attendanceReminderWindow: Schichtende 24–48 h her", () => {
  const w = r.attendanceReminderWindow(now);
  assert.equal(w.endedBefore.getTime(), h(-24).getTime());
  assert.equal(w.endedAfter.getTime(), h(-48).getTime());
  const n = copy.attendanceReminder({ jobTitle: "Bar", pendingCount: 2, jobId: "j" });
  assert.equal(n.category, "jobActivity");
  assert.match(n.push.body, /2 workers are/);
});

// ── Gebuchte Schichten: Anwesenheit/Zuverlaessigkeit richten sich nach dem Ende der gebuchten Schichten ──
test("attendanceState: Fenster richtet sich nach dem Ende der gebuchten Schicht", () => {
  const rel = require("./reliability");
  const at = (d, h, len) => ({ startTimeISO: new Date(Date.UTC(2030, 0, d, h)).toISOString(), endTimeISO: new Date(Date.UTC(2030, 0, d, h + len)).toISOString() });
  const job = { status: "published", startTime: new Date(Date.UTC(2030, 0, 1, 9)), endTime: new Date(Date.UTC(2030, 0, 2, 11)), shifts: [{ id: "a", ...at(1, 9, 2) }, { id: "b", ...at(2, 9, 2) }] };
  const now = new Date(Date.UTC(2030, 0, 1, 20)); // Schicht a vorbei, b liegt morgen
  assert.equal(rel.attendanceState({ status: "accepted", shiftIds: ["a"] }, job, now).canRecord, true);
  const later = rel.attendanceState({ status: "accepted", shiftIds: ["b"] }, job, now);
  assert.deepEqual([later.ended, later.canRecord, later.pending, later.autoDue], [false, false, false, false]);
  // Altbestand (leer) = alle Schichten → Ende der letzten
  assert.equal(rel.attendanceState({ status: "accepted", shiftIds: [] }, job, now).ended, false);
  // 3 Tage nach Schicht b, ohne Eintrag: Auto-Attendance faellig fuer b, aber a nur 2+ Tage → ebenfalls faellig
  const way = new Date(Date.UTC(2030, 0, 5, 12));
  assert.equal(rel.attendanceState({ status: "accepted", shiftIds: ["b"] }, job, way).autoDue, true);
});

test("summarizeReliability: zaehlt nach dem Ende der gebuchten Schichten", () => {
  const rel = require("./reliability");
  const at = (d, h, len) => ({ startTimeISO: new Date(Date.UTC(2030, 0, d, h)).toISOString(), endTimeISO: new Date(Date.UTC(2030, 0, d, h + len)).toISOString() });
  const job = { endTime: new Date(Date.UTC(2030, 0, 2, 11)), shifts: [{ id: "a", ...at(1, 9, 2) }, { id: "b", ...at(2, 9, 2) }] };
  const now = new Date(Date.UTC(2030, 0, 1, 20));
  const rows = [{ status: "accepted", attendance: "attended", shiftIds: ["a"], job }, { status: "accepted", attendance: "no_show", shiftIds: ["b"], job }];
  const s = rel.summarizeReliability(rows, now);
  assert.equal(s.finishedShifts, 1); // b ist noch nicht gelaufen
  assert.equal(s.noShows, 0);
});

test("reliabilityRowsWhere: nur positive Klauseln, kein NOT/null-Vergleich auf endTime nach oben", () => {
  const rel = require("./reliability");
  const w = rel.reliabilityRowsWhere(new Date(Date.UTC(2030, 0, 1)));
  assert.ok(!JSON.stringify(w).includes('"NOT"'));
  assert.deepEqual(Object.keys(w.OR[0].job.endTime), ["gte"]);
});
