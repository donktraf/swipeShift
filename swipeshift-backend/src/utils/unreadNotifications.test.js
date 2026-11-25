const test = require("node:test");
const assert = require("node:assert");
const { countUnread } = require("./unreadNotifications");

const now = new Date("2026-11-25T12:00:00Z");
const h = (n) => new Date(now.getTime() - n * 3_600_000);

test("zaehlt nur Eintraege nach seenAt", () => {
  const list = [{ timestamp: h(1) }, { timestamp: h(5) }, { timestamp: h(30) }];
  assert.equal(countUnread(list, h(2), now), 1);
  assert.equal(countUnread(list, h(0), now), 0);
});

test("ohne seenAt nur letzte 7 Tage", () => {
  const list = [{ timestamp: h(1) }, { timestamp: h(24 * 8) }];
  assert.equal(countUnread(list, null, now), 1);
});

test("robust gegen kaputte Eingaben", () => {
  assert.equal(countUnread(null, null, now), 0);
  assert.equal(countUnread([{ timestamp: "x" }, {}], h(1), now), 0);
  assert.equal(countUnread([{ timestamp: h(1) }], "kaputt", now), 1);
});
