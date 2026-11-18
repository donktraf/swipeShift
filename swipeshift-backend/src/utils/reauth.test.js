const test = require("node:test");
const assert = require("node:assert/strict");
const { availableMethods, isReauthFresh, reauthValidUntil, REAUTH_TTL_MS } = require("./reauth");

test("availableMethods: Reihenfolge und Social-Login ohne Passwort", () => {
  assert.deepEqual(availableMethods({ passwordHash: "x", twoFactorEnabled: true, twoFactorMethod: "totp" }), ["totp", "password"]);
  assert.deepEqual(availableMethods({ passwordHash: "x", twoFactorEnabled: true, twoFactorMethod: "email" }), ["password"]);
  assert.deepEqual(availableMethods({ passwordHash: "SOCIAL_LOGIN" }), ["email"]);
  assert.deepEqual(availableMethods({ passwordHash: "SOCIAL_LOGIN", twoFactorEnabled: true, twoFactorMethod: "totp" }), ["totp"]);
  assert.deepEqual(availableMethods({ passwordHash: "x", twoFactorEnabled: false, twoFactorMethod: "totp" }), ["password"]);
});

test("isReauthFresh: Fenster, widerrufen, abgelaufen, fehlend", () => {
  const now = Date.now();
  const future = new Date(now + 1e9);
  const base = { expiresAt: future, revokedAt: null };
  assert.equal(isReauthFresh({ ...base, reauthAt: null }, now), false);
  assert.equal(isReauthFresh(null, now), false);
  assert.equal(isReauthFresh({ ...base, reauthAt: new Date(now - 1000) }, now), true);
  assert.equal(isReauthFresh({ ...base, reauthAt: new Date(now - REAUTH_TTL_MS + 1000) }, now), true);
  assert.equal(isReauthFresh({ ...base, reauthAt: new Date(now - REAUTH_TTL_MS) }, now), false);
  assert.equal(isReauthFresh({ ...base, reauthAt: new Date(now + 60000) }, now), false);
  assert.equal(isReauthFresh({ ...base, reauthAt: new Date(now - 1000), revokedAt: new Date() }, now), false);
  assert.equal(isReauthFresh({ reauthAt: new Date(now - 1000), expiresAt: new Date(now - 1) }, now), false);
});

test("reauthValidUntil", () => {
  const at = new Date("2026-01-01T00:00:00Z");
  assert.equal(reauthValidUntil(at).getTime(), at.getTime() + REAUTH_TTL_MS);
  assert.equal(reauthValidUntil(null), null);
});
