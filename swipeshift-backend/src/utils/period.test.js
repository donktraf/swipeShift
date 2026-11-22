// src/utils/period.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { resolvePeriod, isInPeriod, prismaRange, buildBuckets, parseDay } = require("./period");

const now = new Date(2026, 10, 16, 12, 0, 0); // 16. Nov 2026, lokal

test("resolvePeriod: Default ist thisMonth", () => {
  const p = resolvePeriod({}, now);
  assert.equal(p.period, "thisMonth");
  assert.deepEqual(p.since, new Date(2026, 10, 1));
  assert.deepEqual(p.until, new Date(2026, 10, 30, 23, 59, 59, 999));
  assert.equal(p.chartEnd.getDate(), 30);
});

test("resolvePeriod: Schicht im naechsten Jahr zaehlt nicht zu thisMonth/thisYear", () => {
  const nextJan = new Date(2027, 0, 15, 9);
  assert.equal(isInPeriod(nextJan, resolvePeriod({ period: "thisMonth" }, now)), false);
  assert.equal(isInPeriod(nextJan, resolvePeriod({ period: "thisYear" }, now)), false);
  assert.equal(isInPeriod(nextJan, resolvePeriod({ period: "allTime" }, now)), true);
  assert.equal(isInPeriod(new Date(2026, 10, 30, 20), resolvePeriod({ period: "thisMonth" }, now)), true);
});

test("resolvePeriod: last3Months / thisYear / allTime", () => {
  assert.deepEqual(resolvePeriod({ period: "last3Months" }, now).since, new Date(2026, 7, 1));
  assert.deepEqual(resolvePeriod({ period: "thisYear" }, now).since, new Date(2026, 0, 1));
  const all = resolvePeriod({ period: "allTime" }, now);
  assert.equal(all.since, null); assert.equal(all.until, null);
});

test("resolvePeriod: custom inklusive beider Tage", () => {
  const p = resolvePeriod({ period: "custom", from: "2026-10-05", to: "2026-10-20" }, now);
  assert.deepEqual(p.since, new Date(2026, 9, 5));
  assert.deepEqual(p.until, new Date(2026, 9, 20, 23, 59, 59, 999));
});

test("resolvePeriod: Fehlerfaelle", () => {
  assert.ok(resolvePeriod({ period: "bogus" }, now).error);
  assert.ok(resolvePeriod({ period: "custom" }, now).error);
  assert.ok(resolvePeriod({ period: "custom", from: "2026-10-20", to: "2026-10-05" }, now).error);
  assert.ok(resolvePeriod({ period: "custom", from: "2026-02-30", to: "2026-03-05" }, now).error);
  assert.ok(resolvePeriod({ period: "custom", from: "2000-01-01", to: "2026-01-01" }, now).error);
});

test("parseDay: nur YYYY-MM-DD", () => {
  assert.equal(parseDay("16.11.2026"), null);
  assert.equal(parseDay(undefined), null);
  assert.deepEqual(parseDay("2026-11-16"), new Date(2026, 10, 16));
});

test("isInPeriod: Grenzen und fehlendes Datum", () => {
  const p = resolvePeriod({ period: "custom", from: "2026-10-05", to: "2026-10-20" }, now);
  assert.equal(isInPeriod(new Date(2026, 9, 20, 22), p), true);
  assert.equal(isInPeriod(new Date(2026, 9, 21, 0, 1), p), false);
  assert.equal(isInPeriod(new Date(2026, 9, 4, 23), p), false);
  assert.equal(isInPeriod(null, p), false);
  assert.equal(isInPeriod(null, resolvePeriod({ period: "allTime" }, now)), true);
});

test("prismaRange", () => {
  assert.equal(prismaRange({ since: null, until: null }), undefined);
  const s = new Date(2026, 0, 1);
  assert.deepEqual(prismaRange({ since: s, until: null }), { gte: s });
  const u = new Date(2026, 11, 31);
  assert.deepEqual(prismaRange({ since: s, until: u }), { gte: s, lte: u });
});

test("buildBuckets: Monat → Tage, 3 Monate → Wochen, Jahr → Monate", () => {
  const month = resolvePeriod({ period: "thisMonth" }, now);
  const days = buildBuckets(month.chartStart, month.chartEnd);
  assert.equal(days.length, 30);
  assert.equal(days[0].unit, "day");
  assert.equal(days[29].label, "30");

  const q = resolvePeriod({ period: "last3Months" }, now); // 1. Aug – 30. Nov = 122 Tage
  const qb = buildBuckets(q.chartStart, q.chartEnd);
  assert.equal(qb[0].unit, "month"); // > 16 Wochen → Monate
  assert.equal(qb.length, 4);

  const year = resolvePeriod({ period: "thisYear" }, now);
  const months = buildBuckets(year.chartStart, year.chartEnd);
  assert.equal(months.length, 12);
  assert.equal(months[0].label, "Jan");
});

test("buildBuckets: 6 Wochen → Wochen, lueckenlos und ohne Ueberlappung", () => {
  const b = buildBuckets(new Date(2026, 9, 1), new Date(2026, 10, 11, 23, 59, 59, 999));
  assert.equal(b[0].unit, "week");
  assert.equal(b.length, 6);
  for (let i = 1; i < b.length; i++) assert.ok(b[i].start > b[i - 1].end);
  assert.deepEqual(b[b.length - 1].end, new Date(2026, 10, 11, 23, 59, 59, 999));
});

test("buildBuckets: Jahresuebergreifend mit Jahr im Label", () => {
  const b = buildBuckets(new Date(2025, 10, 1), new Date(2026, 1, 28, 23, 59, 59, 999));
  assert.equal(b[0].unit, "month");
  assert.equal(b[0].label, "Nov 25");
});

test("currentWeekRange: Montag bis Sonntag der laufenden Woche", () => {
  const { currentWeekRange } = require("./period");
  // Mo 16. Nov 2026 12:00 → Woche 16.–22. Nov
  const mon = currentWeekRange(new Date(2026, 10, 16, 12));
  assert.deepEqual(mon.since, new Date(2026, 10, 16));
  assert.deepEqual(mon.until, new Date(2026, 10, 22, 23, 59, 59, 999));
  // So 22. Nov gehoert noch zur selben Woche, Mo 23. Nov zur naechsten
  assert.deepEqual(currentWeekRange(new Date(2026, 10, 22, 23, 0)).since, new Date(2026, 10, 16));
  assert.deepEqual(currentWeekRange(new Date(2026, 10, 23, 0, 0)).since, new Date(2026, 10, 23));
  // Monats-/Jahreswechsel: Mi 30. Dez 2026 → Woche 28. Dez – 3. Jan
  const wrap = currentWeekRange(new Date(2026, 11, 30, 9));
  assert.deepEqual(wrap.since, new Date(2026, 11, 28));
  assert.deepEqual(wrap.until, new Date(2027, 0, 3, 23, 59, 59, 999));
});

test("bookingPeriodPrefilter: positive Grobklauseln", () => {
  const { bookingPeriodPrefilter } = require("./period");
  const since = new Date(Date.UTC(2030, 0, 1)), until = new Date(Date.UTC(2030, 0, 31));
  assert.deepEqual(bookingPeriodPrefilter({ since, until }), { startTime: { lte: until }, OR: [{ endTime: { gte: since } }, { endTime: null }] });
  assert.deepEqual(bookingPeriodPrefilter({ since: null, until: null }), {});
});
