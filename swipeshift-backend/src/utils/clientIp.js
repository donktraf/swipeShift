// src/utils/clientIp.js
// Normalisiert Client-IPs fuer Sperr-Schluessel: IPv6 → /64 (ein Anschluss hat Milliarden Adressen),
// IPv4-mapped (::ffff:a.b.c.d) → IPv4. Rein, DB-frei.

const net = require("net");

const UNKNOWN = "unknown";

// IPv6-String → 8 Hextets (Zahlen) oder null
function expandIPv6(addr) {
  let a = addr;
  // eingebettetes IPv4 am Ende (z.B. 64:ff9b::1.2.3.4) in zwei Hextets umrechnen
  const m = a.match(/^(.*:)(\d+\.\d+\.\d+\.\d+)$/);
  if (m) {
    if (!net.isIPv4(m[2])) return null;
    const [b1, b2, b3, b4] = m[2].split(".").map(Number);
    a = m[1] + ((b1 << 8) | b2).toString(16) + ":" + ((b3 << 8) | b4).toString(16);
  }
  const halves = a.split("::");
  if (halves.length > 2) return null;
  const head = halves[0] ? halves[0].split(":") : [];
  const tail = halves.length === 2 && halves[1] ? halves[1].split(":") : [];
  const missing = 8 - head.length - tail.length;
  if (halves.length === 1 ? head.length !== 8 : missing < 1) return null;
  const parts = halves.length === 1 ? head : [...head, ...Array(missing).fill("0"), ...tail];
  const nums = parts.map((p) => (/^[0-9a-f]{1,4}$/.test(p) ? parseInt(p, 16) : NaN));
  return nums.some(Number.isNaN) ? null : nums;
}

function normalizeIp(raw) {
  if (typeof raw !== "string") return UNKNOWN;
  const ip = raw.trim().toLowerCase().split("%")[0]; // Zone-ID (fe80::1%en0) entfernen
  if (!ip) return UNKNOWN;
  if (net.isIPv4(ip)) return ip;
  if (!net.isIPv6(ip)) return UNKNOWN;
  const h = expandIPv6(ip);
  if (!h) return UNKNOWN;
  // IPv4-mapped ::ffff:a.b.c.d (auch in Hex-Schreibweise ::ffff:7f00:1) → IPv4
  if (h.slice(0, 5).every((x) => x === 0) && h[5] === 0xffff) {
    return [h[6] >> 8, h[6] & 255, h[7] >> 8, h[7] & 255].join(".");
  }
  return h.slice(0, 4).map((x) => x.toString(16)).join(":") + "::/64";
}

module.exports = { normalizeIp, UNKNOWN };
