const { test } = require("node:test");
const assert = require("node:assert/strict");
const { maskEmail, emailChangedNotice } = require("./emailChangeNotice");

test("maskEmail zeigt nur das erste Zeichen und die Domain", () => {
  assert.equal(maskEmail("kevin@gmail.com"), "k***@gmail.com");
  assert.equal(maskEmail("a@b.co"), "a***@b.co");
  assert.equal(maskEmail("no-at"), "***");
  assert.equal(maskEmail(undefined), "***");
});

test("emailChangedNotice: Text, Support-Adresse, HTML-Escaping", () => {
  const n = emailChangedNotice({ newEmail: "<b>x</b>@evil.com" });
  assert.match(n.text, /changed to </);
  assert.match(n.text, /support@swipeshift\.app/);
  assert.ok(!n.html.includes("<b>"), "kein rohes HTML");
  assert.match(n.html, /&lt;\*\*\*@evil\.com|&lt;\*\*\*/);
  assert.ok(!n.text.includes("x</b>"), "volle Adresse taucht nicht auf");
});
