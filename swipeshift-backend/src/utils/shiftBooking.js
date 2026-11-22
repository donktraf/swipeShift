// src/utils/shiftBooking.js
// Welche Schichten eines Jobs hat ein Worker gebucht? Rein und DB-frei → testbar.
//
// Job.shifts ist JSON [{ id, date, timeRange, duration, totalPay, startTimeISO, endTimeISO }].
// Apply.shiftIds = gebuchte Schicht-IDs. LEER = Altbestand/alte Clients → ALLE Schichten des Jobs.
// Kapazitaet: Job.openSpots gilt PRO Schicht; eine Schicht ist voll, wenn angenommene Bewerbungen, die sie abdecken,
// >= openSpots sind.

const DEFAULT_SHIFT_HOURS = 8; // Fallback ohne Start/Ende — wie bisher im Payment-Screen

const round1 = (h) => Math.round(h * 10) / 10;
const toMs = (v) => {
  if (!v) return null;
  const t = new Date(v).getTime();
  return Number.isNaN(t) ? null : t;
};
const isObj = (v) => v && typeof v === "object" && !Array.isArray(v);

// Schicht-ID: gespeicherte id, sonst "s<Position ab 1>" (identisch zum Backfill in der Migration)
function shiftIdOf(sh, index) {
  if (typeof sh?.id === "string" && sh.id) return sh.id;
  if (typeof sh?.id === "number") return String(sh.id);
  return `s${index + 1}`;
}

// Neue Schichten (POST/PUT /jobs): fehlende oder doppelte ids ergaenzen, damit jede Schicht buchbar ist.
function assignShiftIds(shifts) {
  if (!Array.isArray(shifts)) return shifts;
  const used = new Set();
  return shifts.map((sh, i) => {
    if (!isObj(sh)) return sh;
    let id = shiftIdOf(sh, i);
    for (let n = i + 1; used.has(id); n += 1) id = `s${n}x`; // Duplikat → eindeutige Ersatz-id
    used.add(id);
    return { ...sh, id };
  });
}

// "3 Stunden", "5h", "2,5 h" → Zahl; sonst null
function parseDurationHours(text) {
  const m = typeof text === "string" ? text.match(/(\d+(?:[.,]\d+)?)/) : null;
  const h = m ? Number(m[1].replace(",", ".")) : NaN;
  return h > 0 ? round1(h) : null;
}

/**
 * Alle buchbaren Schichten eines Jobs: [{ id, index, startMs, endMs, hours, date, timeRange }].
 * Quelle: Eintraege mit gueltigem startTimeISO/endTimeISO; ohne solche (Altdaten) alle Eintraege mit Dauer-Text bzw.
 * Fallback (eine Schicht = startTime/endTime des Jobs, sonst 8 h). Ohne shifts-JSON: eine synthetische Schicht "s1".
 * Aufrufer muessen shifts, startTime und endTime selektieren.
 */
function jobShifts(job) {
  const entries = Array.isArray(job?.shifts) ? job.shifts.map((sh, i) => ({ sh, i })).filter(({ sh }) => isObj(sh)) : [];
  const timed = [];
  for (const { sh, i } of entries) {
    const s = toMs(sh.startTimeISO), e = toMs(sh.endTimeISO);
    if (s === null || e === null || e <= s) continue;
    timed.push({ id: shiftIdOf(sh, i), index: i, startMs: s, endMs: e, hours: round1((e - s) / 3_600_000), date: sh.date ?? null, timeRange: sh.timeRange ?? null });
  }
  if (timed.length) return timed;

  const js = toMs(job?.startTime), je = toMs(job?.endTime);
  const jobWindow = js !== null && je !== null && je > js;
  const jobHours = jobWindow ? round1((je - js) / 3_600_000) : null;
  if (!entries.length) {
    return [{ id: "s1", index: 0, startMs: js, endMs: jobWindow ? je : null, hours: jobHours ?? DEFAULT_SHIFT_HOURS, date: null, timeRange: null }];
  }
  const single = entries.length === 1;
  return entries.map(({ sh, i }) => ({
    id: shiftIdOf(sh, i), index: i,
    startMs: single ? js : null, endMs: single && jobWindow ? je : null,
    hours: parseDurationHours(sh.duration) ?? (single ? jobHours : null) ?? DEFAULT_SHIFT_HOURS,
    date: sh.date ?? null, timeRange: sh.timeRange ?? null,
  }));
}

// Gebuchte Schichten; shiftIds leer/fehlend (oder keine ID passt mehr) → alle
function bookedShifts(job, shiftIds) {
  const all = jobShifts(job);
  if (!Array.isArray(shiftIds) || !shiftIds.length) return all;
  const picked = all.filter((s) => shiftIds.includes(s.id));
  return picked.length ? picked : all;
}

// Zeitraum der gebuchten Schichten (frueheste Start, spaeteste Ende); ohne Zeiten → startTime/endTime des Jobs
function bookedSpan(job, shiftIds) {
  const timed = bookedShifts(job, shiftIds).filter((s) => s.startMs !== null && s.endMs !== null);
  if (!timed.length) return { start: job?.startTime ?? null, end: job?.endTime ?? null };
  return {
    start: new Date(Math.min(...timed.map((s) => s.startMs))),
    end: new Date(Math.max(...timed.map((s) => s.endMs))),
  };
}

// Gesamt-Zeitraum aller gueltigen Schichten einer shifts-Liste (fuer Job.startTime/endTime): { start, end } | null
function shiftsSpan(shifts) {
  const timed = jobShifts({ shifts }).filter((s) => s.startMs !== null && s.endMs !== null);
  if (!timed.length) return null;
  return { start: new Date(Math.min(...timed.map((s) => s.startMs))), end: new Date(Math.max(...timed.map((s) => s.endMs))) };
}

