const { test } = require("node:test");
const assert = require("node:assert/strict");
const { mergeConsents, consentsToFlags, allowedKeysForRole } = require("./consents");

const now = new Date("2026-11-17T10:00:00Z");

test("mergeConsents setzt Zeitstempel bei true", () => {
  const r = mergeConsents(null, { terms: true }, allowedKeysForRole("worker"), now);
  assert.deepEqual(r, { terms: now.toISOString() });
});

test("mergeConsents behält vorhandenen Zeitstempel", () => {
  const r = mergeConsents({ terms: "2026-01-01T00:00:00.000Z" }, { terms: true }, allowedKeysForRole("worker"), now);
  assert.equal(r.terms, "2026-01-01T00:00:00.000Z");
});

test("mergeConsents entfernt Key bei false", () => {
  const r = mergeConsents({ ratingSystem: "x" }, { ratingSystem: false }, allowedKeysForRole("worker"), now);
  assert.deepEqual(r, {});
});

test("mergeConsents ignoriert Keys außerhalb der Rollen-Whitelist", () => {
  const r = mergeConsents({}, { legalHiring: true, bogus: true }, allowedKeysForRole("worker"), now);
  assert.deepEqual(r, {});
  const e = mergeConsents({}, { legalHiring: true, bogus: true }, allowedKeysForRole("employer"), now);
  assert.deepEqual(Object.keys(e), ["legalHiring"]);
});

test("mergeConsents ignoriert Nicht-Booleans und verändert Eingabe nicht", () => {
  const existing = { terms: "t" };
  const r = mergeConsents(existing, { terms: "no", ratingSystem: 1 }, allowedKeysForRole("worker"), now);
  assert.deepEqual(r, { terms: "t" });
  assert.notEqual(r, existing);
});

test("consentsToFlags liefert alle Keys als Bool", () => {
  const f = consentsToFlags({ terms: "t" });
  assert.equal(f.terms, true);
  assert.equal(f.legalHiring, false);
  assert.equal(Object.keys(f).length, 5);
});

test("mergeConsents ignoriert terms:false (nicht widerrufbar)", () => {
  const r = mergeConsents({ terms: "t" }, { terms: false }, allowedKeysForRole("worker"), now);
  assert.deepEqual(r, { terms: "t" });
});

test("mergeConsents: unbekannte Rolle hat keine erlaubten Keys", () => {
  assert.deepEqual(allowedKeysForRole("admin"), []);
  assert.deepEqual(mergeConsents({}, { terms: true }, allowedKeysForRole(undefined), now), {});
});

test("mergeConsents: kaputte Eingaben (existing/updates) liefern sauberes Ergebnis", () => {
  const keys = allowedKeysForRole("employer");
  assert.deepEqual(mergeConsents(["x"], { terms: true }, keys, now), { terms: now.toISOString() });
  assert.deepEqual(mergeConsents({ terms: 5, ratingSystem: "t" }, null, keys, now), { ratingSystem: "t" });
  assert.deepEqual(mergeConsents({ terms: "t" }, [true], keys, now), { terms: "t" });
});

test("mergeConsents: Widerruf und Wiedererteilung vergibt neuen Zeitstempel", () => {
  const keys = allowedKeysForRole("employer");
  const revoked = mergeConsents({ legalHiring: "old" }, { legalHiring: false }, keys, now);
  assert.deepEqual(revoked, {});
  assert.equal(mergeConsents(revoked, { legalHiring: true }, keys, now).legalHiring, now.toISOString());
});
