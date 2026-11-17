// src/utils/trustProxy.js
// Parst TRUST_PROXY fuer Express ("trust proxy"). Erlaubt: Hop-Anzahl (z.B. "1") oder eine Liste
// konkreter IPs/CIDRs (z.B. "10.0.0.0/8, 172.16.0.5") bzw. Express-Schluesselwoerter
// loopback/linklocal/uniquelocal. "true" ist NICHT erlaubt (jeder Client koennte X-Forwarded-For faelschen).
// Rueckgabe: undefined (nicht setzen) | Zahl | Array von Strings. Ungueltig → Error (Startabbruch).

const net = require("net");

const KEYWORDS = new Set(["loopback", "linklocal", "uniquelocal"]);

function validEntry(entry) {
  if (KEYWORDS.has(entry)) return true;
  const [addr, prefix, ...rest] = entry.split("/");
  if (rest.length) return false;
  const family = net.isIP(addr);
  if (!family) return false;
  if (prefix === undefined) return true;
  if (!/^\d{1,3}$/.test(prefix)) return false;
  return Number(prefix) <= (family === 4 ? 32 : 128);
}

function parseTrustProxy(value) {
  if (value === undefined || value === null) return undefined;
  const v = String(value).trim();
  if (v === "" || v.toLowerCase() === "false") return undefined;
  if (v.toLowerCase() === "true") {
    throw new Error("TRUST_PROXY=true is not allowed. Use the number of proxy hops (e.g. 1) or a list of proxy IPs/CIDRs.");
  }
  if (/^\d+$/.test(v)) {
    const n = Number(v);
    if (n < 1 || n > 10) throw new Error("TRUST_PROXY hop count must be between 1 and 10.");
    return n;
  }
  const entries = v.split(",").map((e) => e.trim()).filter(Boolean);
  const bad = entries.find((e) => !validEntry(e));
  if (!entries.length || bad) throw new Error(`TRUST_PROXY contains an invalid entry: ${bad ?? v}`);
  return entries;
}

module.exports = { parseTrustProxy };
