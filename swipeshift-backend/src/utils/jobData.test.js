// src/utils/jobData.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const { formatAmount, formatPayText, buildJobData, validateJobBody, checkDraftAccess, hasAcceptedTerms, TERMS_REQUIRED_ERROR, resolveCreateStatus, evaluateStatusChange, shouldAutoAccept } = require("./jobData");
const { computeResponseStats } = require("./responseStats");

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

test("buildJobData: Zusatzfelder Defaults", () => {
  const d = buildJobData({ title: "A" });
  assert.deepEqual(d.requiredSkills, []);
  assert.deepEqual(d.physicalRequirements, []);
  assert.deepEqual(d.certifications, []);
  assert.equal(d.educationLevel, null);
  assert.equal(d.urgency, "normal");
  assert.equal(d.locationType, "single");
  assert.equal(d.breakIncluded, false);
  assert.equal(d.breakMinutes, null);
  assert.equal(d.bonusDescription, null);
  assert.equal(d.cancellationPolicy, null);
  assert.equal(d.instantMatch, false);
  assert.equal(d.workAuthorizationRequired, false);
});

test("buildJobData: Zusatzfelder werden uebernommen und abhaengige Felder bereinigt", () => {
  const d = buildJobData({
    requiredSkills: ["Teamwork", "Teamwork"], certifications: ["Forklift License"],
    educationLevel: "College Degree", urgency: "urgent", locationType: "multiple",
    breakIncluded: true, breakMinutes: "30", bonusAvailable: true, bonusDescription: "  $50 bonus  ",
    cancellationPolicy: "24h", jobNotes: "Meet at gate", instantMatch: true, sameDayPay: true,
  });
  assert.deepEqual(d.requiredSkills, ["Teamwork"]);
  assert.equal(d.breakMinutes, 30);
  assert.equal(d.bonusDescription, "$50 bonus");
  assert.equal(d.urgency, "urgent");
  assert.equal(d.locationType, "multiple");
  assert.equal(d.instantMatch, true);
  assert.equal(d.sameDayPay, true);

  const off = buildJobData({ breakIncluded: false, breakMinutes: 30, bonusAvailable: false, bonusDescription: "x" });
  assert.equal(off.breakMinutes, null);
  assert.equal(off.bonusDescription, null);
});

test("validateJobBody: Zusatzfelder", () => {
  assert.equal(validateJobBody({ requiredSkills: ["Teamwork"], urgency: "urgent", breakMinutes: 15 }), null);
  assert.match(validateJobBody({ requiredSkills: "Teamwork" }), /array/);
  assert.match(validateJobBody({ certifications: ["Pilot"] }), /unsupported/);
  assert.match(validateJobBody({ urgency: "asap" }), /urgency/);
  assert.match(validateJobBody({ locationType: "x" }), /locationType/);
  assert.match(validateJobBody({ educationLevel: "PhD" }), /educationLevel/);
  assert.match(validateJobBody({ cancellationPolicy: "never" }), /cancellationPolicy/);
  assert.match(validateJobBody({ breakMinutes: 20 }), /breakMinutes/);
  assert.match(validateJobBody({ instantMatch: "true" }), /boolean/);
  assert.match(validateJobBody({ jobNotes: "x".repeat(501) }), /500/);
  assert.match(validateJobBody({ cancellationNotes: "x".repeat(301) }), /300/);
  assert.match(validateJobBody({ bonusDescription: "x".repeat(201) }), /200/);
  assert.equal(validateJobBody({ jobNotes: "x".repeat(500) }), null);
});

test("hasAcceptedTerms: nur striktes true", () => {
  assert.equal(hasAcceptedTerms({ termsAccepted: true }), true);
  for (const v of [undefined, false, "true", 1]) assert.equal(hasAcceptedTerms({ termsAccepted: v }), false);
  assert.equal(hasAcceptedTerms(), false);
  assert.equal(TERMS_REQUIRED_ERROR.code, "TERMS_REQUIRED");
});

