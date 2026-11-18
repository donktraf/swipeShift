const { test } = require("node:test");
const assert = require("node:assert/strict");
const { lastCompanyActivity } = require("./savedCompanyDates");

const NOW = new Date("2026-11-18T12:00:00Z");
const d = (n) => new Date(NOW.getTime() + n * 86_400_000);

test("worked: juengster vergangener angenommener Job, Zukunft/storniert ignoriert", () => {
  const r = lastCompanyActivity([
    { status: "completed", startTime: d(-20), endTime: d(-20) },
    { status: "completed", startTime: d(-5), endTime: d(-5) },
    { status: "published", startTime: d(4), endTime: d(4) },
    { status: "cancelled", startTime: d(-1), endTime: d(-1) },
  ], [{ status: "published", createdAt: d(-1) }], NOW);
  assert.equal(r.kind, "worked");
  assert.deepEqual(r.date, d(-5));
});

test("posted: Fallback auf juengsten nicht-Entwurf-Job", () => {
  const r = lastCompanyActivity([], [
    { status: "draft", createdAt: d(-1) },
    { status: "published", createdAt: d(-3) },
    { status: "cancelled", createdAt: d(-9) },
  ], NOW);
  assert.equal(r.kind, "posted");
  assert.deepEqual(r.date, d(-3));
});

test("nichts → null", () => {
  assert.equal(lastCompanyActivity([], [{ status: "draft", createdAt: d(-1) }], NOW), null);
  assert.equal(lastCompanyActivity(null, null, NOW), null);
});
