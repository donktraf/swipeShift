const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const http2 = require("node:http2");
const { createPusher: rawCreate } = require("./push");
function createPusher(opts) { const p = rawCreate(opts); pushers.push(p); return p; }

const silent = { log() {}, error() {} };
const config = { keyId: "K", teamId: "T", bundleId: "com.test.app", key: "unused" };

// Lokaler h2c-Server als APNs-Attrappe: Token "dead…" → 410, "bad…" → 400 BadDeviceToken, sonst 200
const seen = [];
const server = http2.createServer();
server.on("stream", (stream, headers) => {
  let body = "";
  stream.on("data", (c) => { body += c; });
  stream.on("end", () => {
    const token = headers[":path"].split("/").pop();
    seen.push({ token, headers, body: JSON.parse(body) });
    if (token.startsWith("dead")) { stream.respond({ ":status": 410 }); stream.end(JSON.stringify({ reason: "Unregistered" })); }
    else if (token.startsWith("bad")) { stream.respond({ ":status": 400 }); stream.end(JSON.stringify({ reason: "BadDeviceToken" })); }
    else { stream.respond({ ":status": 200 }); stream.end(); }
  });
});
const ready = new Promise((r) => server.listen(0, "127.0.0.1", r));
const pushers = [];
after(() => { pushers.forEach((p) => p.close()); server.close(); });

test("ohne Konfiguration: nur Log, kein Fehler, kein Netzwerk", async () => {
  const lines = [];
  let connected = false;
  const p = createPusher({ getConfig: () => null, connect: () => { connected = true; }, log: { log: (m) => lines.push(m), error() {} } });
  const r = await p.sendPush([{ token: "a".repeat(64), environment: "sandbox" }], { title: "t", body: "b" });
  assert.equal(r.skipped, true);
  assert.equal(connected, false);
  assert.deepEqual(lines, ["push skipped: APNs not configured"]);
});

test("ohne Geraete: nichts zu tun", async () => {
  const p = createPusher({ getConfig: () => config, log: silent });
  assert.equal((await p.sendPush([], { title: "t", body: "b" })).sent, 0);
});

test("sendet Payload + Header; tote Tokens werden entfernt", async () => {
  await ready;
  const removed = [];
  const hosts = [];
  const p = createPusher({
    getConfig: () => config,
    signJwt: async () => "JWT",
    hostFor: (env) => { hosts.push(env); return `http://127.0.0.1:${server.address().port}`; },
    removeToken: async (t) => { removed.push(t); },
    log: silent,
  });
  seen.length = 0;
  const r = await p.sendPush(
    [{ token: "ok1", environment: "sandbox" }, { token: "dead1", environment: "sandbox" }, { token: "bad1", environment: "production" }],
    { title: "Hello", body: "World", data: { type: "chat", conversationId: "c1" } }
  );
  assert.equal(r.sent, 1);
  assert.deepEqual(removed.sort(), ["bad1", "dead1"]);
  assert.deepEqual(hosts.sort(), ["production", "sandbox"]);
  const first = seen.find((s) => s.token === "ok1");
  assert.equal(first.headers["apns-topic"], "com.test.app");
  assert.equal(first.headers["apns-push-type"], "alert");
  assert.equal(first.headers.authorization, "bearer JWT");
  assert.equal(first.body.aps.alert.title, "Hello");
  assert.equal(first.body.conversationId, "c1");
});

test("Verbindungsfehler wirft nie", async () => {
  const p = createPusher({
    getConfig: () => config, signJwt: async () => "JWT", hostFor: () => "http://127.0.0.1:1", log: silent,
  });
  const r = await p.sendPush([{ token: "ok1", environment: "sandbox" }], { title: "t", body: "b" });
  assert.equal(r.sent, 0);
});

test("echte ES256-Signatur mit generiertem Schluessel (jose)", async () => {
  const { generateKeyPair, exportPKCS8, jwtVerify } = require("jose");
  const { privateKey, publicKey } = await generateKeyPair("ES256", { extractable: true });
  const pem = await exportPKCS8(privateKey);
  let captured;
  await ready;
  const p = createPusher({
    getConfig: () => ({ ...config, key: pem }),
    hostFor: () => `http://127.0.0.1:${server.address().port}`,
    log: silent,
  });
  seen.length = 0;
  await p.sendPush([{ token: "ok2", environment: "sandbox" }], { title: "t", body: "b" });
  captured = seen[0].headers.authorization.replace("bearer ", "");
  const { payload, protectedHeader } = await jwtVerify(captured, publicKey, { issuer: "T" });
  assert.equal(protectedHeader.kid, "K");
  assert.equal(protectedHeader.alg, "ES256");
  assert.ok(payload.iat);
});

test("eine HTTP/2-Session pro Umgebung wird wiederverwendet, nach close neu aufgebaut", async () => {
  await ready;
  let connects = 0;
  const http2mod = require("node:http2");
  const p = createPusher({
    getConfig: () => config, signJwt: async () => "JWT",
    connect: () => { connects += 1; return http2mod.connect(`http://127.0.0.1:${server.address().port}`); },
    log: silent,
  });
  const dev = [{ token: "ok3", environment: "sandbox" }];
  assert.equal((await p.sendPush(dev, { title: "t", body: "b" })).sent, 1);
  assert.equal((await p.sendPush(dev, { title: "t", body: "b" })).sent, 1);
  assert.equal(connects, 1);
  await p.sendPush([{ token: "ok4", environment: "production" }], { title: "t", body: "b" });
  assert.equal(connects, 2); // zweite Umgebung = eigene Session
  p.close();
  assert.equal((await p.sendPush(dev, { title: "t", body: "b" })).sent, 1);
  assert.equal(connects, 3);
});

test("Server beendet Session (GOAWAY/close) → Reconnect beim naechsten Senden", async () => {
  await ready;
  let connects = 0;
  const http2mod = require("node:http2");
  let last;
  const p = createPusher({
    getConfig: () => config, signJwt: async () => "JWT",
    connect: () => { connects += 1; last = http2mod.connect(`http://127.0.0.1:${server.address().port}`); return last; },
    log: silent,
  });
  const dev = [{ token: "ok5", environment: "sandbox" }];
  await p.sendPush(dev, { title: "t", body: "b" });
  last.destroy();
  await new Promise((r) => setTimeout(r, 20));
  assert.equal((await p.sendPush(dev, { title: "t", body: "b" })).sent, 1);
  assert.equal(connects, 2);
});
