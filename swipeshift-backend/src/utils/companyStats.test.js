const test = require("node:test");
const assert = require("node:assert/strict");
const { companyJobsWhere, countCompletedJobs, truncateText } = require("./companyStats");

test("zaehlt nur Jobs mit status completed", () => {
  const jobs = [{ status: "completed" }, { status: "published" }, { status: "completed" }, { status: "cancelled" }];
  assert.equal(countCompletedJobs(jobs), 2);
  assert.equal(countCompletedJobs([]), 0);
  assert.equal(countCompletedJobs(undefined), 0);
});

test("companyJobsWhere ist case-insensitive", () => {
  assert.deepEqual(companyJobsWhere("Acme"), { company: { equals: "Acme", mode: "insensitive" } });
});

test("truncateText kuerzt an Wortgrenze und ignoriert Leerwerte", () => {
  assert.equal(truncateText("short text", 50), "short text");
  assert.equal(truncateText("   ", 50), null);
  assert.equal(truncateText(null), null);
  const out = truncateText("alpha beta gamma delta epsilon zeta", 20);
  assert.equal(out, "alpha beta gamma…");
  assert.ok(out.length <= 21);
});
