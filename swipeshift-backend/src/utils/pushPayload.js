// src/utils/pushPayload.js
// Reine, DB-freie Helper fuer APNs: Payload, Header, Token-Validierung, Fehlerbewertung.

const MAX_TITLE = 60;
const MAX_BODY = 100;
const APNS_HOSTS = { production: "https://api.push.apple.com", sandbox: "https://api.sandbox.push.apple.com" };

function truncate(text, max) {
  const s = String(text ?? "").replace(/\s+/g, " ").trim();
  return s.length <= max ? s : `${s.slice(0, max - 1).trimEnd()}…`;
}

// data: flache Map (Werte → String). Landet auf oberster Ebene neben "aps" (iOS: userInfo["type"]).
function buildApnsPayload({ title, body, data } = {}) {
  const payload = {
    aps: { alert: { title: truncate(title, MAX_TITLE), body: truncate(body, MAX_BODY) }, sound: "default" },
  };
  for (const [k, v] of Object.entries(data && typeof data === "object" ? data : {})) {
    if (k === "aps" || v === undefined || v === null) continue;
    payload[k] = String(v);
  }
  return payload;
}

function apnsHeaders({ bundleId, jwt, priority = 10 }) {
  return {
    ":method": "POST",
    authorization: `bearer ${jwt}`,
    "apns-topic": bundleId,
    "apns-push-type": "alert",
    "apns-priority": String(priority),
  };
}

function apnsHost(environment) {
  return environment === "sandbox" ? APNS_HOSTS.sandbox : APNS_HOSTS.production;
}

// Geraetetoken: 64 Hex-Zeichen (aktuell), Apple behaelt sich Laengenaenderungen vor → 32–200 Hex
function isValidDeviceToken(token) {
  return typeof token === "string" && /^[0-9a-fA-F]{32,200}$/.test(token);
}

// Header X-Push-Token (aktuelles APNs-Token des Geraets, von der App bei Login/Register mitgeschickt) → normalisiert oder null
function pushTokenFromHeaders(headers) {
  const raw = headers && headers["x-push-token"];
  const v = typeof raw === "string" ? raw.trim().toLowerCase() : "";
  return isValidDeviceToken(v) ? v : null;
}

function normalizeEnvironment(value) {
  return value === "sandbox" || value === "production" ? value : null;
}

// Token ist tot (→ aus der DB loeschen): 410 oder Gruende BadDeviceToken/Unregistered/DeviceTokenNotForTopic
function isDeadTokenResponse(status, reason) {
  return status === 410 || reason === "Unregistered" || reason === "BadDeviceToken" || reason === "DeviceTokenNotForTopic";
}

// APNs-Konfiguration aus der Umgebung; null = nicht konfiguriert (Push inaktiv)
function readApnsConfig(env = process.env, readFile = null) {
  const keyId = env.APNS_KEY_ID, teamId = env.APNS_TEAM_ID, bundleId = env.APNS_BUNDLE_ID;
  let key = env.APNS_KEY ? String(env.APNS_KEY).replace(/\\n/g, "\n") : null;
  if (!key && env.APNS_KEY_PATH && readFile) {
    try { key = readFile(env.APNS_KEY_PATH); } catch { key = null; }
  }
  if (!keyId || !teamId || !bundleId || !key) return null;
  return { keyId, teamId, bundleId, key };
}

module.exports = {
  MAX_BODY, truncate, buildApnsPayload, apnsHeaders, apnsHost, isValidDeviceToken,
  normalizeEnvironment, pushTokenFromHeaders, isDeadTokenResponse, readApnsConfig,
};
