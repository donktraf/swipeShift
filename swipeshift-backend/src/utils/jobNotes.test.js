const { test } = require("node:test");
const assert = require("node:assert/strict");
const { jobNotesForApply } = require("./jobNotes");

test("jobNotesForApply: nur pending/accepted, getrimmt, leer → null", () => {
  assert.equal(jobNotesForApply("accepted", "  Meet at gate "), "Meet at gate");
  assert.equal(jobNotesForApply("pending", "Bring ID"), "Bring ID");
  assert.equal(jobNotesForApply("declined", "Bring ID"), null);
  assert.equal(jobNotesForApply("accepted", "   "), null);
  assert.equal(jobNotesForApply("accepted", null), null);
});
