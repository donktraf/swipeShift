// src/utils/twoFactor.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  generateCode, hashCode, codeMatches, isCodeUsable, maskEmail, MAX_ATTEMPTS,
} = require("./twoFactor");
const { deviceInfoFromRequest } = require("./deviceInfo");

const SECRET = "test-secret";

test("generateCode liefert immer 6 Ziffern (inkl. fuehrender Nullen)", () => {
  for (let i = 0; i < 200; i++) assert.match(generateCode(), /^\d{6}$/);
});

test("codeMatches: richtiger Code passt, falscher/kaputter nicht", () => {
  const h = hashCode("012345", SECRET);
  assert.equal(codeMatches("012345", h, SECRET), true);
  assert.equal(codeMatches(" 012345 ", h, SECRET), true);
  assert.equal(codeMatches("012346", h, SECRET), false);
  assert.equal(codeMatches("12345", h, SECRET), false);
  assert.equal(codeMatches("abcdef", h, SECRET), false);
  assert.equal(codeMatches(undefined, h, SECRET), false);
  assert.equal(codeMatches("012345", hashCode("012345", "other"), SECRET), false);
});

test("isCodeUsable: verbraucht, abgelaufen oder zu viele Versuche -> unbrauchbar", () => {
  const now = new Date("2026-11-17T10:00:00Z");
  const future = new Date("2026-11-17T10:05:00Z");
  const past = new Date("2026-11-17T09:59:00Z");
  assert.equal(isCodeUsable({ attempts: 0, expiresAt: future, consumedAt: null }, now), true);
  assert.equal(isCodeUsable({ attempts: 0, expiresAt: past, consumedAt: null }, now), false);
  assert.equal(isCodeUsable({ attempts: 0, expiresAt: future, consumedAt: now }, now), false);
  assert.equal(isCodeUsable({ attempts: MAX_ATTEMPTS, expiresAt: future, consumedAt: null }, now), false);
  assert.equal(isCodeUsable(null, now), false);
});

test("maskEmail verbirgt den lokalen Teil", () => {
  assert.equal(maskEmail("kevin@gmail.com"), "k***n@gmail.com");
  assert.equal(maskEmail("ab@x.de"), "a***@x.de");
  assert.equal(maskEmail("kaputt"), "");
});

test("deviceInfoFromRequest liest + kuerzt Header, nimmt erste X-Forwarded-For-IP", () => {
  const info = deviceInfoFromRequest({
    headers: {
      "x-device-name": "iPhone",
      "x-device-model": "iPhone16,1",
      "x-os-version": "iOS 18.1",
    },
    ip: "203.0.113.5",
  });
  assert.deepEqual(info, { deviceName: "iPhone", deviceModel: "iPhone16,1", osVersion: "iOS 18.1", city: null, ipAddress: "203.0.113.5" });

  const long = deviceInfoFromRequest({ headers: { "x-device-name": "x".repeat(500) }, ip: "127.0.0.1" });
  assert.equal(long.deviceName.length, 64);
  assert.equal(long.deviceModel, null);
  assert.equal(long.ipAddress, "127.0.0.1");
});
