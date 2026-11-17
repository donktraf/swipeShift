// src/utils/jobData.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { formatAmount, formatPayText, buildJobData, validateJobBody, checkDraftAccess } = require("./jobData");

test("buildJobData: Defaults bei minimalem Body", () => {
  const d = buildJobData({ title: "A", category: "Events" });
  assert.equal(d.company, "Unknown");
  assert.equal(d.payText, "On request");
  assert.equal(d.openSpots, 1);
  assert.equal(d.lat, null);
  assert.deepEqual(d.shifts, []);
  assert.equal(d.shiftText, "");
  assert.equal(d.startTime, null);
});

test("buildJobData: Ableitungen aus shifts[0], Lohn und Beschreibung", () => {
  const d = buildJobData({
    title: "A", category: "Events", payAmount: "15.5", location: "Berlin", lat: "52.5", lng: 13.4,
    minAge: "18", jobDescription: "x".repeat(200),
    shifts: [{ date: "Mon", timeRange: "9-17", startTimeISO: "2026-12-01T09:00:00Z", endTimeISO: "2026-12-01T17:00:00Z", duration: "8h" }],
  });
  assert.equal(d.payAmount, 15.5);
  assert.equal(d.payText, "$15.50 / hr");
  assert.equal(d.lat, 52.5);
  assert.equal(d.lng, 13.4);
  assert.equal(d.minAge, 18);
  assert.equal(d.shiftText, "Mon, 9-17");
  assert.equal(d.startTime.toISOString(), "2026-12-01T09:00:00.000Z");
  assert.equal(d.duration, "8h");
  assert.equal(d.shortInfo.length, 120);
});

test("buildJobData: leere/fehlende shifts -> keine Ableitungen", () => {
  for (const shifts of [undefined, null, []]) {
    const d = buildJobData({ title: "A", shifts });
    assert.deepEqual(d.shifts, shifts ?? []);
    assert.equal(d.shiftText, "");
    assert.equal(d.startTime, null);
    assert.equal(d.endTime, null);
    assert.equal(d.duration, null);
  }
});

test("buildJobData: shift ohne ISO-Zeiten/Dauer, nur shifts[0] zaehlt", () => {
  const d = buildJobData({ shifts: [
    { date: "Tue", timeRange: "8-12" },
    { date: "Wed", timeRange: "9-10", startTimeISO: "2026-12-02T09:00:00Z", duration: "1h" },
  ] });
  assert.equal(d.shiftText, "Tue, 8-12");
  assert.equal(d.startTime, null);
  assert.equal(d.duration, null);
  assert.equal(d.shifts.length, 2);
});

test("buildJobData: payAmount als Zahl, String, leer, 0", () => {
  assert.equal(buildJobData({ payAmount: 20 }).payAmount, 20);
  assert.equal(buildJobData({ payAmount: 20 }).payText, "$20 / hr");
  assert.equal(buildJobData({ payAmount: "12.75" }).payAmount, 12.75);
  assert.equal(buildJobData({ payAmount: "12.75" }).payText, "$12.75 / hr");
  for (const p of ["", null, undefined, 0]) {
    const d = buildJobData({ payAmount: p });
    assert.equal(d.payAmount, null);
    assert.equal(d.payText, "On request");
  }
});

test("buildJobData: expliziter payText hat Vorrang", () => {
  const d = buildJobData({ payAmount: 10, payText: "Custom" });
  assert.equal(d.payText, "Custom");
  assert.equal(d.payAmount, 10);
});

test("buildJobData: Tags/Tasks/Languages fehlen -> leere Arrays", () => {
  const d = buildJobData({ title: "A" });
  assert.deepEqual(d.tags, []);
  assert.deepEqual(d.tasks, []);
  assert.deepEqual(d.languages, []);
  const e = buildJobData({ tags: ["x"], tasks: ["t"], languages: ["de"] });
  assert.deepEqual(e.tags, ["x"]);
  assert.deepEqual(e.tasks, ["t"]);
  assert.deepEqual(e.languages, ["de"]);
});

test("buildJobData: status ist nicht Teil des Ergebnisses (Route setzt ihn)", () => {
  assert.equal("status" in buildJobData({ status: "draft" }), false);
  assert.equal("employerId" in buildJobData({ employerId: "x" }), false);
});

test("buildJobData: minAge-Parsing", () => {
  assert.equal(buildJobData({ minAge: "18" }).minAge, 18);
  assert.equal(buildJobData({ minAge: 21 }).minAge, 21);
  assert.equal(buildJobData({ minAge: "" }).minAge, null);
  assert.equal(buildJobData({}).minAge, null);
  assert.equal(buildJobData({ minAge: "abc" }).minAge, NaN); // buildJobData selbst prueft nicht; validateJobBody faengt das ab
});

