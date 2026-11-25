// src/utils/applicationStatus.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { deriveApplicationStatus, normalizeCancellationReason, DEFAULT_REASONS, MAX_REASON_LENGTH } = require("./applicationStatus");

const now = new Date("2026-11-16T12:00:00Z");
const past   = { status: "published", endTime: new Date("2026-11-10T12:00:00Z") };
const future = { status: "published", endTime: new Date("2026-11-20T12:00:00Z") };

test("applied / confirmed / completed", () => {
  assert.equal(deriveApplicationStatus({ status: "pending" }, future, now).displayStatus, "applied");
  assert.equal(deriveApplicationStatus({ status: "accepted" }, future, now).displayStatus, "confirmed");
  assert.equal(deriveApplicationStatus({ status: "accepted" }, past, now).displayStatus, "completed");
});

test("Zahlungsstatus nur bei completed", () => {
  assert.equal(deriveApplicationStatus({ status: "accepted", isPaid: true }, past, now).paymentStatus, "paid");
  assert.equal(deriveApplicationStatus({ status: "accepted", isPaid: false }, past, now).paymentStatus, "pending");
  assert.equal(deriveApplicationStatus({ status: "accepted", isPaid: false }, future, now).paymentStatus, null);
});

test("declined → cancelled mit Standardgrund", () => {
  const s = deriveApplicationStatus({ status: "declined" }, future, now);
  assert.equal(s.displayStatus, "cancelled");
  assert.equal(s.cancellationKind, "declined");
  assert.equal(s.cancellationReason, DEFAULT_REASONS.declined);
});

test("Stornierter Job: auch angenommene Worker sehen cancelled (Bugfix)", () => {
  const s = deriveApplicationStatus({ status: "accepted" }, { ...future, status: "cancelled" }, now);
  assert.equal(s.displayStatus, "cancelled");
  assert.equal(s.cancellationKind, "jobCancelled");
  assert.equal(s.cancellationReason, DEFAULT_REASONS.jobCancelled);
});

test("Stornierter Job: Employer-Grund wird angezeigt", () => {
  const s = deriveApplicationStatus({ status: "pending" },
    { ...future, status: "cancelled", cancellationReason: "  Event wurde abgesagt  " }, now);
  assert.equal(s.cancellationReason, "Event wurde abgesagt");
});

test("normalizeCancellationReason", () => {
  assert.equal(normalizeCancellationReason(undefined), null);
  assert.equal(normalizeCancellationReason("   "), null);
  assert.equal(normalizeCancellationReason(" Weather "), "Weather");
  assert.equal(normalizeCancellationReason("x".repeat(500)).length, MAX_REASON_LENGTH);
});

test("Employer markiert Job als completed → completed auch vor Schichtende", () => {
  const s = deriveApplicationStatus({ status: "accepted", isPaid: false }, { ...future, status: "completed" }, now);
  assert.equal(s.displayStatus, "completed");
  assert.equal(s.paymentStatus, "pending");
});

test("deriveApplicationStatus: 'completed' erst nach dem Ende der GEBUCHTEN Schichten", () => {
  const at = (d, h, len) => ({ startTimeISO: new Date(Date.UTC(2030, 0, d, h)).toISOString(), endTimeISO: new Date(Date.UTC(2030, 0, d, h + len)).toISOString() });
  const job = { status: "published", endTime: new Date(Date.UTC(2030, 0, 2, 11)), shifts: [{ id: "a", ...at(1, 9, 2) }, { id: "b", ...at(2, 9, 2) }] };
  const now = new Date(Date.UTC(2030, 0, 1, 20));
  assert.equal(deriveApplicationStatus({ status: "accepted", shiftIds: ["a"] }, job, now).displayStatus, "completed");
  assert.equal(deriveApplicationStatus({ status: "accepted", shiftIds: ["b"] }, job, now).displayStatus, "confirmed");
  assert.equal(deriveApplicationStatus({ status: "accepted", shiftIds: [] }, job, now).displayStatus, "confirmed");
});

test("declined mit cancelReason (Konto des Arbeitgebers geschlossen) → jobCancelled mit Grund", () => {
  const r = deriveApplicationStatus({ status: "declined", cancelReason: "The employer closed their account." }, { status: "completed" });
  assert.deepEqual([r.displayStatus, r.cancellationKind, r.cancellationReason], ["cancelled", "jobCancelled", "The employer closed their account."]);
});
