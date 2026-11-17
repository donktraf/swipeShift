// src/utils/profileFields.test.js
const { test } = require("node:test");
const assert = require("node:assert/strict");
const P = require("./profileFields");

const NOW = new Date("2026-11-18T12:00:00Z");

test("Whitelists: gueltig, dedupliziert, ungueltig -> Fehler", () => {
  assert.deepEqual(P.validateAvailableTimes(["night", "morning", "morning"]).value, ["morning", "night"]);
  assert.deepEqual(P.validateAvailableTimes(null).value, []);
  assert.ok(P.validateAvailableTimes(["dawn"]).error);
  assert.ok(P.validateAvailableTimes("morning").error);
  assert.deepEqual(P.validateShiftTypes(["weekend", "oneDay"]).value, ["oneDay", "weekend"]);
  // lastMinute ist bewusst kein Chip (Same-day-Schalter)
  assert.ok(P.validateShiftTypes(["lastMinute"]).error);
});

test("validateExperience: Kategorie/Level/Duplikate", () => {
  assert.deepEqual(
    P.validateExperience([{ category: "Retail", level: "gt1y" }, { category: "Events", level: "lt3m" }]).value,
    [{ category: "Retail", level: "gt1y" }, { category: "Events", level: "lt3m" }]
  );
  assert.ok(P.validateExperience([{ category: "Mining", level: "gt1y" }]).error);
  assert.ok(P.validateExperience([{ category: "Retail", level: "expert" }]).error);
  assert.ok(P.validateExperience([{ category: "Retail", level: "lt3m" }, { category: "Retail", level: "gt1y" }]).error);
  assert.ok(P.validateExperience("x").error);
  assert.deepEqual(P.validateExperience([]).value, []);
});

test("cleanExperience/cleanWhitelist verwerfen Muell in Bestandsdaten", () => {
  assert.deepEqual(
    P.cleanExperience([{ category: "Retail", level: "gt1y" }, { category: "Retail", level: "lt3m" }, { category: "X", level: "lt3m" }, null]),
    [{ category: "Retail", level: "gt1y" }]
  );
  assert.deepEqual(P.cleanExperience(null), []);
  assert.deepEqual(P.cleanWhitelist(["night", "foo"], P.AVAILABLE_TIMES), ["night"]);
});

test("validateYearFounded: Bereich 1800..aktuelles Jahr", () => {
  assert.equal(P.validateYearFounded(1999, NOW).value, 1999);
  assert.equal(P.validateYearFounded("2010", NOW).value, 2010);
  assert.equal(P.validateYearFounded(null, NOW).value, null);
  assert.equal(P.validateYearFounded(1800, NOW).value, 1800);
  assert.equal(P.validateYearFounded(2026, NOW).value, 2026);
  assert.ok(P.validateYearFounded(1799, NOW).error);
  assert.ok(P.validateYearFounded(2027, NOW).error);
  assert.ok(P.validateYearFounded(2000.5, NOW).error);
  assert.ok(P.validateYearFounded("abc", NOW).error);
});

test("validateTagline: trim, leer -> null, max 80", () => {
  assert.equal(P.validateTagline("  Great shifts  ").value, "Great shifts");
  assert.equal(P.validateTagline("   ").value, null);
  assert.equal(P.validateTagline("x".repeat(80)).value.length, 80);
  assert.ok(P.validateTagline("x".repeat(81)).error);
});

test("validateZip: US 5 oder 5+4", () => {
  assert.equal(P.validateZip("10001").value, "10001");
  assert.equal(P.validateZip(" 10001-1234 ").value, "10001-1234");
  assert.equal(P.validateZip("").value, null);
  for (const bad of ["1000", "100011", "ABCDE", "10001-12", "10001 1234"]) assert.ok(P.validateZip(bad).error, bad);
});

test("validateCoordinates: Paar + Bereich", () => {
  assert.deepEqual(P.validateCoordinates(40.7, -74).value, { lat: 40.7, lng: -74 });
  assert.deepEqual(P.validateCoordinates(null, null).value, { lat: null, lng: null });
  assert.ok(P.validateCoordinates(40.7, null).error);
  assert.ok(P.validateCoordinates(91, 0).error);
  assert.ok(P.validateCoordinates(0, 181).error);
});

