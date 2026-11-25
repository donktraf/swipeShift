const { test } = require("node:test");
const assert = require("node:assert/strict");
const fs = require("fs");
const os = require("os");
const path = require("path");
const { resolveUploadPath, deleteUploadFile } = require("./uploadCleanup");
const { normalizePhotoUrl } = require("./utils/uploadFiles");
const r = require("./utils/retention");

function tmpDir() { return fs.mkdtempSync(path.join(os.tmpdir(), "uploads-test-")); }

test("resolveUploadPath: nur direkte Kinder des Upload-Ordners", () => {
  const dir = tmpDir();
  assert.equal(resolveUploadPath("a.jpg", dir), path.join(dir, "a.jpg"));
  for (const bad of ["../a.jpg", "..", "sub/a.jpg", "/etc/passwd", "a/../../b", ""]) assert.equal(resolveUploadPath(bad, dir), null, bad);
});

test("deleteUploadFile: loescht Datei, ignoriert fehlende, weigert Symlink/Ordner/Traversal", async () => {
  const dir = tmpDir(), outside = tmpDir();
  fs.writeFileSync(path.join(dir, "a.jpg"), "x");
  fs.writeFileSync(path.join(outside, "secret.txt"), "s");
  fs.symlinkSync(path.join(outside, "secret.txt"), path.join(dir, "link.jpg"));
  fs.mkdirSync(path.join(dir, "folder.d"));
  assert.equal(await deleteUploadFile("a.jpg", dir), true);
  assert.equal(fs.existsSync(path.join(dir, "a.jpg")), false);
  assert.equal(await deleteUploadFile("a.jpg", dir), false); // weg → kein Fehler
  assert.equal(await deleteUploadFile("link.jpg", dir), false);
  assert.equal(fs.existsSync(path.join(outside, "secret.txt")), true);
  assert.equal(fs.existsSync(path.join(dir, "link.jpg")), true);
  assert.equal(await deleteUploadFile("folder.d", dir), false);
  assert.equal(await deleteUploadFile(`../${path.basename(outside)}/secret.txt`, dir), false);
  assert.equal(fs.existsSync(path.join(outside, "secret.txt")), true);
});

test("normalizePhotoUrl: leer ok, eigene Upload-URL ok (Query/Hash entfernt), Fremdes abgelehnt", () => {
  const hosts = ["localhost:3000"];
  assert.deepEqual(normalizePhotoUrl(null, hosts), { ok: true, value: null });
  assert.deepEqual(normalizePhotoUrl("", hosts), { ok: true, value: null });
  assert.deepEqual(normalizePhotoUrl("http://localhost:3000/uploads/a-1.jpg?x=1#h", hosts), { ok: true, value: "http://localhost:3000/uploads/a-1.jpg" });
  for (const bad of ["https://lh3.googleusercontent.com/a.jpg", "http://evil.com/uploads/a.jpg", "http://localhost:3000/other/a.jpg",
    "http://localhost:3000/uploads/../x", "javascript:alert(1)", "nope", 5]) assert.equal(normalizePhotoUrl(bad, hosts).ok, false, String(bad));
});

test("Bann-Filter: Reports/Actions aktiv gebannter Personen bleiben, andere alte werden ausgewaehlt", () => {
  const now = new Date("2026-11-25T00:00:00Z");
  const old = new Date("2023-01-01T00:00:00Z");
  const banned = r.activeBanTargets([{ id: "u1", bannedAt: old }], [{ id: "t1", bannedAt: old }, { id: "t2", bannedAt: null }]);
  const reports = ["u1", "t1", "t2", "x"].map((id) => ({ status: "closed", resolvedAt: old, reportedUserId: id }));
  assert.deepEqual(reports.filter((x) => r.isReportPurgeable(x, banned, now)).map((x) => x.reportedUserId), ["t2", "x"]);
  const actions = ["u1", "t1", "t2", "x"].map((id) => ({ targetUserId: id, createdAt: old }));
  assert.deepEqual(actions.filter((x) => r.isActionPurgeable(x, banned, now)).map((x) => x.targetUserId), ["t2", "x"]);
});
