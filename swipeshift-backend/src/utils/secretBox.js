// src/utils/secretBox.js
// Gemeinsame Secret-Verschluesselung (AES-256-GCM, Key-ID, frei waehlbare AAD/Kontext) mit Key-Rotation.
// Genutzt von TOTP (AAD = userId) und Bankdaten (AAD = "bank:<userId>").
// Key: TOTP_ENCRYPTION_KEY (+ TOTP_ENCRYPTION_KEY_PREVIOUS waehrend einer Rotation).
// Format: v1.<kid>.<iv b64>.<tag b64>.<ciphertext b64>

const crypto = require("crypto");

let warnedDevKey = false;
const DEV_ENVS = new Set(["development", "test"]);

function kidOf(key) {
  return crypto.createHash("sha256").update(key).digest("hex").slice(0, 8);
}

function toEntry(key) {
  return { kid: kidOf(key), key };
}

// 32-Byte-Key aus 64 Hex-Zeichen oder Base64 (genau 32 Byte). Nur ausserhalb von Produktion/Staging
// (NODE_ENV development/test) ist zusaetzlich eine beliebige Passphrase erlaubt (→ SHA-256).
function parseKey(raw, { allowPassphrase = false, name = "TOTP_ENCRYPTION_KEY" } = {}) {
  if (/^[0-9a-fA-F]{64}$/.test(raw)) return Buffer.from(raw, "hex");
  const b = Buffer.from(raw, "base64");
  if (b.length === 32 && b.toString("base64") === raw) return b;
  if (allowPassphrase) return crypto.createHash("sha256").update(raw).digest();
  throw new Error(`${name} must be 32 bytes: 64 hex characters or base64 (e.g. \`openssl rand -hex 32\`).`);
}

// Keyring: { current: {kid,key}, previous: {kid,key}|null }.
// Ohne Key: Dev-Fallback (aus JWT_SECRET) NUR bei NODE_ENV=development|test, sonst Fehler.
function getKeyring(env = process.env) {
  const dev = DEV_ENVS.has(env.NODE_ENV);
  const raw = env.TOTP_ENCRYPTION_KEY;
  let current;
  if (!raw) {
    if (!dev) {
      throw new Error("TOTP_ENCRYPTION_KEY is required unless NODE_ENV is development or test (32 bytes, e.g. `openssl rand -hex 32`).");
    }
    if (!warnedDevKey) {
      warnedDevKey = true;
      console.warn("[totp] TOTP_ENCRYPTION_KEY is not set — using a development key derived from JWT_SECRET. Do NOT use this outside development.");
    }
    current = crypto.createHash("sha256").update("totp-dev-key:" + (env.JWT_SECRET || "dev_secret_change_me")).digest();
  } else {
    current = parseKey(raw, { allowPassphrase: dev });
  }
  const prevRaw = env.TOTP_ENCRYPTION_KEY_PREVIOUS;
  const previous = prevRaw
    ? parseKey(prevRaw, { allowPassphrase: dev, name: "TOTP_ENCRYPTION_KEY_PREVIOUS" })
    : null;
  return { current: toEntry(current), previous: previous ? toEntry(previous) : null };
}

function encryptWithAad(plain, aad, keyring = getKeyring()) {
  const iv = crypto.randomBytes(12);
  const cipher = crypto.createCipheriv("aes-256-gcm", keyring.current.key, iv, { authTagLength: 16 });
  cipher.setAAD(Buffer.from(String(aad), "utf8"));
  const enc = Buffer.concat([cipher.update(String(plain), "utf8"), cipher.final()]);
  return ["v1", keyring.current.kid, iv.toString("base64"), cipher.getAuthTag().toString("base64"), enc.toString("base64")].join(".");
}

function payloadKid(payload) {
  const parts = String(payload || "").split(".");
  return parts[0] === "v1" && parts.length === 5 ? parts[1] : null;
}

function decryptWithAad(payload, aad, keyring = getKeyring()) {
  const [v, kid, iv, tag, data] = String(payload || "").split(".");
  if (v !== "v1" || !kid || !iv || !tag || !data) throw new Error("Invalid encrypted payload");
  const entry = [keyring.current, keyring.previous].find((e) => e && e.kid === kid);
  if (!entry) throw new Error(`Unknown key id ${kid}`);
  const decipher = crypto.createDecipheriv("aes-256-gcm", entry.key, Buffer.from(iv, "base64"), { authTagLength: 16 });
  decipher.setAAD(Buffer.from(String(aad), "utf8"));
  decipher.setAuthTag(Buffer.from(tag, "base64"));
  return Buffer.concat([decipher.update(Buffer.from(data, "base64")), decipher.final()]).toString("utf8");
}

// true, wenn der Payload noch mit einem aelteren Key verschluesselt ist (→ neu verschluesseln)
function needsReencrypt(payload, keyring = getKeyring()) {
  const kid = payloadKid(payload);
  return !!kid && kid !== keyring.current.kid;
}

// Payload mit dem aktuellen Key neu verschluesseln; null = schon aktuell
function reencryptWithAad(payload, aad, keyring = getKeyring()) {
  if (!needsReencrypt(payload, keyring)) return null;
  return encryptWithAad(decryptWithAad(payload, aad, keyring), aad, keyring);
}

module.exports = {
  parseKey, kidOf, getKeyring, encryptWithAad, decryptWithAad, payloadKid, needsReencrypt, reencryptWithAad,
};