// Ende der gebuchten Schichten (Date | null); Basis fuer Anwesenheit, Zahlungs-/Erinnerungsfenster, Zuverlaessigkeit
function bookedEnd(job, shiftIds) {
  const end = bookedSpan(job, shiftIds).end;
  return end ? new Date(end) : null;
}

// Job mit startTime/endTime der gebuchten Schichten (fuer Status-/Storno-Logik aus Worker-Sicht)
function withBookedTimes(job, shiftIds) {
  if (!job) return job;
  const { start, end } = bookedSpan(job, shiftIds);
  return { ...job, startTime: start, endTime: end };
}

// Zeitintervalle der gebuchten Schichten fuer den Konflikt-Check; ohne Zeiten das Job-Fenster
function bookedIntervals(job, shiftIds) {
  const timed = bookedShifts(job, shiftIds).filter((s) => s.startMs !== null && s.endMs !== null);
  if (timed.length) return timed.map((s) => ({ startMs: s.startMs, endMs: s.endMs }));
  const js = toMs(job?.startTime), je = toMs(job?.endTime);
  return js !== null && je !== null ? [{ startMs: js, endMs: je }] : [];
}

// Fuer die Clients: gebuchte Schichten (nur Anzeigefelder)
function describeBooked(job, shiftIds) {
  return bookedShifts(job, shiftIds).map((s) => ({
    id: s.id, date: s.date, timeRange: s.timeRange,
    startTime: s.startMs !== null ? new Date(s.startMs).toISOString() : null,
    endTime:   s.endMs   !== null ? new Date(s.endMs).toISOString()   : null,
  }));
}

/**
 * Auswahl aus dem Apply-Body pruefen. rawIds undefined/null = alle (Single-Shift/alte Clients).
 * → { ok: true, shiftIds } | { ok: false, status, error, message }
 * Bereits begonnene Schichten sind nicht buchbar: explizit gewaehlt → 409 SHIFT_UNAVAILABLE; bei "alle" werden sie
 * uebersprungen (SHIFT_UNAVAILABLE erst, wenn nichts mehr uebrig ist).
 */
function parseShiftSelection(job, rawIds, now = new Date()) {
  const all = jobShifts(job);
  const bad = (message) => ({ ok: false, status: 400, error: "INVALID_SHIFTS", message });
  let candidates = all;
  const explicit = rawIds !== undefined && rawIds !== null;
  if (explicit) {
    if (!Array.isArray(rawIds) || !rawIds.length) return bad("shiftIds must be a non-empty list.");
    if (!rawIds.every((id) => typeof id === "string" && id)) return bad("shiftIds must be strings.");
    if (new Set(rawIds).size !== rawIds.length) return bad("shiftIds must be unique.");
    const known = new Map(all.map((s) => [s.id, s]));
    if (!rawIds.every((id) => known.has(id))) return bad("Unknown shift for this job.");
    candidates = rawIds.map((id) => known.get(id));
  }
  const nowMs = new Date(now).getTime();
  const bookable = candidates.filter((s) => s.startMs === null || s.startMs > nowMs);
  if (!bookable.length || (explicit && bookable.length !== candidates.length)) {
    return { ok: false, status: 409, error: "SHIFT_UNAVAILABLE", message: "This shift has already started." };
  }
  return { ok: true, shiftIds: bookable.map((s) => s.id) };
}

// Anzahl angenommener Bewerbungen je Schicht-ID (acceptedApplies: { shiftIds } der angenommenen Bewerbungen des Jobs)
function shiftCoverage(job, acceptedApplies) {
  const counts = new Map(jobShifts(job).map((s) => [s.id, 0]));
  for (const a of Array.isArray(acceptedApplies) ? acceptedApplies : []) {
    for (const s of bookedShifts(job, a?.shiftIds)) counts.set(s.id, (counts.get(s.id) ?? 0) + 1);
  }
  return counts;
}

const capacityOf = (job) => job?.openSpots ?? 1;

// Welche der angefragten Schichten sind voll? (excludeApplyId: die Bewerbung selbst nicht mitzaehlen)
function fullShiftIds(job, shiftIds, acceptedApplies, excludeApplyId = null) {
  const others = (Array.isArray(acceptedApplies) ? acceptedApplies : []).filter((a) => !excludeApplyId || a.id !== excludeApplyId);
  const counts = shiftCoverage(job, others);
  return shiftIds.filter((id) => (counts.get(id) ?? 0) >= capacityOf(job));
}

// Hoechste Belegung ueber die angefragten Schichten (Instant Match: nur wenn ALLE Platz haben ⇔ max < openSpots)
function maxCoverage(job, shiftIds, acceptedApplies) {
  const counts = shiftCoverage(job, acceptedApplies);
  return Math.max(0, ...shiftIds.map((id) => counts.get(id) ?? 0));
}

// Fruehester Start einer gebuchten Schicht ab `from` (Schicht-Erinnerung); null wenn keine
function nextBookedStart(job, shiftIds, from) {
  const fromMs = new Date(from).getTime();
  const starts = bookedShifts(job, shiftIds).map((s) => s.startMs).filter((t) => t !== null && t >= fromMs);
  return starts.length ? new Date(Math.min(...starts)) : null;
}

module.exports = {
  DEFAULT_SHIFT_HOURS, round1, shiftIdOf, assignShiftIds, parseDurationHours,
  jobShifts, bookedShifts, bookedSpan, bookedEnd, shiftsSpan, withBookedTimes, bookedIntervals, describeBooked,
  parseShiftSelection, shiftCoverage, fullShiftIds, maxCoverage, nextBookedStart,
};
