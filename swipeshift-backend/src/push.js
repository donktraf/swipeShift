// src/push.js
// APNs-Sender (HTTP/2, Provider-Token ES256). Ohne APNS_* → nur Logzeile, kein Fehler (Push inaktiv).
// Env: APNS_KEY_ID, APNS_TEAM_ID, APNS_BUNDLE_ID, APNS_KEY (p8-Inhalt) oder APNS_KEY_PATH — siehe .env.example.

const fs = require("node:fs");
const http2 = require("node:http2");
const {
  buildApnsPayload, apnsHeaders, apnsHost, isDeadTokenResponse, readApnsConfig,
} = require("./utils/pushPayload");

const JWT_TTL_MS = 50 * 60 * 1000; // Apple erlaubt 20–60 min
const REQUEST_TIMEOUT_MS = 10_000;
const IDLE_TIMEOUT_MS = 10 * 60 * 1000;
// Fehler einer verbrauchten/abgebrochenen Session → einmal mit frischer Verbindung wiederholen
const RETRYABLE = new Set(["ERR_HTTP2_GOAWAY_SESSION", "ERR_HTTP2_INVALID_SESSION", "ERR_HTTP2_SESSION_ERROR", "ERR_HTTP2_STREAM_CANCEL", "ECONNRESET", "EPIPE", "ERR_STREAM_WRITE_AFTER_END"]);

// Fabrik fuer Tests: config/connect/hostFor/removeToken/signJwt austauschbar
function createPusher({
  getConfig = () => readApnsConfig(process.env, (p) => fs.readFileSync(p, "utf8")),
  connect = (host) => http2.connect(host),
  hostFor = apnsHost,
  removeToken = async () => {},
  signJwt = null,
  log = console,
} = {}) {
  let cachedJwt = null; // { jwt, at, keyId }
  const sessions = new Map(); // environment → Http2Session (eine wiederverwendete Verbindung pro Umgebung)

  function dropSession(env, client) {
    if (sessions.get(env) === client) sessions.delete(env);
    try { client.close(); } catch { /* ignore */ }
  }

  // Bestehende Session nutzen; bei close/goaway/error wird sie verworfen und beim naechsten Senden neu aufgebaut.
  // unref: eine idle Verbindung haelt den Prozess nicht am Leben; nach IDLE_TIMEOUT_MS wird sie geschlossen.
  function getSession(env) {
    const existing = sessions.get(env);
    if (existing && !existing.closed && !existing.destroyed) return existing;
    const client = connect(hostFor(env));
    sessions.set(env, client);
    client.on("error", (e) => { log.error("push: APNs connection error:", e.code || e.message); dropSession(env, client); });
    client.on("close", () => { if (sessions.get(env) === client) sessions.delete(env); });
    client.on("goaway", () => dropSession(env, client));
    client.setTimeout?.(IDLE_TIMEOUT_MS, () => dropSession(env, client));
    client.unref?.();
    return client;
  }

  function close() {
    for (const [env, client] of [...sessions]) dropSession(env, client);
  }

  async function providerJwt(config) {
    if (cachedJwt && cachedJwt.keyId === config.keyId && Date.now() - cachedJwt.at < JWT_TTL_MS) return cachedJwt.jwt;
    let jwt;
    if (signJwt) jwt = await signJwt(config);
    else {
      const { SignJWT, importPKCS8 } = require("jose");
      const key = await importPKCS8(config.key, "ES256");
      jwt = await new SignJWT({}).setProtectedHeader({ alg: "ES256", kid: config.keyId })
        .setIssuer(config.teamId).setIssuedAt().sign(key);
    }
    cachedJwt = { jwt, at: Date.now(), keyId: config.keyId };
    return jwt;
  }

  // Ein Request ueber eine bestehende Session → { status, reason }
  function sendOne(client, token, headers, body) {
    return new Promise((resolve) => {
      let status = 0, data = "", done = false;
      const finish = (v) => { if (!done) { done = true; resolve(v); } };
      let req;
      try {
        req = client.request({ ...headers, ":path": `/3/device/${token}` });
      } catch (e) {
        return finish({ status: 0, reason: e.code || e.message });
      }
      req.setTimeout(REQUEST_TIMEOUT_MS, () => { req.close(http2.constants.NGHTTP2_CANCEL); finish({ status: 0, reason: "Timeout" }); });
      req.setEncoding("utf8");
      req.on("response", (h) => { status = Number(h[":status"]) || 0; });
      req.on("data", (c) => { data += c; });
      req.on("end", () => {
        let reason = null;
        try { reason = JSON.parse(data || "{}").reason ?? null; } catch { /* ignore */ }
        finish({ status, reason });
      });
      req.on("error", (e) => finish({ status: 0, reason: e.code || e.message }));
      req.end(body);
    });
  }

  // devices: [{ token, environment }]; message: { title, body, data }. Wirft nie.
  async function sendPush(devices, message) {
    try {
      const list = Array.isArray(devices) ? devices : [];
      if (list.length === 0) return { skipped: true, reason: "no-devices", sent: 0 };
      const config = getConfig();
      if (!config) {
        log.log("push skipped: APNs not configured");
        return { skipped: true, reason: "not-configured", sent: 0 };
      }
      const jwt = await providerJwt(config);
      const headers = apnsHeaders({ bundleId: config.bundleId, jwt });
      const body = JSON.stringify(buildApnsPayload(message));

      const byEnv = new Map();
      for (const d of list) {
        const env = d.environment === "sandbox" ? "sandbox" : "production";
        if (!byEnv.has(env)) byEnv.set(env, []);
        byEnv.get(env).push(d);
      }

      let sent = 0;
      for (const [env, group] of byEnv) {
        {
          const results = await Promise.all(group.map(async (d) => {
            let client = getSession(env);
            let r = await sendOne(client, d.token, headers, body);
            if (r.status === 0 && RETRYABLE.has(r.reason)) {
              dropSession(env, client);
              client = getSession(env);
              r = await sendOne(client, d.token, headers, body);
            }
            return { d, r };
          }));
          for (const { d, r } of results) {
            if (r.status === 200) sent += 1;
            else if (isDeadTokenResponse(r.status, r.reason)) {
              await removeToken(d.token).catch((e) => log.error("push: token cleanup failed:", e));
            } else {
              if (r.reason === "ExpiredProviderToken" || r.reason === "InvalidProviderToken") cachedJwt = null;
              log.error(`push: APNs rejected (${r.status} ${r.reason})`);
            }
          }
        }
      }
      return { skipped: false, sent };
    } catch (err) {
      log.error("push: send failed:", err);
      return { skipped: false, error: true, sent: 0 };
    }
  }

  return { sendPush, close };
}

// Produktiv-Instanz: tote Tokens aus der DB entfernen (Lazy-Require wegen Ladezyklen/Tests)
const defaultPusher = createPusher({
  removeToken: (token) => require("./prisma.js").prisma.pushDevice.deleteMany({ where: { token } }),
});

module.exports = { createPusher, sendPush: defaultPusher.sendPush, closePush: defaultPusher.close };
