const { test } = require("node:test");
const assert = require("node:assert/strict");
const { renderEmail, escapeHtml, plainLine, FOOTER } = require("./emailTemplate");
const c = require("./notificationCopy");

test("escapeHtml / plainLine", () => {
  assert.equal(escapeHtml(`<a href="x">&'</a>`), "&lt;a href=&quot;x&quot;&gt;&amp;&#39;&lt;/a&gt;");
  assert.equal(plainLine("a\r\nBcc: evil@x.com"), "a Bcc: evil@x.com");
  assert.equal(plainLine("x".repeat(500), 10).length, 10);
  assert.equal(escapeHtml(null), "");
});

test("renderEmail: Footer in HTML und Text, alles escaped", () => {
  const { html, text } = renderEmail({ heading: "<b>Hi</b>", paragraphs: ["<script>alert(1)</script>"] });
  assert.ok(html.includes(escapeHtml(FOOTER)));
  assert.ok(text.endsWith(FOOTER));
  assert.ok(!html.includes("<script>"));
  assert.ok(!html.includes("<b>Hi</b>"));
  assert.ok(text.includes("Settings → Notifications"));
});

test("Mail-Texte escapen Nutzereingaben (Jobtitel, Firma, Grund, Namen)", () => {
  const evil = `<img src=x onerror=alert(1)>`;
  const results = [
    c.applicationAccepted({ jobTitle: evil, company: evil, jobId: "j" }),
    c.applicationDeclined({ jobTitle: evil, company: evil, jobId: "j" }),
    c.jobCancelled({ jobTitle: evil, company: evil, reason: evil, jobId: "j" }),
    c.shiftReminder({ jobTitle: evil, company: evil, startTime: new Date(), jobId: "j" }),
    c.newApplication({ workerName: evil, jobTitle: evil, jobId: "j" }),
    c.instantMatchBooked({ workerName: evil, jobTitle: evil, jobId: "j" }),
    c.paymentReceived({ jobTitle: evil, company: evil }),
    c.paymentOpen({ jobTitle: evil, unpaidCount: 2 }),
    c.reviewReceived({ fromName: evil, jobTitle: evil }),
  ];
  for (const r of results) {
    assert.ok(!r.email.html.includes("<img"), r.push.title);
    assert.ok(r.email.html.includes("&lt;img"), r.push.title);
  }
  assert.ok(!c.unreadMessageEmail({ senderName: evil, jobTitle: evil }).html.includes("<img"));
});

test("Kategorien und Tap-Daten", () => {
  assert.equal(c.applicationAccepted({ jobTitle: "T", jobId: "j", conversationId: "c" }).category, "jobActivity");
  assert.deepEqual(c.applicationAccepted({ jobTitle: "T", jobId: "j", conversationId: "c" }).push.data, { type: "chat", conversationId: "c", jobId: "j" });
  assert.deepEqual(c.applicationDeclined({ jobTitle: "T", jobId: "j" }).push.data, { type: "job", jobId: "j" });
  assert.equal(c.paymentReceived({ jobTitle: "T" }).category, "payments");
  assert.equal(c.paymentOpen({ jobTitle: "T", unpaidCount: 1 }).push.body, `1 worker is still unpaid for "T".`);
  assert.equal(c.reviewReceived({ jobTitle: "T" }).category, "account");
  assert.equal(c.accountPaused().category, "account");
  assert.equal(c.accountResumed().category, "account");
  assert.equal(c.newApplication({ jobTitle: "T", jobId: "j" }).push.data.type, "applicants");
});

test("Chat: Push mit Vorschau (<=100), E-Mail ohne Nachrichtentext", () => {
  const text = "SECRET-CONTENT " + "y".repeat(300);
  const push = c.newMessagePush({ senderName: "Anna", jobTitle: "Bar", text, conversationId: "c1" });
  assert.equal(push.title, "Anna");
  assert.ok(push.body.length <= 100);
  assert.ok(push.body.startsWith("SECRET-CONTENT"));
  assert.deepEqual(push.data, { type: "chat", conversationId: "c1" });
  const mail = c.unreadMessageEmail({ senderName: "Anna", jobTitle: "Bar" });
  assert.equal(mail.subject, "New message from Anna");
  assert.ok(!mail.html.includes("SECRET") && !mail.text.includes("SECRET"));
  assert.ok(mail.text.includes("Anna") && mail.text.includes("Bar") && mail.text.includes("Open the SwipeShift app"));
});

test("Betreff: keine Zeilenumbrueche aus Nutzereingaben", () => {
  const r = c.applicationAccepted({ jobTitle: "Bar\r\nBcc: x@y.z", jobId: "j" });
  assert.ok(!/[\r\n]/.test(r.email.subject));
});

test("formatShiftStart: Zeitzone des Empfaengers, Fallback UTC", () => {
  const d = new Date("2026-11-19T14:00:00Z");
  assert.equal(c.formatShiftStart(d, "America/New_York"), "Thu, Nov 19, 9:00 AM");
  assert.equal(c.formatShiftStart(d, null), "Thu, Nov 19, 2:00 PM UTC");
  assert.equal(c.formatShiftStart("kaputt", "UTC"), "");
});

test("jobCancelled: Grund nur im Push, nie in der Mail", () => {
  const none = c.jobCancelled({ jobTitle: "T", jobId: "j" });
  assert.ok(!none.push.body.includes("Reason"));
  const r = c.jobCancelled({ jobTitle: "T", reason: "Rain http://evil.example", jobId: "j" });
  assert.ok(r.push.body.includes("Reason: Rain"));
  assert.ok(!r.email.text.includes("Rain") && !r.email.html.includes("evil") && !r.email.subject.includes("Rain"));
});

test("describeShiftStart: heute/morgen/Datum in Ortszeit, ohne Zone neutral", () => {
  const now = new Date("2026-11-18T20:00:00Z"); // Berlin 21:00 am 18.
  assert.equal(c.describeShiftStart(new Date("2026-11-18T22:30:00Z"), "Europe/Berlin", now), "today at 11:30 PM");
  assert.equal(c.describeShiftStart(new Date("2026-11-18T23:30:00Z"), "Europe/Berlin", now), "tomorrow at 12:30 AM");
  assert.equal(c.describeShiftStart(new Date("2026-11-18T20:30:00Z"), "Europe/Berlin", now), "today at 9:30 PM");
  assert.equal(c.describeShiftStart(new Date("2026-11-19T08:00:00Z"), "Europe/Berlin", now), "tomorrow at 9:00 AM");
  assert.equal(c.describeShiftStart(new Date("2026-11-21T08:00:00Z"), "Europe/Berlin", now), "Sat, Nov 21, 9:00 AM");
  assert.equal(c.describeShiftStart(new Date("2026-11-19T14:00:00Z"), null, now), "Thu, Nov 19, 2:00 PM UTC");
  assert.ok(!/today|tomorrow/.test(c.shiftReminder({ jobTitle: "T", startTime: "2026-11-19T14:00:00Z", now }).push.body));
});

test("pausedOk nur bei Konto pausiert/fortgesetzt", () => {
  assert.equal(c.accountPaused().pausedOk, true);
  assert.equal(c.accountResumed().pausedOk, true);
  assert.equal(c.reviewReceived({ jobTitle: "T" }).pausedOk, undefined);
});
