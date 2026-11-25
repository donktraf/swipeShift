// Zeitstempel-Auswahl fuer dynamische Benachrichtigungen: der Zeitpunkt des EREIGNISSES zaehlt
// (nicht createdAt der Bewerbung), sonst waere eine spaetere Annahme/Zahlung "schon gelesen".

const valid = (d) => (d && !Number.isNaN(new Date(d).getTime()) ? d : null);

const acceptedTimestamp = (apply) => valid(apply?.acceptedAt) ?? apply?.createdAt;
const paidTimestamp = (apply) => valid(apply?.paidAt) ?? apply?.createdAt;
// Review faellig, sobald der Job abgeschlossen ist: spaeterer Wert aus Job-Ende (letzte Schicht) und
// letzter Job-Aenderung (Status -> completed kommt oft erst nach endTime); Fallback createdAt der Bewerbung
function reviewDueTimestamp(apply) {
  const times = [valid(apply?.job?.endTime), valid(apply?.job?.updatedAt)].filter(Boolean).map((d) => new Date(d));
  if (!times.length) return apply?.createdAt;
  return new Date(Math.max(...times.map((d) => d.getTime())));
}

// POST /notifications/seen { upTo }: seenAt = min(upTo, now), nie rueckwaerts. Liefert neuen Wert oder null (= unveraendert).
function nextSeenAt(previous, upTo, now = new Date()) {
  const nowMs = new Date(now).getTime();
  const upMs = upTo ? new Date(upTo).getTime() : NaN;
  const candidate = Number.isNaN(upMs) ? nowMs : Math.min(upMs, nowMs);
  const prevMs = previous ? new Date(previous).getTime() : NaN;
  if (!Number.isNaN(prevMs) && candidate <= prevMs) return null;
  return new Date(candidate);
}

module.exports = { acceptedTimestamp, paidTimestamp, reviewDueTimestamp, nextSeenAt };
