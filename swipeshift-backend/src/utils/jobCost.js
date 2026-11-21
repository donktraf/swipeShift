// src/utils/jobCost.js
// Einheitliche Kostenrechnung fuer Employer-Finanzen, Dashboard und Job-Payment-Screen.
// payAmount ist der STUNDENLOHN (PostJobView: "Hourly Rate ($)", payText "$X / hr").
//
//   Lohn pro Worker   = payAmount × Schichtstunden
//   Abgeschlossen     = Lohn pro Worker × angenommene Worker   (tatsaechlich geschuldet)
//   Kommend (geplant) = Lohn pro Worker × max(openSpots, angenommene Worker)
//   Paid Out          = Lohn pro Worker × als bezahlt markierte Worker
//
// Plattform-Gebuehr (utils/fees.js): Servicegebuehr OBENDRAUF auf den Employer, Worker bekommt den
// vollen Lohn. jobCosts liefert je Kennzahl Lohn (completed/planned/paidOut — unveraenderte Namen),
// Gebuehr (…Fee) und Gesamt inkl. Gebuehr (…Total). "Total Spending" im Employer-UI = …Total.

const { billable, onHold } = require("./reliability");
const { roundMoney, feeFor, feePercentForJob } = require("./fees");

const DEFAULT_SHIFT_HOURS = 8; // Fallback ohne Start/Ende — wie bisher im Payment-Screen

const round1 = (h) => Math.round(h * 10) / 10;

// Stunden je Schicht (auf 0,1 h gerundet, identisch zur Anzeige im Payment-Screen).
// Quelle: ALLE gueltigen Schichten in job.shifts (startTimeISO/endTimeISO); ohne diese die Spalten
// startTime/endTime (eine Schicht); ohne beides ein Fallback von 8 h.
// Aufrufer muessen shifts, startTime und endTime selektieren.
function shiftHoursList(job) {
  const out = [];
  if (Array.isArray(job?.shifts)) {
    for (const sh of job.shifts) {
      if (!sh?.startTimeISO || !sh?.endTimeISO) continue;
      const h = (new Date(sh.endTimeISO) - new Date(sh.startTimeISO)) / 3_600_000;
      if (h > 0) out.push(round1(h));
    }
  }
  if (out.length) return out;
  if (job?.startTime && job?.endTime) {
    const h = (new Date(job.endTime) - new Date(job.startTime)) / 3_600_000;
    if (h > 0) return [round1(h)];
  }
  return [DEFAULT_SHIFT_HOURS];
}

// Gesamtstunden ueber alle Schichten (pro Worker)
function shiftHours(job) {
  return round1(shiftHoursList(job).reduce((s, h) => s + h, 0));
}

// Lohn je Worker ueber alle Schichten (je Schicht auf Cent gerundet, wie PostJobView).
// TODO: Apply speichert nicht, auf welche Schichten sich ein Worker beworben hat → es werden ALLE Schichten des Jobs angenommen
// (gilt auch fuer den Worker-Verdienst).
function payPerWorker(job) {
  const rate = job?.payAmount ?? 0;
  return roundMoney(shiftHoursList(job).reduce((s, h) => s + roundMoney(rate * h), 0));
}

// Lohn und Gebuehr je Worker, schichtweise gerundet (Gebuehr je Schicht, dann summiert — wie PostJobView)
function perWorkerParts(job, percent) {
  const rate = job?.payAmount ?? 0;
  let wage = 0, fee = 0;
  for (const h of shiftHoursList(job)) {
    const w = roundMoney(rate * h);
    wage += w;
    fee  += feeFor(w, percent);
  }
  return { wage: roundMoney(wage), fee: roundMoney(fee) };
}

// applies: Liste angenommener Bewerbungen des Jobs ({ isPaid, attendance?, ... }).
// No-Shows werden nicht berechnet (utils/reliability.js → billable); ein No-Show unter Einspruch ist "On hold"
// (…onHold…, noch nicht berechnet) bis zur Entscheidung.
// job.platformFeePercent = Snapshot beim Veroeffentlichen (null → aktueller Default).
function jobCosts(job, allApplies = []) {
  const applies   = billable(allApplies);
  const held      = onHold(allApplies).length;
  const percent   = feePercentForJob(job);
  const { wage: perWorker, fee: perWorkerFee } = perWorkerParts(job, percent);
  const accepted  = applies.length;
  const paid      = applies.filter(a => a.isPaid).length;
  const planned   = Math.max(job?.openSpots ?? 1, accepted);
  const block = (n) => {
    const wages = roundMoney(perWorker * n);
    const fees  = roundMoney(perWorkerFee * n);
    return { wages, fees, total: roundMoney(wages + fees) };
  };
  const c = block(accepted), p = block(planned), o = block(paid), h = block(held);
  return {
    feePercent: percent,
    perWorker,
    perWorkerFee,
    perWorkerTotal: roundMoney(perWorker + perWorkerFee),
    completed: c.wages, completedFee: c.fees, completedTotal: c.total,
    planned:   p.wages, plannedFee:   p.fees, plannedTotal:   p.total,
    paidOut:   o.wages, paidOutFee:   o.fees, paidOutTotal:   o.total,
    onHold:    h.wages, onHoldFee:    h.fees, onHoldTotal:    h.total,
  };
}

module.exports = { DEFAULT_SHIFT_HOURS, shiftHoursList, shiftHours, payPerWorker, jobCosts };