test("buildJobData: shortInfo 120 Zeichen, kurz bleibt, leer -> '' / jobDescription null", () => {
  assert.equal(buildJobData({ jobDescription: "y".repeat(120) }).shortInfo.length, 120);
  assert.equal(buildJobData({ jobDescription: "kurz" }).shortInfo, "kurz");
  const d = buildJobData({ jobDescription: "" });
  assert.equal(d.shortInfo, "");
  assert.equal(d.jobDescription, null);
  assert.equal(buildJobData({ jobDescription: "z".repeat(300) }).jobDescription.length, 300);
});

test("buildJobData: company/openSpots/location/lat-lng Defaults", () => {
  assert.equal(buildJobData({ company: "" }).company, "Unknown");
  assert.equal(buildJobData({ company: "ACME" }).company, "ACME");
  assert.equal(buildJobData({ openSpots: 0 }).openSpots, 1);
  assert.equal(buildJobData({ openSpots: 5 }).openSpots, 5);
  assert.equal(buildJobData({}).location, "");
  assert.equal(buildJobData({ lat: 0, lng: 0 }).lat, 0);
  assert.equal(buildJobData({ lat: null }).lat, null);
  assert.equal(buildJobData().company, "Unknown");
  assert.equal(buildJobData({}).logoEmoji, "🏢");
});

test("validateJobBody: gueltige und leere Werte", () => {
  assert.equal(validateJobBody({}), null);
  assert.equal(validateJobBody(), null);
  assert.equal(validateJobBody({ lat: "52.5", lng: 0, payAmount: "12.5", minAge: "18", payText: "x" }), null);
  assert.equal(validateJobBody({ lat: null, payAmount: "", minAge: undefined }), null);
  assert.equal(validateJobBody({ shifts: [], tags: ["a"], tasks: [], languages: null }), null);
});

test("validateJobBody: nicht endliche Zahlen -> Meldung", () => {
  for (const f of ["lat", "lng", "payAmount", "minAge"]) {
    assert.match(validateJobBody({ [f]: "abc" }), new RegExp(f));
  }
  assert.ok(validateJobBody({ lat: Infinity }));
  assert.ok(validateJobBody({ payAmount: NaN }));
});

test("validateJobBody: Array-Felder", () => {
  for (const f of ["shifts", "tags", "tasks", "languages"]) {
    assert.match(validateJobBody({ [f]: "x" }), new RegExp(f));
    assert.match(validateJobBody({ [f]: {} }), new RegExp(f));
  }
});

test("checkDraftAccess: 404 / 403 / 409 / erlaubt", () => {
  assert.equal(checkDraftAccess(null, "u").status, 404);
  assert.equal(checkDraftAccess({ employerId: "o", status: "draft" }, "u").status, 403);
  const c = checkDraftAccess({ employerId: "u", status: "published" }, "u");
  assert.equal(c.status, 409);
  assert.equal(c.code, "NOT_DRAFT");
  assert.equal(checkDraftAccess({ employerId: "u", status: "draft" }, "u"), null);
});

test("validateJobBody: openSpots must be a whole number", () => {
  const { validateJobBody } = require("./jobData");
  assert.equal(validateJobBody({ openSpots: 3 }), null);
  assert.equal(validateJobBody({ openSpots: "2" }), null);
  assert.equal(validateJobBody({ openSpots: "" }), null);
  assert.match(validateJobBody({ openSpots: "abc" }), /openSpots/);
  assert.match(validateJobBody({ openSpots: 1.5 }), /openSpots/);
});

test("buildJobData: empty-string lat/lng become null instead of NaN", () => {
  const { buildJobData } = require("./jobData");
  const d = buildJobData({ title: "t", lat: "", lng: "" });
  assert.equal(d.lat, null);
  assert.equal(d.lng, null);
});

test("formatPayText: Dollar-Format", () => {
  assert.equal(formatPayText(18), "$18 / hr");
  assert.equal(formatPayText("12.75"), "$12.75 / hr");
});

test("formatAmount: ganz ohne, sonst 2 Nachkommastellen, Cent-Rundung", () => {
  assert.equal(formatAmount(18), "$18");
  assert.equal(formatAmount(15.5), "$15.50");
  assert.equal(formatAmount(1250.75), "$1250.75");
  assert.equal(formatAmount("12.999"), "$13");
  assert.equal(formatAmount(0.005), "$0.01");
});
