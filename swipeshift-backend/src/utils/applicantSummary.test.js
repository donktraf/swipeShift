const test = require("node:test");
const assert = require("node:assert/strict");
const {
  groupBy, sortedExperience, buildTags, compactDays, availabilityText, summarizeApplicant, averageRating,
} = require("./applicantSummary");

const NOW = new Date("2026-11-17T12:00:00Z");

test("groupBy: gruppiert nach Schluessel und ignoriert Zeilen ohne Schluessel", () => {
  const map = groupBy([{ w: "a", n: 1 }, { w: "b", n: 2 }, { w: "a", n: 3 }, { n: 4 }, null], "w");
  assert.deepEqual(map.get("a").map((r) => r.n), [1, 3]);
  assert.equal(map.get("b").length, 1);
  assert.equal(map.size, 2);
  assert.equal(groupBy(undefined, "w").size, 0);
});

test("sortedExperience: staerkstes Level zuerst, ungueltige Eintraege fliegen raus", () => {
  const out = sortedExperience([
    { category: "Retail", level: "lt3m" },
    { category: "Hospitality", level: "gt1y" },
    { category: "Nonsense", level: "gt1y" },
    { category: "Events", level: "m3to12" },
  ]);
  assert.deepEqual(out.map((e) => e.text), ["Hospitality · 1+ yrs", "Events · 3–12 mo", "Retail · <3 mo"]);
  assert.deepEqual(sortedExperience(null), []);
});

test("buildTags: max. 3, Erfahrung vor Skills, Skills nur ab 4", () => {
  const exp = [{ category: "Hospitality", level: "gt1y" }];
  const skills = { communication: 5, teamwork: 3, reliability: 4, underPressure: 4 };
  assert.deepEqual(buildTags(exp, skills), ["Hospitality · 1+ yrs", "Communication", "Reliability"]);
  assert.deepEqual(buildTags(null, { communication: 2, teamwork: 2, reliability: 2, underPressure: 2 }), []);
  assert.deepEqual(buildTags(null, { communication: 5 }), []); // unvollstaendige Skills werden ignoriert
  const many = ["Hospitality", "Events", "Retail", "Office"].map((category) => ({ category, level: "gt1y" }));
  assert.equal(buildTags(many, skills).length, 3);
});

test("compactDays: Bereiche ab 3 Tagen, sonst einzeln", () => {
  assert.equal(compactDays(["Fri", "Mon", "Tue", "Wed", "Thu"]), "Mon–Fri");
  assert.equal(compactDays(["Mon", "Tue", "Sat"]), "Mon, Tue, Sat");
  assert.equal(compactDays(["Mon", "Tue", "Wed", "Sat", "Sun"]), "Mon–Wed, Sat, Sun");
  assert.equal(compactDays(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]), "Every day");
  assert.equal(compactDays([]), "");
  assert.equal(compactDays(undefined), "");
});

test("availabilityText: Tage + Tageszeiten, null ohne Angaben", () => {
  const availability = ["Mon", "Tue", "Wed"].map((name) => ({ name, available: true }));
  assert.equal(availabilityText(availability, ["evening", "morning", "bogus"]), "Mon–Wed · Morning, Evening");
  assert.equal(availabilityText([], ["night"]), "Night");
  assert.equal(availabilityText(null, null), null);
});

test("summarizeApplicant: neuer Worker ohne Daten", () => {
  const s = summarizeApplicant({ now: NOW });
  assert.equal(s.ratingAverage, null);
  assert.equal(s.reviewCount, 0);
  assert.equal(s.completedJobs, 0);
  assert.deepEqual(s.tags, []);
  assert.equal(s.strongestExperience, null);
  assert.equal(s.isAdult, false);
  assert.equal(s.availabilityText, null);
});

test("summarizeApplicant: Bewertungen (workQuality null), abgeschlossene Jobs, 18+", () => {
  const s = summarizeApplicant({
    worker: {
      dateOfBirth: new Date("2000-01-01T00:00:00Z"),
      experience: [{ category: "Events", level: "m3to12" }],
    },
    reviews: [
      { communication: 5, teamwork: 4, reliability: 5, underPressure: 4, workQuality: null },
      { communication: 3, teamwork: 3, reliability: 3, underPressure: 3, workQuality: 3 },
    ],
    applies: [
      { status: "accepted", isPaid: true, job: { category: "Events", endTime: "2026-11-01T10:00:00Z", status: "completed" } },
      { status: "accepted", isPaid: false, job: { category: "Events", endTime: "2026-12-01T10:00:00Z", status: "published" } },
    ],
    now: NOW,
  });
  assert.equal(s.ratingAverage, 3.8); // (4.5 + 3) / 2 = 3.75 -> 3.8
  assert.equal(s.reviewCount, 2);
  assert.equal(s.completedJobs, 1);
  assert.equal(s.isAdult, true);
  assert.equal(s.strongestExperience, "Events · 3–12 mo");
  assert.ok(!("age" in s));
});

test("summarizeApplicant: unter 18 bekommt kein Badge", () => {
  const s = summarizeApplicant({ worker: { dateOfBirth: new Date("2010-01-01T00:00:00Z") }, now: NOW });
  assert.equal(s.isAdult, false);
});

test("averageRating: nur bewertete Worker zaehlen", () => {
  assert.equal(averageRating([{ ratingAverage: 5 }, { ratingAverage: 4 }, { ratingAverage: null }]), 4.5);
  assert.equal(averageRating([{ ratingAverage: null }]), null);
  assert.equal(averageRating([]), null);
  assert.equal(averageRating(undefined), null);
});
