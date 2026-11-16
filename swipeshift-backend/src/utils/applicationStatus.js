// src/utils/applicationStatus.js
// Anzeige-Status einer Bewerbung aus Worker-Sicht (Job Applications + Kalender).
// Rein und DB-frei → testbar.
//
//   displayStatus:      applied | confirmed | completed | cancelled
//   cancellationKind:   declined | jobCancelled | null
//   cancellationReason: Text fuer die UI (Employer-Grund falls angegeben, sonst Standardtext)
//   paymentStatus:      paid | pending | null (nur bei completed)

const DEFAULT_REASONS = {
  declined:     "Your application was declined.",
  jobCancelled: "The employer cancelled this job.",
};

function deriveApplicationStatus(apply, job, now = new Date()) {
  // Stornierter Job schlaegt alles andere — vorher blieb ein angenommener Worker faelschlich "confirmed"
  if (job?.status === "cancelled") {
    const reason = typeof job.cancellationReason === "string" ? job.cancellationReason.trim() : "";
    return {
      displayStatus:      "cancelled",
      cancellationKind:   "jobCancelled",
      cancellationReason: reason || DEFAULT_REASONS.jobCancelled,
      paymentStatus:      null,
    };
  }
  if (apply.status === "declined") {
    return {
      displayStatus:      "cancelled",
      cancellationKind:   "declined",
      cancellationReason: DEFAULT_REASONS.declined,
      paymentStatus:      null,
    };
  }
  if (apply.status === "accepted") {
    // Abgeschlossen, wenn die Schicht vorbei ist ODER der Employer den Job als completed markiert hat
    const ended = job?.status === "completed" || (job?.endTime && new Date(job.endTime) < now);
    return {
      displayStatus:      ended ? "completed" : "confirmed",
      cancellationKind:   null,
      cancellationReason: null,
      paymentStatus:      ended ? (apply.isPaid ? "paid" : "pending") : null,
    };
  }
  return { displayStatus: "applied", cancellationKind: null, cancellationReason: null, paymentStatus: null };
}

// Employer-Eingabe fuer den Stornierungsgrund normalisieren (optional, max. 300 Zeichen)
const MAX_REASON_LENGTH = 300;
function normalizeCancellationReason(value) {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  if (!trimmed) return null;
  return trimmed.slice(0, MAX_REASON_LENGTH);
}

module.exports = { DEFAULT_REASONS, MAX_REASON_LENGTH, deriveApplicationStatus, normalizeCancellationReason };
