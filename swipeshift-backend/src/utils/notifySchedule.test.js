const { test } = require("node:test");
const assert = require("node:assert/strict");
const s = require("./notifySchedule");

const NOW = new Date("2026-11-18T12:00:00Z");
const ago = (min) => new Date(NOW.getTime() - min * 60000);
const conv = (over = {}) => ({
  id: "c1", workerId: "w", employerId: "e", workerLastReadAt: null, employerLastReadAt: null,
  workerEmailNotifiedAt: null, employerEmailNotifiedAt: null, job: { title: "Bar" }, ...over,
});
const msg = (over = {}) => ({ id: "m", senderId: "e", isSystem: false, isRead: false, createdAt: ago(20), conversation: conv(), ...over });

test("Fenster", () => {
  const w = s.shiftReminderWindow(NOW);
  assert.equal(w.from.toISOString(), NOW.toISOString());
  assert.equal(w.to.toISOString(), "2026-11-19T12:00:00.000Z");
  const p = s.paymentOpenWindow(NOW);
  assert.equal(p.endedBefore.toISOString(), NOW.toISOString());
  assert.equal(p.endedAfter.toISOString(), "2026-11-11T12:00:00.000Z");
});

test("Ungelesen >15 min → Ziel mit Empfaenger-Rolle", () => {
  const r = s.pickUnreadMessageEmailTargets([msg()], NOW);
  assert.deepEqual(r, [{ conversationId: "c1", recipientId: "w", recipientRole: "worker", senderId: "e", jobTitle: "Bar", unreadCount: 1 }]);
  const r2 = s.pickUnreadMessageEmailTargets([msg({ senderId: "w" })], NOW);
  assert.equal(r2[0].recipientId, "e");
  assert.equal(r2[0].recipientRole, "employer");
});

test("zu frisch, zu alt, System, isRead → kein Ziel", () => {
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ createdAt: ago(10) })], NOW).length, 0);
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ createdAt: ago(25 * 60) })], NOW).length, 0);
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ isSystem: true })], NOW).length, 0);
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ isRead: true })], NOW).length, 0);
});

test("inzwischen gelesen (lastReadAt nach Nachricht) → kein Ziel", () => {
  const c = conv({ workerLastReadAt: ago(5) });
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ conversation: c })], NOW).length, 0);
  const c2 = conv({ workerLastReadAt: ago(60) }); // gelesen VOR der Nachricht
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ conversation: c2 })], NOW).length, 1);
});

test("Cooldown 1 h und nur neue Nachrichten seit letzter Mail", () => {
  const recent = conv({ workerEmailNotifiedAt: ago(30) });
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ conversation: recent })], NOW).length, 0);
  // Mail vor 90 min, Nachricht davor → schon abgedeckt
  const old = conv({ workerEmailNotifiedAt: ago(90) });
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ createdAt: ago(120), conversation: old })], NOW).length, 0);
  // Nachricht nach der letzten Mail und Cooldown vorbei → Ziel
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ createdAt: ago(80), conversation: old })], NOW).length, 1);
  // Cooldown gilt pro Empfaenger: Mail an Worker sperrt Employer nicht
  const c = conv({ workerEmailNotifiedAt: ago(5) });
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ senderId: "w", conversation: c })], NOW).length, 1);
});

test("mehrere Nachrichten → ein Ziel pro Konversation+Empfaenger; kein Employer → ignoriert", () => {
  const r = s.pickUnreadMessageEmailTargets([msg({ id: "1" }), msg({ id: "2", createdAt: ago(30) })], NOW);
  assert.equal(r.length, 1);
  assert.equal(r[0].unreadCount, 2);
  const noEmp = conv({ employerId: null });
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ senderId: "w", conversation: noEmp })], NOW).length, 0);
  assert.equal(s.pickUnreadMessageEmailTargets([msg({ senderId: "stranger" })], NOW).length, 0);
  assert.deepEqual(s.pickUnreadMessageEmailTargets(null, NOW), []);
});