test("normalizeSocialLinks: URL, @handle, Schema ergaenzen, Ablehnung", () => {
  const r = P.normalizeSocialLinks({
    instagram: "@acme.shifts", linkedin: "https://linkedin.com/company/acme",
    facebook: "facebook.com/acme", tiktok: "  ",
  });
  assert.equal(r.value.instagram, "https://instagram.com/acme.shifts");
  assert.equal(r.value.linkedin, "https://linkedin.com/company/acme");
  assert.equal(r.value.facebook, "https://facebook.com/acme");
  assert.equal(r.value.tiktok, undefined);
  assert.equal(P.normalizeSocialLinks({ tiktok: "@acme" }).value.tiktok, "https://www.tiktok.com/@acme");
  assert.ok(P.normalizeSocialLinks({ instagram: "javascript:alert(1)" }).error);
  assert.ok(P.normalizeSocialLinks({ instagram: "ftp://x.com/a" }).error);
  assert.ok(P.normalizeSocialLinks({ instagram: "just words" }).error);
  assert.ok(P.normalizeSocialLinks("x").error);
  assert.equal(P.normalizeSocialLinks({}).value, null);
  assert.equal(P.normalizeSocialLinks(null).value, null);
  // unbekannte Keys werden ignoriert
  assert.equal(P.normalizeSocialLinks({ myspace: "https://a.com" }).value, null);
});

test("cleanSocialLinks: nur http(s) und bekannte Keys", () => {
  assert.deepEqual(P.cleanSocialLinks({ instagram: "https://a.com/x", tiktok: "javascript:1", foo: "https://b.com" }), { instagram: "https://a.com/x" });
  assert.equal(P.cleanSocialLinks({}), null);
  assert.equal(P.cleanSocialLinks(null), null);
});

test("validateWorkerProfileFields: nur uebergebene Felder, Fehler gesammelt", () => {
  const ok = P.validateWorkerProfileFields({ availableTimes: ["morning"], experience: [{ category: "Retail", level: "gt1y" }] });
  assert.deepEqual(Object.keys(ok.data).sort(), ["availableTimes", "experience"]);
  assert.equal(ok.errors.length, 0);
  const bad = P.validateWorkerProfileFields({ availableTimes: ["x"], shiftTypes: ["y"] });
  assert.equal(bad.errors.length, 2);
  assert.deepEqual(P.validateWorkerProfileFields({}).data, {});
});

test("validateEmployerProfileFields: Mapping + Fehler", () => {
  const ok = P.validateEmployerProfileFields({
    yearFounded: 2001, tagline: " Hi ", zipCode: "10001", streetAddress: "1 Main St",
    addressLat: 1, addressLng: 2, postsInMultipleStates: true, remoteFriendly: false,
    publicContactName: "Ann", publicContactRole: "", socialLinks: { instagram: "@a" },
  }, NOW);
  assert.equal(ok.errors.length, 0);
  assert.equal(ok.data.tagline, "Hi");
  assert.equal(ok.data.publicContactRole, null);
  assert.equal(ok.data.addressLat, 1);
  assert.equal(ok.data.socialLinks.instagram, "https://instagram.com/a");
  const bad = P.validateEmployerProfileFields({ yearFounded: 1500, zipCode: "1", remoteFriendly: "yes", addressLat: 5 }, NOW);
  assert.equal(bad.errors.length, 4);
  assert.deepEqual(P.validateEmployerProfileFields({}, NOW).data, {});
});

// ---- Randfaelle ----

test("Whitelists: Gross-/Kleinschreibung, Nicht-Array, Nicht-Strings", () => {
  assert.ok(P.validateAvailableTimes(["Morning"]).error); // case-sensitiv
  assert.ok(P.validateAvailableTimes({}).error);
  assert.ok(P.validateAvailableTimes([null]).error);
  assert.ok(P.validateAvailableTimes([1]).error);
  assert.deepEqual(P.validateAvailableTimes([]).value, []);
  assert.deepEqual(P.validateAvailableTimes(undefined).value, []);
  // ein ungueltiger Wert verwirft die ganze Liste
  assert.ok(P.validateShiftTypes(["oneDay", "nope"]).error);
});

