const { test } = require("node:test");
const assert = require("node:assert/strict");
const { uploadFilenameFromUrl, filenamesToRelease, isOrphanOldEnough } = require("./uploadFiles");
const { jobsToCancel } = require("./accountCleanup");

test("uploadFilenameFromUrl: gueltige Upload-URL", () => {
  assert.equal(uploadFilenameFromUrl("http://localhost:3000/uploads/1767-ab12.jpg"), "1767-ab12.jpg");
  assert.equal(uploadFilenameFromUrl("https://api.example.com/uploads/1767-ab12"), "1767-ab12");
});

test("uploadFilenameFromUrl: Traversal und fremde Pfade werden abgelehnt", () => {
  for (const u of [
    "http://h/uploads/../.env", "http://h/uploads/%2e%2e%2f.env", "http://h/uploads/..%2F..%2Fetc%2Fpasswd",
    "http://h/uploads/a/b.jpg", "http://h/uploads/.hidden", "http://h/uploads/", "http://h/uploads",
    "http://h/other/a.jpg", "http://h/uploads/a.jpg?x=1", "http://h/uploads/a%5Cb.jpg", "http://h/uploads/a%00.jpg",
    "file:///uploads/a.jpg", "ftp://h/uploads/a.jpg", "not a url", "", null, undefined, 42,
  ]) assert.equal(uploadFilenameFromUrl(u), null, String(u));
});

test("filenamesToRelease: alt minus neu, dedupliziert", () => {
  const a = "http://h/uploads/a.jpg", b = "http://h/uploads/b.jpg";
  assert.deepEqual(filenamesToRelease([a], [b]), ["a.jpg"]);
  assert.deepEqual(filenamesToRelease([a], [a]), []);
  assert.deepEqual(filenamesToRelease([a, a, null, "junk"], [null]), ["a.jpg"]);
  assert.deepEqual(filenamesToRelease([a], []), ["a.jpg"]);
});

test("isOrphanOldEnough: 24 h Karenz", () => {
  const now = 10 * 86400000;
  assert.equal(isOrphanOldEnough(now - 25 * 3600000, now), true);
  assert.equal(isOrphanOldEnough(now - 3600000, now), false);
});

test("jobsToCancel: nur offene Status", () => {
  const jobs = ["draft", "published", "inProgress", "completed", "cancelled"].map((status) => ({ id: status, status }));
  assert.deepEqual(jobsToCancel(jobs), ["draft", "published", "inProgress"]);
});
