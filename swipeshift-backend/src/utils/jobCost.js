// src/utils/jobCost.js
// Einheitliche Kostenrechnung fuer Employer-Finanzen, Dashboard und Job-Payment-Screen.
// payAmount ist der STUNDENLOHN (PostJobView: "Hourly Rate ($)", payText "$X / hr").
//
//   Lohn pro Worker   = payAmount × Stunden seiner GEBUCHTEN Schichten (Apply.shiftIds, leer = alle)
//   Abgeschlossen     = Summe ueber die angenommenen Worker   (tatsaechlich geschuldet)
//   Kommend (geplant) = je Schicht Lohn × max(openSpots, angenommene Worker, die die Schicht abdecken)
//   Paid Out          = Summe ueber als bezahlt markierte Worker
//
// Plattform-Gebuehr (utils/fees.js): Servicegebuehr OBENDRAUF auf den Employer, Worker bekommt den
// vollen Lohn. jobCosts liefert je Kennzahl Lohn (completed/planned/paidOut — unveraenderte Namen),
// Gebuehr (…Fee) und Gesamt inkl. Gebuehr (…Total). "Total Spending" im Employer-UI = …Total.

const { billable, onHold } = require("./reliability");
const { roundMoney, feeFor, feePercentForJob } = require("./fees");
const { DEFAULT_SHIFT_HOURS, jobShifts, bookedShifts, shiftCoverage } = require("./shiftBooking");

// Stunden je Schicht (auf 0,1 h gerundet, identisch zur Anzeige im Payment-Screen).
// shiftIds = gebuchte Schichten des Workers (Apply.shiftIds); leer/fehlend = ALLE Schichten des Jobs.
// Quelle der Schichten: utils/shiftBooking.js (job.shifts mit startTimeISO/endTimeISO; sonst startTime/endTime; sonst 8 h).
// Aufrufer muessen shifts, startTime und endTime selektieren.
function shiftHoursList(job, shiftIds) {
  return bookedShifts(job, shiftIds).map((s) => s.hours);
}

const round1 = (h) => Math.round(h * 10) / 10;

// Gesamtstunden ueber die gebuchten Schichten (pro Worker)
function shiftHours(job, shiftIds) {
  return round1(shiftHoursList(job, shiftIds).reduce((s, h) => s + h, 0));
}

// Lohn je Worker ueber seine gebuchten Schichten (je Schicht auf Cent gerundet, wie PostJobView).
// Ohne shiftIds: alle Schichten des Jobs.
function payPerWorker(job, shiftIds) {
  const rate = job?.payAmount ?? 0;
  return roundMoney(shiftHoursList(job, shiftIds).reduce((s, h) => s + roundMoney(rate * h), 0));
}

// Lohn und Gebuehr je Worker, schichtweise gerundet (Gebuehr je Schicht, dann summiert — wie PostJobView)
function perWorkerParts(job, percent, shiftIds) {
  const rate = job?.payAmount ?? 0;
  let wage = 0, fee = 0;
  for (const h of shiftHoursList(job, shiftIds)) {
    const w = roundMoney(rate * h);
    wage += w;
    fee  += feeFor(w, percent);
  }
  return { wage: roundMoney(wage), fee: roundMoney(fee) };
}

// applies: Liste angenommener Bewerbungen des Jobs ({ isPaid, shiftIds?, attendance?, ... }).
//   Abgeschlossen = Summe der gebuchten Schichten der (abrechenbaren) Worker
//   Paid Out      = dito fuer bezahlte Worker
//   Kommend       = je Schicht Lohn × max(openSpots, angenommene Worker, die diese Schicht abdecken)
// No-Shows werden nicht berechnet (utils/reliability.js → billable); ein No-Show unter Einspruch ist "On hold"
// (…onHold…, noch nicht berechnet) bis zur Entscheidung.
// job.platformFeePercent = Snapshot beim Veroeffentlichen (null → aktueller Default).
// perWorker/perWorkerFee/perWorkerTotal = ALLE Schichten des Jobs (Richtwert je Worker, unabhaengig von der Buchung).
function jobCosts(job, allApplies = []) {
  const applies   = billable(allApplies);
  const heldList  = onHold(allApplies);
  const percent   = feePercentForJob(job);
  const { wage: perWorker, fee: perWorkerFee } = perWorkerParts(job, percent);

  const sumOver = (list) => {
    let w = 0, f = 0;
    for (const a of list) {
      const p = perWorkerParts(job, percent, a.shiftIds);
      w += p.wage; f += p.fee;
    }
    const wages = roundMoney(w), fees = roundMoney(f);
    return { wages, fees, total: roundMoney(wages + fees) };
  };

  // Geplant: pro Schicht max(Plaetze, tatsaechlich abdeckende Worker)
  const coverage = shiftCoverage(job, applies);
  const spots    = job?.openSpots ?? 1;
  const rate     = job?.payAmount ?? 0;
  let pw = 0, pf = 0;
  for (const s of jobShifts(job)) {
    const w = roundMoney(rate * s.hours);
    const n = Math.max(spots, coverage.get(s.id) ?? 0);
    pw += w * n;
    pf += feeFor(w, percent) * n;
  }
  const plannedWages = roundMoney(pw), plannedFees = roundMoney(pf);

  const c = sumOver(applies), o = sumOver(applies.filter((a) => a.isPaid)), h = sumOver(heldList);
  return {
    feePercent: percent,
    perWorker,
    perWorkerFee,
    perWorkerTotal: roundMoney(perWorker + perWorkerFee),
    completed: c.wages, completedFee: c.fees, completedTotal: c.total,
    planned:   plannedWages, plannedFee: plannedFees, plannedTotal: roundMoney(plannedWages + plannedFees),
    paidOut:   o.wages, paidOutFee:   o.fees, paidOutTotal:   o.total,
    onHold:    h.wages, onHoldFee:    h.fees, onHoldTotal:    h.total,
  };
}

module.exports = { DEFAULT_SHIFT_HOURS, shiftHoursList, shiftHours, payPerWorker, jobCosts };
