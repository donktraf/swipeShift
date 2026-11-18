const { test } = require("node:test");
const assert = require("node:assert/strict");
const p = require("./pushPayload");

test("buildApnsPayload: alert, Kuerzung, data flach auf oberster Ebene", () => {
  const out = p.buildApnsPayload({ title: "Hi", body: "x".repeat(300), data: { type: "chat", conversationId: "c1", n: 5, aps: "evil", skip: null } });
  assert.equal(out.aps.alert.title, "Hi");
  assert.equal(out.aps.alert.body.length, 100);
  assert.ok(out.aps.alert.body.endsWith("…"));
  assert.equal(out.aps.sound, "default");
  assert.equal(out.type, "chat");
  assert.equal(out.n, "5");
  assert.equal("skip" in out, false);
  assert.deepEqual(Object.keys(out.aps), ["alert", "sound"]);
});

test("buildApnsPayload: ohne Eingaben bleibt gueltig", () => {
  assert.deepEqual(p.buildApnsPayload(), { aps: { alert: { title: "", body: "" }, sound: "default" } });
});

test("apnsHeaders / apnsHost", () => {
  const h = p.apnsHeaders({ bundleId: "com.x.app", jwt: "J" });
  assert.equal(h["apns-topic"], "com.x.app");
  assert.equal(h["apns-push-type"], "alert");
  assert.equal(h["apns-priority"], "10");
  assert.equal(h.authorization, "bearer J");
  assert.equal(p.apnsHost("sandbox"), "https://api.sandbox.push.apple.com");
  assert.equal(p.apnsHost("production"), "https://api.push.apple.com");
});

test("isValidDeviceToken / normalizeEnvironment", () => {
  assert.equal(p.isValidDeviceToken("a".repeat(64)), true);
  assert.equal(p.isValidDeviceToken("zz"), false);
  assert.equal(p.isValidDeviceToken(null), false);
  assert.equal(p.normalizeEnvironment("sandbox"), "sandbox");
  assert.equal(p.normalizeEnvironment("prod"), null);
});

test("pushTokenFromHeaders", () => {
  assert.equal(p.pushTokenFromHeaders({ "x-push-token": " " + "AB".repeat(32) + " " }), "ab".repeat(32));
  assert.equal(p.pushTokenFromHeaders({ "x-push-token": "nope" }), null);
  assert.equal(p.pushTokenFromHeaders({}), null);
  assert.equal(p.pushTokenFromHeaders(undefined), null);
});

test("isDeadTokenResponse", () => {
  assert.equal(p.isDeadTokenResponse(410, "Unregistered"), true);
  assert.equal(p.isDeadTokenResponse(400, "BadDeviceToken"), true);
  assert.equal(p.isDeadTokenResponse(403, "InvalidProviderToken"), false);
  assert.equal(p.isDeadTokenResponse(429, "TooManyRequests"), false);
});

test("readApnsConfig: nur vollstaendig → Config, sonst null", () => {
  const full = { APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_BUNDLE_ID: "B", APNS_KEY: "-----A\\nB-----" };
  assert.deepEqual(p.readApnsConfig(full), { keyId: "K", teamId: "T", bundleId: "B", key: "-----A\nB-----" });
  assert.equal(p.readApnsConfig({}), null);
  assert.equal(p.readApnsConfig({ ...full, APNS_TEAM_ID: "" }), null);
  const viaPath = { APNS_KEY_ID: "K", APNS_TEAM_ID: "T", APNS_BUNDLE_ID: "B", APNS_KEY_PATH: "/k.p8" };
  assert.equal(p.readApnsConfig(viaPath, () => "PEM").key, "PEM");
  assert.equal(p.readApnsConfig(viaPath, () => { throw new Error("x"); }), null);
});
