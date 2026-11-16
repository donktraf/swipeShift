// src/utils/period.js
// Gemeinsame Zeitraum-Logik fuer Finanz-Uebersichten (Worker + Employer).
// Rein und DB-frei → testbar. Zeiten in Server-Lokalzeit (wie der restliche Code).
//
// Query-Parameter:
//   period = thisMonth | last3Months | thisYear | allTime | custom   (Default: thisMonth)
//   from, to = YYYY-MM-DD (nur bei period=custom, beide inklusive)

const PERIODS = ["thisMonth", "last3Months", "thisYear", "allTime", "custom"];
const MAX_CUSTOM_DAYS = 366 * 5; // Schutz gegen absurde Bereiche

const DAY_MS = 24 * 3600 * 1000;

function startOfDay(d) { const x = new Date(d); x.setHours(0, 0, 0, 0); return x; }
function endOfDay(d)   { const x = new Date(d); x.setHours(23, 59, 59, 999); return x; }

function parseDay(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) return null;
  const [y, m, d] = value.split("-").map(Number);
  const date = new Date(y, m - 1, d);
  // Ungueltige Tage wie 2026-02-30 rollen sonst still in den Folgemonat
  if (date.getFullYear() !== y || date.getMonth() !== m - 1 || date.getDate() !== d) return null;
  return date;
}

// Liefert { period, since, until } oder { error }.
// since/until = Filtergrenzen fuer job.startTime (null = offen). Feste Zeitraeume enden am
// Ende des laufenden Monats/Jahres — sonst wuerden z.B. Schichten im naechsten Jahr unter
// "This Month" mitgezaehlt, im Diagramm aber fehlen.
// chartStart/chartEnd = Achse fuer das Diagramm (bei allTime spaeter aus den Daten ergaenzt).
function resolvePeriod(query = {}, now = new Date()) {
  const period = query.period ?? "thisMonth";
  if (!PERIODS.includes(period)) return { error: `Unknown period: ${period}` };

  const y = now.getFullYear(), m = now.getMonth();
  switch (period) {
    case "thisMonth":
      return { period, since: new Date(y, m, 1), until: endOfDay(new Date(y, m + 1, 0)),
               chartStart: new Date(y, m, 1), chartEnd: endOfDay(new Date(y, m + 1, 0)) };
    case "last3Months":
      return { period, since: new Date(y, m - 3, 1), until: endOfDay(new Date(y, m + 1, 0)),
               chartStart: new Date(y, m - 3, 1), chartEnd: endOfDay(new Date(y, m + 1, 0)) };
    case "thisYear":
      return { period, since: new Date(y, 0, 1), until: endOfDay(new Date(y, 11, 31)),
               chartStart: new Date(y, 0, 1), chartEnd: endOfDay(new Date(y, 11, 31)) };
    case "allTime":
      return { period, since: null, until: null, chartStart: null, chartEnd: null };
    case "custom": {
      const from = parseDay(query.from), to = parseDay(query.to);
      if (!from || !to) return { error: "Custom period needs from and to as YYYY-MM-DD" };
      if (from > to) return { error: "from must be on or before to" };
      if ((to - from) / DAY_MS > MAX_CUSTOM_DAYS) return { error: "Custom period is too long" };
      return { period, since: startOfDay(from), until: endOfDay(to),
               chartStart: startOfDay(from), chartEnd: endOfDay(to) };
    }
  }
}

function isInPeriod(date, { since, until }) {
  if (!date) return since === null && until === null; // ohne Datum nur bei "All Time"
  const t = new Date(date);
  if (since && t < since) return false;
  if (until && t > until) return false;
  return true;
}

// Prisma-where-Fragment fuer ein DateTime-Feld
function prismaRange({ since, until }) {
  if (!since && !until) return undefined;
  return { ...(since ? { gte: since } : {}), ...(until ? { lte: until } : {}) };
}

// Teilt [start, end] in Diagramm-Buckets: Tage (≤ 31 Tage), Wochen (≤ 16 Wochen), sonst Monate.
function buildBuckets(start, end) {
  if (!start || !end || start > end) return [];
  const spanDays = Math.round((startOfDay(end) - startOfDay(start)) / DAY_MS) + 1;
  const buckets = [];

  if (spanDays <= 31) {
    for (let d = startOfDay(start); d <= end; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
      buckets.push({ start: d, end: endOfDay(d), label: String(d.getDate()), unit: "day" });
    }
  } else if (spanDays <= 16 * 7) {
    for (let d = startOfDay(start); d <= end; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 7)) {
      const last = endOfDay(new Date(d.getFullYear(), d.getMonth(), d.getDate() + 6));
      buckets.push({ start: d, end: last < end ? last : end,
                     label: d.toLocaleDateString("en-US", { month: "short", day: "numeric" }), unit: "week" });
    }
  } else {
    for (let d = new Date(start.getFullYear(), start.getMonth(), 1); d <= end;
         d = new Date(d.getFullYear(), d.getMonth() + 1, 1)) {
      const sameYear = start.getFullYear() === end.getFullYear();
      buckets.push({
        start: d < start ? startOfDay(start) : d,
        end: endOfDay(new Date(d.getFullYear(), d.getMonth() + 1, 0)),
        label: d.toLocaleDateString("en-US", sameYear ? { month: "short" } : { month: "short", year: "2-digit" }),
        unit: "month",
      });
    }
    const lastBucket = buckets[buckets.length - 1];
    if (lastBucket && lastBucket.end > end) lastBucket.end = end;
  }
  return buckets;
}

module.exports = { PERIODS, resolvePeriod, isInPeriod, prismaRange, buildBuckets, parseDay };