test("validateExperience: fehlende Felder, Nicht-Objekte, Duplikate", () => {
  assert.ok(P.validateExperience([{ category: "Retail" }]).error);
  assert.ok(P.validateExperience([{ level: "gt1y" }]).error);
  assert.ok(P.validateExperience([null]).error);
  assert.ok(P.validateExperience([1]).error);
  assert.ok(P.validateExperience({}).error);
  assert.deepEqual(P.validateExperience(null).value, []);
  // Extra-Felder werden entfernt
  assert.deepEqual(P.validateExperience([{ category: "Retail", level: "gt1y", x: 1 }]).value, [{ category: "Retail", level: "gt1y" }]);
  // Kategorie ist case-sensitiv
  assert.ok(P.validateExperience([{ category: "retail", level: "gt1y" }]).error);
});

test("validateZip: Leerzeichen, Buchstaben, leer, Nicht-String", () => {
  assert.equal(P.validateZip(" 12345 ").value, "12345");
  assert.equal(P.validateZip("   ").value, null);
  assert.equal(P.validateZip(null).value, null);
  assert.equal(P.validateZip(undefined).value, null);
  assert.ok(P.validateZip(12345).error);
  for (const bad of ["1234a", "12345-", "12345-123a", "1 2345"]) assert.ok(P.validateZip(bad).error, bad);
});

test("validateYearFounded: Grenzen, String-Zahl, leer", () => {
  assert.equal(P.validateYearFounded("", NOW).value, null);
  assert.equal(P.validateYearFounded(undefined, NOW).value, null);
  assert.equal(P.validateYearFounded(" 2010 ", NOW).value, 2010);
  assert.equal(P.validateYearFounded("1800", NOW).value, 1800);
  assert.equal(P.validateYearFounded(2026, NOW).value, 2026);
  assert.ok(P.validateYearFounded(2027, NOW).error); // aktuelles Jahr + 1
  assert.ok(P.validateYearFounded("2027", NOW).error);
  assert.ok(P.validateYearFounded("1799", NOW).error);
  for (const bad of ["2010.5", "-1", true, NaN, [], {}]) assert.ok(P.validateYearFounded(bad, NOW).error, String(bad));
});

test("validateTagline: Whitespace zaehlt nicht, Nicht-String", () => {
  assert.equal(P.validateTagline("  " + "x".repeat(80) + "  ").value.length, 80);
  assert.ok(P.validateTagline("  " + "x".repeat(81) + "  ").error);
  assert.equal(P.validateTagline(null).value, null);
  assert.equal(P.validateTagline("").value, null);
  assert.ok(P.validateTagline(5).error);
});

test("normalizeSocialLinks: Handles, Schema, gefaehrliche Schemata, Muell", () => {
  const ig = (v) => P.normalizeSocialLinks({ instagram: v });
  assert.equal(ig("@handle").value.instagram, "https://instagram.com/handle");
  assert.equal(P.normalizeSocialLinks({ linkedin: "@acme" }).value.linkedin, "https://www.linkedin.com/company/acme");
  assert.equal(ig("http://instagram.com/a").value.instagram, "http://instagram.com/a");
  assert.equal(ig("instagram.com/a").value.instagram, "https://instagram.com/a");
  assert.equal(ig("  @handle  ").value.instagram, "https://instagram.com/handle");
  for (const bad of ["handle", "@", "@a b", "instagram.com/a b", "localhost", "//evil.com", "https://nodot",
    "data:text/html,x", "JAVASCRIPT:alert(1)", "javascript:alert(1)", "file:///etc/passwd", "ftp://x.com/a"]) {
    assert.ok(ig(bad).error, bad);
  }
  assert.ok(ig(5).error);
  assert.ok(P.normalizeSocialLinks([]).error);
  assert.equal(ig("").value, null);
  assert.equal(ig(null).value, null);
  assert.equal(P.normalizeSocialLinks({ myspace: "javascript:1" }).value, null); // unbekannt -> ignoriert, nie gespeichert
});

