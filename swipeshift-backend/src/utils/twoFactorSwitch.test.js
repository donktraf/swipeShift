// src/utils/twoFactorSwitch.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const tf = require("./twoFactor");

const off = { twoFactorEnabled: false, twoFactorMethod: null };
const email = { twoFactorEnabled: true, twoFactorMethod: "email" };
const legacy = { twoFactorEnabled: true, twoFactorMethod: null };
const totpU = { twoFactorEnabled: true, twoFactorMethod: "totp" };

test("canSwitchMethod: email -> totp erlaubt, totp -> email erlaubt", () => {
  assert.deepEqual(tf.canSwitchMethod(email, "totp"), { ok: true });
  assert.deepEqual(tf.canSwitchMethod(legacy, "totp"), { ok: true });
  assert.deepEqual(tf.canSwitchMethod(totpU, "email"), { ok: true });
});

test("canSwitchMethod: gleiche Methode -> ALREADY_ENABLED, aus -> NOT_ENABLED", () => {
  assert.equal(tf.canSwitchMethod(totpU, "totp").code, "ALREADY_ENABLED");
  assert.equal(tf.canSwitchMethod(email, "email").code, "ALREADY_ENABLED");
  assert.equal(tf.canSwitchMethod(off, "totp").code, "NOT_ENABLED");
  assert.equal(tf.canSwitchMethod(off, "email").code, "NOT_ENABLED");
  assert.equal(tf.canSwitchMethod(null, "email").ok, false);
});

test("challengeMatchesUser switch_email: nur Mail-Challenge bei aktivem TOTP", () => {
  assert.equal(tf.challengeMatchesUser("switch_email", false, totpU), true);
  assert.equal(tf.challengeMatchesUser("switch_email", true, totpU), false);
  assert.equal(tf.challengeMatchesUser("switch_email", false, email), false);
  assert.equal(tf.challengeMatchesUser("switch_email", false, off), false);
});

test("challengeMatchesUser totp_enable bleibt bei aktiver E-Mail-2FA gueltig (Wechsel email -> totp)", () => {
  assert.equal(tf.challengeMatchesUser("totp_enable", false, email), true);
  assert.equal(tf.challengeMatchesUser("totp_enable", false, totpU), false);
});

test("switchBindingValid: User, Sitzung und Zweck muessen passen", () => {
  const rec = { purpose: "switch_email", userId: "u1", sessionId: "s1" };
  assert.equal(tf.switchBindingValid(rec, { userId: "u1", sessionId: "s1" }), true);
  assert.equal(tf.switchBindingValid(rec, { userId: "u1", sessionId: "s2" }), false);
  assert.equal(tf.switchBindingValid(rec, { userId: "u2", sessionId: "s1" }), false);
  assert.equal(tf.switchBindingValid(rec, { userId: "u1", sessionId: undefined }), false);
  assert.equal(tf.switchBindingValid({ ...rec, sessionId: null }, { userId: "u1", sessionId: null }), false);
  assert.equal(tf.switchBindingValid({ ...rec, purpose: "enable" }, { userId: "u1", sessionId: "s1" }), false);
  assert.equal(tf.switchBindingValid(null, { userId: "u1", sessionId: "s1" }), false);
});

test("methodChangedMail nennt die neue Methode", () => {
  assert.match(tf.methodChangedMail("totp").subject, /authenticator app/);
  assert.match(tf.methodChangedMail("email").subject, /email codes/);
  assert.match(tf.methodChangedMail("email").text, /password/);
});
