const { test } = require("node:test");
const assert = require("node:assert/strict");
const sb = require("./shiftBooking");

const at = (d, h, len) => {
  const st = new Date(Date.UTC(2030, 0, d, h));
  return { startTimeISO: st.toISOString(), endTimeISO: new Date(st.getTime() + len * 3_600_000).toISOString() };
};
const job = (extra = {}) => ({
  payAmount: 20, openSpots: 1, platformFeePercent: null,
  shifts: [{ id: "a", date: "Mon 12", ...at(12, 9, 4) }, { id: "b", date: "Tue 13", ...at(13, 9, 2) }],
  ...extra,
});
const NOW = new Date(Date.UTC(2030, 0, 1));

test("assignShiftIds: ergaenzt fehlende, bereinigt doppelte, behaelt vorhandene", () => {
  const r = sb.assignShiftIds([{ id: "x" }, {}, { id: "x" }, { id: "s2" }]);
  assert.equal(r[0].id, "x");
  assert.equal(r[1].id, "s2");
  assert.equal(new Set(r.map((s) => s.id)).size, 4);
  assert.deepEqual(sb.assignShiftIds([]), []);
  assert.equal(sb.assignShiftIds(undefined), undefined);
});

test("jobShifts: Stunden je Schicht, ids, Altdaten-Fallbacks", () => {
  assert.deepEqual(sb.jobShifts(job()).map((s) => [s.id, s.hours]), [["a", 4], ["b", 2]]);
  // Altdaten ohne ISO: Dauer-Text, ids s1.. nach Position
  const legacy = { shifts: [{ duration: "3 Stunden" }, { duration: "5h" }, {}] };
  assert.deepEqual(sb.jobShifts(legacy).map((s) => [s.id, s.hours]), [["s1", 3], ["s2", 5], ["s3", 8]]);
  // keine shifts: eine synthetische Schicht mit Job-Fenster bzw. 8 h
  assert.deepEqual(sb.jobShifts({ shifts: [] }).map((s) => [s.id, s.hours]), [["s1", 8]]);
  assert.equal(sb.jobShifts({ startTime: new Date(2030, 0, 1, 9), endTime: new Date(2030, 0, 1, 12) })[0].hours, 3);
});

test("bookedShifts: leer/fehlend = alle, sonst Auswahl; unbekannte ids → alle (kein Verstecken)", () => {
  assert.equal(sb.bookedShifts(job(), []).length, 2);
  assert.equal(sb.bookedShifts(job(), undefined).length, 2);
  assert.deepEqual(sb.bookedShifts(job(), ["b"]).map((s) => s.id), ["b"]);
  assert.equal(sb.bookedShifts(job(), ["zzz"]).length, 2);
});

test("bookedSpan / bookedIntervals / describeBooked", () => {
  const span = sb.bookedSpan(job(), ["b"]);
  assert.equal(span.start.toISOString(), at(13, 9, 2).startTimeISO);
  assert.equal(span.end.toISOString(), at(13, 9, 2).endTimeISO);
  assert.equal(sb.bookedSpan(job(), []).end.toISOString(), at(13, 9, 2).endTimeISO);
  assert.equal(sb.bookedIntervals(job(), ["a"]).length, 1);
  assert.deepEqual(sb.describeBooked(job(), ["a"]).map((s) => s.date), ["Mon 12"]);
  // ohne Schichtzeiten → Job-Fenster
  const w = { shifts: [], startTime: new Date(2030, 0, 1, 9), endTime: new Date(2030, 0, 1, 12) };
  assert.equal(sb.bookedIntervals(w, []).length, 1);
  assert.deepEqual(sb.bookedIntervals({ shifts: [] }, []), []);
  assert.equal(sb.withBookedTimes(job(), ["b"]).startTime.toISOString(), at(13, 9, 2).startTimeISO);
});

