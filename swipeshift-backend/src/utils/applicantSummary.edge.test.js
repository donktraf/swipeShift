const test = require("node:test");
const assert = require("node:assert/strict");
const { summarizeApplicant, buildTags, availabilityText } = require("./applicantSummary");

const NOW = new Date("2026-11-17T12:00:00Z");
const allDays = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].map((name) => ({ name, available: true }));
const fullSkills = (o = {}) => ({ communication: 1, teamwork: 1, reliability: 1, underPressure: 1, ...o });

test("keine Reviews: ratingAverage null, reviewCount 0", () => {
  const s = summarizeApplicant({ worker: {}, reviews: [], now: NOW });
  assert.equal(s.ratingAverage, null);
  assert.equal(s.reviewCount, 0);
});

test("Review nur mit workQuality null zaehlt trotzdem", () => {
  const s = summarizeApplicant({
    reviews: [{ communication: 4, teamwork: 4, reliability: 4, underPressure: 4, workQuality: null }], now: NOW,
  });
  assert.equal(s.ratingAverage, 4);
  assert.equal(s.reviewCount, 1);
});

test("Alter: genau 18 heute ja, 17 Jahre 364 Tage nein", () => {
  assert.equal(summarizeApplicant({ worker: { dateOfBirth: new Date("2008-11-17T00:00:00Z") }, now: NOW }).isAdult, true);
  assert.equal(summarizeApplicant({ worker: { dateOfBirth: new Date("2008-11-18T00:00:00Z") }, now: NOW }).isAdult, false);
});

test("fehlendes/ungueltiges Geburtsdatum: kein Badge", () => {
  assert.equal(summarizeApplicant({ worker: { dateOfBirth: null }, now: NOW }).isAdult, false);
  assert.equal(summarizeApplicant({ worker: {}, now: NOW }).isAdult, false);
  assert.equal(summarizeApplicant({ worker: { dateOfBirth: "kaputt" }, now: NOW }).isAdult, false);
});

test("keine Erfahrung + keine Skills: keine Tags", () => {
  const s = summarizeApplicant({ worker: { experience: [], skills: null }, now: NOW });
  assert.deepEqual(s.tags, []);
  assert.equal(s.strongestExperience, null);
});

test(">3 moegliche Tags: auf 3 begrenzt, staerkstes Level zuerst, keine Skills mehr", () => {
  const experience = [
    { category: "Retail", level: "lt3m" },
    { category: "Events", level: "m3to12" },
    { category: "Hospitality", level: "gt1y" },
    { category: "Office", level: "gt1y" },
  ];
  const tags = buildTags(experience, fullSkills({ communication: 5 }));
  assert.deepEqual(tags, ["Hospitality · 1+ yrs", "Office · 1+ yrs", "Events · 3–12 mo"]);
});

test("Skills: 4 wird Tag, 3 nicht; hoehere Werte zuerst", () => {
  assert.deepEqual(buildTags([], fullSkills({ teamwork: 3 })), []);
  assert.deepEqual(buildTags([], fullSkills({ teamwork: 4 })), ["Teamwork"]);
  assert.deepEqual(buildTags([], fullSkills({ communication: 4, reliability: 5 })), ["Reliability", "Communication"]);
});

test("Skills fuellen nur freie Plaetze nach Erfahrung auf", () => {
  const exp = [{ category: "Events", level: "gt1y" }, { category: "Retail", level: "lt3m" }];
  assert.deepEqual(buildTags(exp, fullSkills({ reliability: 5, teamwork: 4 })), ["Events · 1+ yrs", "Retail · <3 mo", "Reliability"]);
});

test("Verfuegbarkeit: leer, alle Tage, nur Tageszeiten", () => {
  assert.equal(availabilityText([], []), null);
  assert.equal(availabilityText(undefined, undefined), null);
  assert.equal(availabilityText(allDays, []), "Every day");
  assert.equal(availabilityText([], ["afternoon", "night"]), "Afternoon, Night");
  assert.equal(availabilityText(allDays.map((d) => ({ ...d, available: false })), []), null);
});

test("unbekannte Kategorien/Level im Rohdatensatz werden ignoriert", () => {
  const s = summarizeApplicant({
    worker: { experience: [
      { category: "Spaceflight", level: "gt1y" },
      { category: "Retail", level: "godlike" },
      { category: "Events" },
      null, "x",
      { category: "Cleaning", level: "lt3m" },
    ] }, now: NOW,
  });
  assert.deepEqual(s.tags, ["Cleaning · <3 mo"]);
  assert.equal(s.strongestExperience, "Cleaning · <3 mo");
});

test("Muell als experience/skills/availability crasht nicht", () => {
  const s = summarizeApplicant({ worker: { experience: "abc", skills: 5, availability: {}, availableTimes: "x" }, reviews: null, applies: null, now: NOW });
  assert.deepEqual(s.tags, []);
  assert.equal(s.availabilityText, null);
});
