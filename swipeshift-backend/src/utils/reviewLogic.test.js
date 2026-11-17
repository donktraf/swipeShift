const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  reviewOverall, summarizeEmployerReviews, validateDraftData, validateReviewSubmission,
  computeWouldWorkAgain, validateWorkerReviewBody,
} = require("./reviewLogic");

test("reviewOverall: Mittel nur ueber vorhandene Kategorien", () => {
  assert.equal(reviewOverall({ communication: 4, teamwork: 4, reliability: 4, underPressure: 4, workQuality: null }), 4);
  assert.equal(reviewOverall({ communication: 5, teamwork: 3, reliability: 4, underPressure: 4, workQuality: 4 }), 4);
  assert.equal(reviewOverall({}), null);
});

test("summarizeEmployerReviews: nulls bei workQuality, Top-Worker-Zaehlung", () => {
  const s = summarizeEmployerReviews([
    { communication: 4, teamwork: 4, reliability: 4, underPressure: 4, workQuality: null, topWorker: false },
    { communication: 5, teamwork: 5, reliability: 5, underPressure: 5, workQuality: 5, topWorker: true },
  ]);
  assert.equal(s.ratings.workQuality, 5);
  assert.equal(s.ratings.communication, 4.5);
  assert.equal(s.overallRating, 4.5);
  assert.equal(s.topWorkerCount, 1);
  const old = summarizeEmployerReviews([{ communication: 3, teamwork: 3, reliability: 3, underPressure: 3, workQuality: null }]);
  assert.equal(old.ratings.workQuality, null);
  assert.equal(old.overallRating, 3);
  assert.deepEqual(summarizeEmployerReviews([]), { reviewCount: 0, overallRating: null, ratings: null, topWorkerCount: 0 });
});

test("validateDraftData: whitelist und Werte", () => {
  const ok = validateDraftData({ communication: 3, workQuality: 0, comment: "hi", topWorker: true, evil: "x" });
  assert.deepEqual(ok, { ok: true, data: { communication: 3, workQuality: 0, comment: "hi", topWorker: true } });
  assert.equal(validateDraftData({ communication: 6 }).ok, false);
  assert.equal(validateDraftData({ communication: 2.5 }).ok, false);
  assert.equal(validateDraftData({ communication: "3" }).ok, false);
  assert.equal(validateDraftData({ comment: "x".repeat(601) }).ok, false);
  assert.equal(validateDraftData({ wouldRehire: "yes" }).ok, false);
  assert.equal(validateDraftData([]).ok, false);
  assert.deepEqual(validateDraftData({}), { ok: true, data: {} });
});

test("validateReviewSubmission: alle 5 Kategorien Pflicht", () => {
  const base = { communication: 4, teamwork: 4, reliability: 4, underPressure: 4, workQuality: 4 };
  const r = validateReviewSubmission({ ...base, comment: "  ", topWorker: true });
  assert.equal(r.ok, true);
  assert.equal(r.data.comment, null);
  assert.equal(r.data.wouldRehire, true);
  assert.equal(r.data.topWorker, true);
  assert.equal(validateReviewSubmission({ ...base, workQuality: undefined }).ok, false);
  assert.equal(validateReviewSubmission({ ...base, teamwork: 0 }).ok, false);
});

test("computeWouldWorkAgain: null-Werte ignoriert, unter 3 ausgeblendet", () => {
  assert.deepEqual(computeWouldWorkAgain([{ wouldWorkAgain: true }, { wouldWorkAgain: null }, { wouldWorkAgain: false }]),
    { percent: null, sampleSize: 2 });
  assert.deepEqual(computeWouldWorkAgain([{ wouldWorkAgain: true }, { wouldWorkAgain: true }, { wouldWorkAgain: false }, {}]),
    { percent: 67, sampleSize: 3 });
  assert.deepEqual(computeWouldWorkAgain([]), { percent: null, sampleSize: 0 });
});

test("validateWorkerReviewBody: Zustimmung und Would-work-again Pflicht", () => {
  assert.match(validateWorkerReviewBody({ wouldWorkAgain: true }), /confirm/);
  const ok = { publishConsent: true, wouldWorkAgain: false, communication: 4, paymentFairness: 3,
    workEnvironment: 5, jobDescriptionAccuracy: 2, overallExperience: 1 };
  assert.match(validateWorkerReviewBody({ publishConsent: true, ...{ ...ok, wouldWorkAgain: undefined } }), /work for this company again/);
  assert.equal(validateWorkerReviewBody(ok), null);
  assert.match(validateWorkerReviewBody({ ...ok, communication: 0 }), /1 to 5/);
  assert.match(validateWorkerReviewBody({ ...ok, overallExperience: 6 }), /1 to 5/);
  assert.match(validateWorkerReviewBody({ ...ok, teamwork: 1, paymentFairness: 2.5 }), /1 to 5/);
  assert.match(validateWorkerReviewBody({ ...ok, workEnvironment: "5" }), /1 to 5/);
  assert.match(validateWorkerReviewBody({ ...ok, comment: "x".repeat(401) }), /400/);
  assert.equal(validateWorkerReviewBody({ ...ok, comment: null }), null);
});

