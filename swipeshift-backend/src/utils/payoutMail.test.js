// src/utils/payoutMail.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { payoutChangeMail } = require("./payoutMail");

const now = new Date("2026-11-18T12:34:56Z");
const settings = { payout: { method: "bank", paypalEmail: "<b>x</b>@a.de", bank: { accountLast4: "1234", routingNumber: "021000021" } } };

test("Mail nennt nur sichere Angaben, Zeitstempel UTC und Support-Hinweis", () => {
  const m = payoutChangeMail(settings, { bank: true, paypal: false, method: true }, now);
  assert.match(m.text, /Bank account ending 1234/);
  assert.match(m.text, /Payout method changed to bank account/);
  assert.match(m.text, /2026-11-18 12:34 UTC/);
  assert.match(m.text, /change your password and contact support@swipeshift.app/);
  assert.ok(!m.text.includes("021000021"));
  assert.ok(!m.html.includes("<b>"));
});

test("PayPal: keine Adresse in der Mail", () => {
  const m = payoutChangeMail(settings, { bank: false, paypal: true, method: false }, now);
  assert.match(m.text, /PayPal account was changed/);
  assert.ok(!m.text.includes("x</b>"));
});
