// src/utils/chatPresence.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const {
  isTyping, isOnline, isReadByOther, shouldTouchLastSeen, participantFields,
  TYPING_WINDOW_MS, ONLINE_WINDOW_MS, LAST_SEEN_THROTTLE_MS,
} = require("./chatPresence");

const now = new Date("2026-11-16T12:00:00Z");
const ago = (ms) => new Date(now.getTime() - ms);

test("isTyping: innerhalb des Fensters aktiv, danach nicht", () => {
  assert.equal(isTyping(ago(1000), now), true);
  assert.equal(isTyping(ago(TYPING_WINDOW_MS + 1), now), false);
  assert.equal(isTyping(null, now), false);
});

test("isTyping: Zeitstempel in der Zukunft zaehlt nicht", () => {
  assert.equal(isTyping(new Date(now.getTime() + 5000), now), false);
});

test("isOnline: zwei Minuten Fenster", () => {
  assert.equal(isOnline(ago(30 * 1000), now), true);
  assert.equal(isOnline(ago(ONLINE_WINDOW_MS + 1), now), false);
  assert.equal(isOnline(undefined, now), false);
});

test("isReadByOther: lastReadAt nach Sendezeit = gelesen", () => {
  const msg = { createdAt: ago(10000), isRead: false };
  assert.equal(isReadByOther(msg, ago(5000)), true);
  assert.equal(isReadByOther(msg, ago(20000)), false);
  assert.equal(isReadByOther(msg, null), false);
});

test("isReadByOther: altes isRead-Flag bleibt gueltig", () => {
  assert.equal(isReadByOther({ createdAt: now, isRead: true }, null), true);
});

test("shouldTouchLastSeen: drosselt Schreibzugriffe", () => {
  const t = now.getTime();
  assert.equal(shouldTouchLastSeen(undefined, t), true);
  assert.equal(shouldTouchLastSeen(t - 1000, t), false);
  assert.equal(shouldTouchLastSeen(t - LAST_SEEN_THROTTLE_MS, t), true);
});

test("participantFields: Worker vs. Employer Sicht", () => {
  const conv = { workerId: "w", employerId: "e" };
  const w = participantFields(conv, "w");
  assert.equal(w.isWorker, true);
  assert.equal(w.otherUserId, "e");
  assert.equal(w.myTypingField, "workerTypingAt");
  assert.equal(w.otherReadField, "employerLastReadAt");
  const e = participantFields(conv, "e");
  assert.equal(e.otherUserId, "w");
  assert.equal(e.myReadField, "employerLastReadAt");
  assert.equal(e.otherTypingField, "workerTypingAt");
});
