// src/utils/jobCost.js
// Einheitliche Kostenrechnung fuer Employer-Finanzen, Dashboard und Job-Payment-Screen.
// payAmount ist der STUNDENLOHN (PostJobView: "Hourly Rate ($)", payText "$X / hr").
//
//   Lohn pro Worker   = payAmount × Schichtstunden
//   Abgeschlossen     = Lohn pro Worker × angenommene Worker   (tatsaechlich geschuldet)
//   Kommend (geplant) = Lohn pro Worker × max(openSpots, angenommene Worker)
//   Paid Out          = Lohn pro Worker × als bezahlt markierte Worker

const DEFAULT_SHIFT_HOURS = 8; // Fallback ohne Start/Ende — wie bisher im Payment-Screen

// Schichtdauer in Stunden, auf 0,1 h gerundet (identisch zur Anzeige im Payment-Screen)
function shiftHours(job) {
  if (!job?.startTime || !job?.endTime) return DEFAULT_SHIFT_HOURS;
  const hours = (new Date(job.endTime) - new Date(job.startTime)) / 3_600_000;
  if (!(hours > 0)) return DEFAULT_SHIFT_HOURS;
  return Math.round(hours * 10) / 10;
}

function payPerWorker(job) {
  return (job?.payAmount ?? 0) * shiftHours(job);
}

// applies: Liste angenommener Bewerbungen des Jobs ({ isPaid })
function jobCosts(job, applies = []) {
  const perWorker = payPerWorker(job);
  const accepted  = applies.length;
  const paid      = applies.filter(a => a.isPaid).length;
  const planned   = Math.max(job?.openSpots ?? 1, accepted);
  return {
    perWorker,
    completed: perWorker * accepted,
    planned:   perWorker * planned,
    paidOut:   perWorker * paid,
  };
}

module.exports = { DEFAULT_SHIFT_HOURS, shiftHours, payPerWorker, jobCosts };
