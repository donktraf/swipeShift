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

function deviceInfoFromRequest(req) {
  const h = (req && req.headers) || {};
  const ip = clean(String(h["x-forwarded-for"] || "").split(",")[0]) || clean(req?.ip) || clean(req?.socket?.remoteAddress);
  return {
    deviceName: clean(h["x-device-name"]),
    deviceModel: clean(h["x-device-model"]),
    osVersion: clean(h["x-os-version"]),
    ipAddress: ip,
  };
}

module.exports = { deviceInfoFromRequest };