test("validateCoordinates: Grenzen, NaN, Strings", () => {
  assert.deepEqual(P.validateCoordinates(90, 180).value, { lat: 90, lng: 180 });
  assert.deepEqual(P.validateCoordinates(-90, -180).value, { lat: -90, lng: -180 });
  assert.deepEqual(P.validateCoordinates(0, 0).value, { lat: 0, lng: 0 });
  assert.deepEqual(P.validateCoordinates("40.7", "-74").value, { lat: 40.7, lng: -74 });
  assert.deepEqual(P.validateCoordinates("", "").value, { lat: null, lng: null });
  for (const [a, b] of [[90.0001, 0], [-90.1, 0], [0, 180.1], [0, -180.1], [NaN, 0], [0, NaN], [Infinity, 0], ["abc", 1]]) {
    assert.ok(P.validateCoordinates(a, b).error, `${a},${b}`);
  }
  assert.ok(P.validateCoordinates(null, 5).error);
  assert.ok(P.validateCoordinates(5, undefined).error);
  // Nur echte Zahlen oder dezimale Zahl-Strings
  for (const bad of [[true, true], [[], []], ["0x10", "1"], ["1e2", "1"], [{}, 1], ["1,5", "2"]]) {
    assert.ok(P.validateCoordinates(bad[0], bad[1]).error, JSON.stringify(bad));
  }
});

test("validateEmployerProfileFields: Teil-Updates und leere Werte loeschen", () => {
  const r = P.validateEmployerProfileFields({ tagline: "", zipCode: "", yearFounded: "", socialLinks: {}, addressLat: "", addressLng: "" }, NOW);
  assert.equal(r.errors.length, 0);
  assert.deepEqual(r.data, { tagline: null, zipCode: null, yearFounded: null, socialLinks: null, addressLat: null, addressLng: null });
  // nur Lat uebergeben -> Fehler
  assert.equal(P.validateEmployerProfileFields({ addressLat: 1 }, NOW).errors.length, 1);
  // Nicht-String-Texte
  assert.equal(P.validateEmployerProfileFields({ publicContactName: 5, streetAddress: {} }, NOW).errors.length, 2);
  assert.equal(P.validateEmployerProfileFields({ streetAddress: "x".repeat(121) }, NOW).errors.length, 1);
});

test("normalizeSocialLinks: Host-Whitelist, Credentials, Laenge, Schema-Erkennung", () => {
  const n = (key, v) => P.normalizeSocialLinks({ [key]: v });
  // erlaubte Hosts inkl. www./m. und fb.com
  assert.equal(n("facebook", "https://m.facebook.com/acme").value.facebook, "https://m.facebook.com/acme");
  assert.equal(n("facebook", "https://fb.com/acme").value.facebook, "https://fb.com/acme");
  assert.equal(n("tiktok", "https://www.tiktok.com/@acme").value.tiktok, "https://www.tiktok.com/@acme");
  assert.equal(n("linkedin", "https://www.linkedin.com/company/acme").value.linkedin, "https://www.linkedin.com/company/acme");
  // falscher Host / Netzwerk-Mismatch / Lookalikes
  for (const [k, v] of [["instagram", "https://evil.com/a"], ["instagram", "https://facebook.com/a"],
    ["instagram", "https://instagram.com.evil.com/a"], ["instagram", "https://notinstagram.com/a"],
    ["tiktok", "https://instagram.com/a"]]) {
    assert.ok(n(k, v).error, `${k} ${v}`);
  }
  // Credentials in der URL
  assert.ok(n("instagram", "https://user:pw@instagram.com/a").error);
  assert.match(n("instagram", "https://user@instagram.com/a").error, /username or password/);
  // ueberlang
  assert.match(n("instagram", "https://instagram.com/" + "a".repeat(300)).error, /too long/);
  // "evil.com:8080/x" ist kein Schema -> scheitert an der Host-Whitelist
  assert.match(n("instagram", "evil.com:8080/x").error, /must point to/);
  assert.ok(n("instagram", "javascript:alert(1)").error);
});
