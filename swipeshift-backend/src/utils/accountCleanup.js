// src/utils/accountCleanup.js — Konto-Loeschung: Job-Storno-Auswahl (rein)

const OPEN_JOB_STATUSES = ["draft", "published", "inProgress"];
const ACCOUNT_CLOSED_REASON = "The employer closed their account.";
const ACCOUNT_CLOSED_CHAT_NOTE = "The employer closed their account. This job was cancelled.";

// Jobs, die beim Loeschen des Arbeitgebers storniert werden (offen = draft/published/inProgress)
function jobsToCancel(jobs) {
  return jobs.filter((j) => OPEN_JOB_STATUSES.includes(j.status)).map((j) => j.id);
}

module.exports = { OPEN_JOB_STATUSES, ACCOUNT_CLOSED_REASON, ACCOUNT_CLOSED_CHAT_NOTE, jobsToCancel };
