// src/utils/deviceInfo.js
// Liest die Geraete-Infos, die die iOS-App beim Login mitschickt (X-Device-*-Header).
// Reine Funktion, DB-frei. Werte werden gekuerzt, damit niemand beliebig lange Strings speichert.

const MAX_LEN = 64;

function clean(value) {
  if (typeof value !== "string") return null;
  const v = value.replace(/[\u0000-\u001f\u007f]/g, "").trim();
  if (!v) return null;
  return v.slice(0, MAX_LEN);
}

const MAX_CITY_LEN = 80;

// X-Device-City: grober Ort ("Austin, TX"). Nicht-ASCII darf prozent-kodiert ankommen.
// Ungueltig (zu lang, Steuer-/nicht druckbare Zeichen, leer) → null, nichts wird gespeichert.
function sanitizeCity(value) {
  if (typeof value !== "string") return null;
  let v = value;
  if (/%[0-9a-fA-F]{2}/.test(v)) {
    try { v = decodeURIComponent(v); } catch { return null; }
  }
  v = v.trim();
  if (!v || v.length > MAX_CITY_LEN) return null;
  // \p{C} = Steuer-, Format-, Surrogat- und nicht zugewiesene Zeichen; \p{Zl}/\p{Zp} = Zeilen-/Absatztrenner
  if (/[\p{C}\p{Zl}\p{Zp}]/u.test(v)) return null;
  return v;
}

function deviceInfoFromRequest(req) {
  const h = (req && req.headers) || {};
  // Nur req.ip: Express wertet X-Forwarded-For nur aus, wenn "trust proxy" gesetzt ist (siehe index.js) —
  // ein roher Header waere frei faelschbar.
  const ip = clean(req?.ip) || clean(req?.socket?.remoteAddress);
  return {
    deviceName: clean(h["x-device-name"]),
    deviceModel: clean(h["x-device-model"]),
    osVersion: clean(h["x-os-version"]),
    city: sanitizeCity(h["x-device-city"]),
    ipAddress: ip,
  };
}

module.exports = { deviceInfoFromRequest, sanitizeCity, MAX_CITY_LEN };
