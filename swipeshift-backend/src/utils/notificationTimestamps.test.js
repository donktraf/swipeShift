const test = require("node:test");
const assert = require("node:assert");
const { acceptedTimestamp, paidTimestamp, reviewDueTimestamp, nextSeenAt } = require("./notificationTimestamps");
const { countUnread } = require("./unreadNotifications");

const t = (s) => new Date(s);

test("acceptedTimestamp bevorzugt acceptedAt, sonst createdAt", () => {
  assert.deepEqual(acceptedTimestamp({ acceptedAt: t("2026-02-01"), createdAt: t("2026-01-01") }), t("2026-02-01"));
  assert.deepEqual(acceptedTimestamp({ acceptedAt: null, createdAt: t("2026-01-01") }), t("2026-01-01"));
});

test("paidTimestamp / reviewDueTimestamp", () => {
  assert.deepEqual(paidTimestamp({ paidAt: t("2026-03-01"), createdAt: t("2026-01-01") }), t("2026-03-01"));
  assert.deepEqual(paidTimestamp({ createdAt: t("2026-01-01") }), t("2026-01-01"));
  assert.deepEqual(reviewDueTimestamp({ job: { endTime: t("2026-02-05") }, createdAt: t("2026-01-01") }), t("2026-02-05"));
  assert.deepEqual(reviewDueTimestamp({ job: { endTime: null }, createdAt: t("2026-01-01") }), t("2026-01-01"));
});

test("Szenario: seen nach Bewerbung, Accept danach → unread", () => {
  const applied = t("2026-11-25T10:00:00Z");
  const seen = t("2026-11-25T11:00:00Z");
  const acceptedAt = t("2026-11-25T12:00:00Z");
  const now = t("2026-11-25T12:30:00Z");
  const list = [{ timestamp: acceptedTimestamp({ acceptedAt, createdAt: applied }) }];
  assert.equal(countUnread(list, seen, now), 1);
  // Altverhalten (createdAt) haette 0 ergeben
  assert.equal(countUnread([{ timestamp: applied }], seen, now), 0);
});

test("nextSeenAt: min(upTo, now), nie rueckwaerts", () => {
  const now = t("2026-11-25T12:00:00Z");
  assert.deepEqual(nextSeenAt(null, "2026-11-25T11:00:00Z", now), t("2026-11-25T11:00:00Z"));
  assert.deepEqual(nextSeenAt(null, "2030-01-01T00:00:00Z", now), now);
  assert.deepEqual(nextSeenAt(null, undefined, now), now);
  assert.deepEqual(nextSeenAt(null, "kaputt", now), now);
  assert.equal(nextSeenAt(t("2026-11-25T11:30:00Z"), "2026-11-25T11:00:00Z", now), null);
  assert.deepEqual(nextSeenAt(t("2026-11-25T10:00:00Z"), "2026-11-25T11:00:00Z", now), t("2026-11-25T11:00:00Z"));
});

test("reviewDueTimestamp: Abschluss nach Schichtende zaehlt (spaeterer Wert)", () => {
  const t = (s) => new Date(s);
  assert.deepEqual(
    reviewDueTimestamp({ job: { endTime: t("2026-02-05T12:00:00Z"), updatedAt: t("2026-02-07T09:00:00Z") }, createdAt: t("2026-01-01") }),
    t("2026-02-07T09:00:00Z"),
  );
});
