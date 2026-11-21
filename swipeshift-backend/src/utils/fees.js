// src/utils/fees.js
// Plattform-Gebuehr (Servicegebuehr obendrauf auf den Arbeitgeber). Worker bekommt immer den vollen
// ausgeschriebenen Stundenlohn — es wird NIE etwas vom Worker-Lohn abgezogen.
//
//   Lohn (Worker erhaelt) = payAmount × Stunden
//   Gebuehr (Employer)    = Lohn × platformFeePercent / 100   (auf ganze Cent gerundet)
//   Employer zahlt        = Lohn + Gebuehr
//
// Rundung: Cent-genau wie formatAmount (utils/jobData.js, Math.round(x * 100)). Gebuehr wird je
// Worker-Schicht gerundet und dann multipliziert, damit Summen (Job, Liste, Dashboard) immer zur
// Einzelanzeige passen.
//
// Konfiguration nur hier gelesen (.env): PLATFORM_FEE_PERCENT (Default 15),
// INSTANT_PAYOUT_FEE_PERCENT (Default 1.5, Worker-Sofortauszahlung, noch ohne Auszahlungsanbieter).
// Jobs ohne Snapshot (Job.platformFeePercent = null: Entwuerfe und Altjobs vor Einfuehrung) nutzen
// den AKTUELLEN Default; beim Veroeffentlichen wird der Satz pro Job eingefroren.

const DEFAULT_PLATFORM_FEE_PERCENT = 15;
const DEFAULT_INSTANT_PAYOUT_FEE_PERCENT = 1.5;

// Ungueltige/negative/>100-Werte → Default (kein Absturz wegen Tippfehler in .env)
function parsePercent(raw, fallback) {
  if (raw == null || String(raw).trim() === "") return fallback;
  const n = Number(String(raw).trim().replace(",", "."));
  if (!Number.isFinite(n) || n < 0 || n > 100) return fallback;
  return Math.round(n * 100) / 100;
}

function platformFeePercent(env = process.env) {
  return parsePercent(env.PLATFORM_FEE_PERCENT, DEFAULT_PLATFORM_FEE_PERCENT);
}
function instantPayoutFeePercent(env = process.env) {
  return parsePercent(env.INSTANT_PAYOUT_FEE_PERCENT, DEFAULT_INSTANT_PAYOUT_FEE_PERCENT);
}

// Auf ganze Cent runden (wie formatAmount)
function roundMoney(amount) {
  return Math.round((Number(amount) || 0) * 100) / 100;
}

// Satz eines Jobs: Snapshot, sonst aktueller Default
function feePercentForJob(job, env = process.env) {
  // undefined (≠ null) = Feld wurde nicht gelesen (select vergessen; global per omit ausgeblendet) → laut warnen
  if (job && job.platformFeePercent === undefined) {
    console.warn("feePercentForJob: job.platformFeePercent was not loaded (missing select?) — falling back to the current default rate");
  }
  const snap = job?.platformFeePercent;
  return typeof snap === "number" && Number.isFinite(snap) && snap >= 0 ? snap : platformFeePercent(env);
}

function feeFor(amount, percent = platformFeePercent()) {
  return Math.round((Number(amount) || 0) * 100 * percent / 100) / 100;
}

function employerTotal(amount, percent = platformFeePercent()) {
  return roundMoney(roundMoney(amount) + feeFor(roundMoney(amount), percent));
}

// Oeffentliche Werte fuer die App (GET /config) — keine Secrets
function publicFeeConfig(env = process.env) {
  return {
    platformFeePercent: platformFeePercent(env),
    instantPayoutFeePercent: instantPayoutFeePercent(env),
  };
}

module.exports = {
  DEFAULT_PLATFORM_FEE_PERCENT, DEFAULT_INSTANT_PAYOUT_FEE_PERCENT,
  parsePercent, platformFeePercent, instantPayoutFeePercent, roundMoney, feePercentForJob,
  feeFor, employerTotal, publicFeeConfig,
};