test("summarizeEmployerReviews: gemischte null/Zahl-Werte und alle null", () => {
  const s = summarizeEmployerReviews([
    { communication: 5, teamwork: null, reliability: 4, underPressure: undefined, workQuality: 0 },
    { communication: null, teamwork: 3, reliability: null, underPressure: null, workQuality: null },
  ]);
  assert.equal(s.ratings.communication, 5);
  assert.equal(s.ratings.teamwork, 3);
  assert.equal(s.ratings.underPressure, null);
  assert.equal(s.ratings.workQuality, null);
  assert.equal(s.overallRating, 3.8); // (4.5 + 3) / 2 = 3.75 -> 3.8
  const allNull = summarizeEmployerReviews([{ communication: null, teamwork: null, reliability: null, underPressure: null, workQuality: null }]);
  assert.equal(allNull.overallRating, null);
  assert.equal(allNull.reviewCount, 1);
  assert.ok(Object.values(allNull.ratings).every((v) => v === null));
  assert.equal(summarizeEmployerReviews(null).reviewCount, 0);
});

test("validateDraftData: Grenzen, null, Strings, Booleans", () => {
  assert.equal(validateDraftData({ communication: 0 }).ok, true);
  assert.equal(validateDraftData({ communication: 5 }).ok, true);
  assert.equal(validateDraftData({ communication: -1 }).ok, false);
  assert.equal(validateDraftData({ communication: NaN }).ok, false);
  assert.equal(validateDraftData({ communication: true }).ok, false);
  assert.deepEqual(validateDraftData({ communication: null, comment: null }), { ok: true, data: {} });
  assert.equal(validateDraftData({ comment: "x".repeat(600) }).ok, true);
  assert.equal(validateDraftData({ comment: 123 }).ok, false);
  assert.equal(validateDraftData({ topWorker: 1 }).ok, false);
  assert.deepEqual(validateDraftData({ wouldRehire: false, topWorker: false }).data, { wouldRehire: false, topWorker: false });
  assert.equal(validateDraftData(null).ok, false);
  assert.equal(validateDraftData("x").ok, false);
});

test("validateReviewSubmission: Fehler pro Kategorie, Defaults, Trim", () => {
  const base = { communication: 4, teamwork: 4, reliability: 4, underPressure: 4, workQuality: 4 };
  for (const k of Object.keys(base)) {
    const r = validateReviewSubmission({ ...base, [k]: undefined });
    assert.equal(r.ok, false);
    assert.match(r.error, new RegExp(k));
  }
  assert.equal(validateReviewSubmission({ ...base, workQuality: null }).ok, false);
  assert.equal(validateReviewSubmission({ ...base, communication: 6 }).ok, false);
  const r = validateReviewSubmission({ ...base, comment: "  gut  ", wouldRehire: false });
  assert.equal(r.data.comment, "gut");
  assert.equal(r.data.wouldRehire, false);
  assert.equal(r.data.topWorker, false);
  assert.equal(validateReviewSubmission({ ...base, comment: "x".repeat(601) }).ok, false);
});

test("computeWouldWorkAgain: Rundung, Schwelle, alle true/false", () => {
  const mk = (y, n, x = 0) => [...Array(y).fill({ wouldWorkAgain: true }), ...Array(n).fill({ wouldWorkAgain: false }), ...Array(x).fill({ wouldWorkAgain: null })];
  assert.deepEqual(computeWouldWorkAgain(mk(1, 2)), { percent: 33, sampleSize: 3 });
  assert.deepEqual(computeWouldWorkAgain(mk(2, 1, 5)), { percent: 67, sampleSize: 3 });
  assert.deepEqual(computeWouldWorkAgain(mk(3, 0)), { percent: 100, sampleSize: 3 });
  assert.deepEqual(computeWouldWorkAgain(mk(0, 3)), { percent: 0, sampleSize: 3 });
  assert.deepEqual(computeWouldWorkAgain(mk(1, 1), 2), { percent: 50, sampleSize: 2 });
  assert.deepEqual(computeWouldWorkAgain(null), { percent: null, sampleSize: 0 });
  assert.deepEqual(computeWouldWorkAgain([{ wouldWorkAgain: "true" }, null, undefined]), { percent: null, sampleSize: 0 });
});
