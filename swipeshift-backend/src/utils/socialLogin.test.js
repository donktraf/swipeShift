const test = require("node:test");
const assert = require("node:assert/strict");
const { normalizeEmail, decideAppleLogin, decideGoogleLogin, needsTakeoverCleanup, stripPayout } = require("./socialLogin");

const victim = { id: "u1", email: "victim@example.com" };

test("normalizeEmail trims and lowercases, tolerates non-strings", () => {
  assert.equal(normalizeEmail("  Foo@Bar.COM \n"), "foo@bar.com");
  assert.equal(normalizeEmail(undefined), "");
  assert.equal(normalizeEmail(5), "");
});

test("apple: subject match logs in without linking", () => {
  const d = decideAppleLogin({ tokenSub: "s", userBySub: victim });
  assert.deepEqual(d, { action: "login", user: victim, linkSub: false });
});

test("apple: verified token email matches existing account and links sub", () => {
  const d = decideAppleLogin({ tokenSub: "s", tokenEmail: "Victim@Example.com", tokenEmailVerified: "true", userByEmail: victim });
  assert.equal(d.action, "login");
  assert.equal(d.linkSub, true);
});

test("apple: unverified/missing email_verified on token email never matches", () => {
  for (const flag of [false, "false", undefined]) {
    const d = decideAppleLogin({ tokenSub: "s", tokenEmail: "victim@example.com", tokenEmailVerified: flag, userByEmail: victim });
    assert.equal(d.action, "reject");
  }
});

test("apple: BODY email must never log into an existing account", () => {
  const d = decideAppleLogin({ tokenSub: "attacker", bodyEmail: "victim@example.com", userByEmail: victim });
  assert.equal(d.action, "reject");
  assert.equal(d.status, 409);
  assert.equal(d.code, "EMAIL_IN_USE");
});

test("apple: body email for a brand-new account is stored unverified", () => {
  const d = decideAppleLogin({ tokenSub: "s", bodyEmail: " New@Example.com ", userByEmail: null });
  assert.deepEqual(d, { action: "create", email: "new@example.com", emailVerified: false });
});

test("apple: verified token email creates a verified new account; no email at all rejected", () => {
  assert.deepEqual(decideAppleLogin({ tokenSub: "s", tokenEmail: "a@b.co", tokenEmailVerified: true }), { action: "create", email: "a@b.co", emailVerified: true });
  assert.equal(decideAppleLogin({ tokenSub: "s" }).status, 400);
  assert.equal(decideAppleLogin({ tokenEmail: "a@b.co", tokenEmailVerified: true }).status, 401);
});

test("google: only a verified token email is used", () => {
  assert.equal(decideGoogleLogin({ tokenEmail: "victim@example.com", emailVerified: false, existingUser: victim }).action, "reject");
  assert.equal(decideGoogleLogin({ tokenEmail: "victim@example.com", emailVerified: undefined, existingUser: victim }).action, "reject");
  assert.equal(decideGoogleLogin({ tokenEmail: "", emailVerified: true }).action, "reject");
  assert.equal(decideGoogleLogin({ tokenEmail: "victim@example.com", emailVerified: true, existingUser: victim }).action, "login");
  assert.deepEqual(decideGoogleLogin({ tokenEmail: " New@X.io", emailVerified: true, existingUser: null }), { action: "create", email: "new@x.io" });
});

test("takeover cleanup: only for previously unverified accounts", () => {
  assert.equal(needsTakeoverCleanup(null), false);
  assert.equal(needsTakeoverCleanup({ emailVerifiedAt: null, passwordHash: "hash" }), true);
  assert.equal(needsTakeoverCleanup({ emailVerifiedAt: new Date(), passwordHash: "hash" }), false);
});

test("stripPayout removes only the payout key", () => {
  assert.deepEqual(stripPayout({ payout: { method: "bank" }, notifications: { a: 1 } }), { notifications: { a: 1 } });
  assert.equal(stripPayout(null), null);
  assert.deepEqual(stripPayout({ x: 1 }), { x: 1 });
});