test("computeResponseStats: autoAccepted wird ignoriert", () => {
  const old = new Date(Date.now() - 100 * 3600 * 1000);
  const real = [1, 2, 3].map(() => ({ status: "accepted", createdAt: old, respondedAt: new Date(old.getTime() + 3600 * 1000) }));
  const auto = Array.from({ length: 10 }, () => ({ status: "accepted", createdAt: old, respondedAt: null, autoAccepted: true }));
  assert.deepEqual(computeResponseStats([...real, ...auto]), computeResponseStats(real));
  assert.equal(computeResponseStats([...real, ...auto]).responseSampleSize, 3);
  assert.equal(computeResponseStats(auto).responseRate, null);
});

test("resolveCreateStatus: nur draft/published", () => {
  assert.deepEqual(resolveCreateStatus(undefined), { status: "published" });
  assert.deepEqual(resolveCreateStatus("draft"), { status: "draft" });
  for (const bad of ["completed", "inProgress", "cancelled", "", 5]) assert.ok(resolveCreateStatus(bad).error);
});

test("evaluateStatusChange: Publish braucht Terms bei jedem Wechsel nach published", () => {
  for (const from of ["draft", "cancelled", "completed", "inProgress"]) {
    const denied = evaluateStatusChange(from, "published", {});
    if (from === "draft" || from === "cancelled" || from === "completed" || from === "inProgress") {
      assert.equal(denied.ok, false, from);
      assert.equal(denied.status, 400);
      assert.equal(denied.body.code, "TERMS_REQUIRED");
    }
    assert.deepEqual(evaluateStatusChange(from, "published", { termsAccepted: true }), { ok: true, publishing: true });
  }
  // published → published ist kein Publish-Wechsel
  assert.deepEqual(evaluateStatusChange("published", "published", {}), { ok: true, publishing: false });
});

test("evaluateStatusChange: Draft nur zu published/cancelled, ungueltiger Status", () => {
  assert.equal(evaluateStatusChange("draft", "completed").status, 409);
  assert.equal(evaluateStatusChange("draft", "inProgress").body.code, "INVALID_TRANSITION");
  assert.deepEqual(evaluateStatusChange("draft", "cancelled"), { ok: true, publishing: false });
  assert.equal(evaluateStatusChange("published", "bogus").status, 400);
  assert.deepEqual(evaluateStatusChange("published", "cancelled"), { ok: true, publishing: false });
});

test("shouldAutoAccept: Instant Match, Plaetze und harte Anforderungen", () => {
  const now = new Date("2026-11-18T00:00:00Z");
  const worker = { dateOfBirth: new Date("2000-01-01"), workAuthorization: true };
  const job = { instantMatch: true, openSpots: 2, minAge: 18, workAuthorizationRequired: true };
  assert.equal(shouldAutoAccept({ job, worker, acceptedCount: 1, now }), true);
  assert.equal(shouldAutoAccept({ job, worker, acceptedCount: 2, now }), false);
  assert.equal(shouldAutoAccept({ job: { ...job, instantMatch: false }, worker, acceptedCount: 0, now }), false);
  // zu jung / Geburtsdatum fehlt
  assert.equal(shouldAutoAccept({ job, worker: { ...worker, dateOfBirth: new Date("2012-01-01") }, acceptedCount: 0, now }), false);
  assert.equal(shouldAutoAccept({ job, worker: { ...worker, dateOfBirth: null }, acceptedCount: 0, now }), false);
  assert.equal(shouldAutoAccept({ job, worker: null, acceptedCount: 0, now }), false);
  // ohne minAge ist das Alter egal
  assert.equal(shouldAutoAccept({ job: { ...job, minAge: null }, worker: { ...worker, dateOfBirth: null }, acceptedCount: 0, now }), true);
  // Arbeitserlaubnis
  assert.equal(shouldAutoAccept({ job, worker: { ...worker, workAuthorization: false }, acceptedCount: 0, now }), false);
  assert.equal(shouldAutoAccept({ job: { ...job, workAuthorizationRequired: false }, worker: { ...worker, workAuthorization: false }, acceptedCount: 0, now }), true);
});