test("parseShiftSelection: Default alle, Validierung, begonnene Schichten", () => {
  assert.deepEqual(sb.parseShiftSelection(job(), undefined, NOW), { ok: true, shiftIds: ["a", "b"] });
  assert.deepEqual(sb.parseShiftSelection(job(), ["b"], NOW), { ok: true, shiftIds: ["b"] });
  for (const bad of [[], "a", ["a", "a"], ["nope"], [1], [""]]) {
    const r = sb.parseShiftSelection(job(), bad, NOW);
    assert.equal(r.ok, false, JSON.stringify(bad));
    assert.equal(r.status, 400);
    assert.equal(r.error, "INVALID_SHIFTS");
  }
  // Schicht a (12.1. 09:00) hat begonnen
  const later = new Date(Date.UTC(2030, 0, 12, 10));
  const explicit = sb.parseShiftSelection(job(), ["a"], later);
  assert.deepEqual([explicit.ok, explicit.status, explicit.error], [false, 409, "SHIFT_UNAVAILABLE"]);
  assert.equal(sb.parseShiftSelection(job(), ["a", "b"], later).ok, false);
  assert.deepEqual(sb.parseShiftSelection(job(), undefined, later), { ok: true, shiftIds: ["b"] }); // "alle" ueberspringt begonnene
  const none = sb.parseShiftSelection(job(), undefined, new Date(Date.UTC(2030, 0, 20)));
  assert.equal(none.error, "SHIFT_UNAVAILABLE");
});

test("Kapazitaet pro Schicht: voll bei angenommenen >= openSpots", () => {
  const j = job({ openSpots: 1 });
  const accepted = [{ id: "x1", shiftIds: ["a"] }];
  assert.deepEqual(sb.fullShiftIds(j, ["a", "b"], accepted), ["a"]);
  assert.deepEqual(sb.fullShiftIds(j, ["b"], accepted), []);
  assert.deepEqual(sb.fullShiftIds(j, ["a"], accepted, "x1"), []); // sich selbst nicht mitzaehlen
  // Altbestand (leer) deckt alle Schichten ab
  assert.deepEqual(sb.fullShiftIds(j, ["a", "b"], [{ id: "old", shiftIds: [] }]), ["a", "b"]);
  assert.equal(sb.maxCoverage(job({ openSpots: 3 }), ["a", "b"], [{ shiftIds: ["a"] }, { shiftIds: ["a", "b"] }]), 2);
  assert.equal(sb.maxCoverage(j, ["a"], []), 0);
  // openSpots 0: alles voll
  assert.deepEqual(sb.fullShiftIds(job({ openSpots: 0 }), ["a"], []), ["a"]);
});

test("nextBookedStart: fruehester gebuchter Start ab from", () => {
  const from = new Date(Date.UTC(2030, 0, 12, 12));
  assert.equal(sb.nextBookedStart(job(), [], from).toISOString(), at(13, 9, 2).startTimeISO);
  assert.equal(sb.nextBookedStart(job(), ["a"], from), null);
  assert.equal(sb.nextBookedStart(job(), ["a"], NOW).toISOString(), at(12, 9, 4).startTimeISO);
});

test("assignShiftIds: behaelt vorhandene ids, ersetzt Duplikate, fuellt Luecken", () => {
  const r = sb.assignShiftIds([{ id: "keep-1" }, { id: "keep-2" }, { id: "keep-1" }, {}]);
  assert.equal(r[0].id, "keep-1");
  assert.equal(r[1].id, "keep-2");
  assert.notEqual(r[2].id, "keep-1");
  assert.ok(r[3].id);
  assert.equal(new Set(r.map((s) => s.id)).size, 4);
});

test("shiftsSpan / bookedEnd: frueheste Start, spaetestes Ende ueber alle Schichten", () => {
  const span = sb.shiftsSpan([{ id: "x", ...at(13, 9, 2) }, { id: "y", ...at(12, 9, 4) }, { id: "z" }]);
  assert.equal(span.start.toISOString(), at(12, 9, 4).startTimeISO);
  assert.equal(span.end.toISOString(), at(13, 9, 2).endTimeISO);
  assert.equal(sb.shiftsSpan([]), null);
  assert.equal(sb.shiftsSpan([{ duration: "3h" }]), null);
  assert.equal(sb.bookedEnd(job(), ["a"]).toISOString(), at(12, 9, 4).endTimeISO);
  assert.equal(sb.bookedEnd({ shifts: [] }, []), null);
});
