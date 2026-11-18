// src/utils/notificationCopy.js
// Reine Texte (Push + E-Mail, Englisch) pro Ereignis. Rueckgabe: { category, push: {title, body, data}, email: {subject, html, text} }.
// Nutzereingaben werden in emailTemplate.renderEmail escaped; Betreffzeilen laufen durch plainLine.

const { renderEmail, plainLine } = require("./emailTemplate");
const { sanitizeTimeZone } = require("./notifyPolicy");
const { MAX_BODY, truncate } = require("./pushPayload");

const OPEN_APP = "Open the SwipeShift app to see the details.";

function make(category, { title, body, data, heading, paragraphs, subject }) {
  const email = renderEmail({ heading: heading ?? title, paragraphs: paragraphs ?? [body, OPEN_APP] });
  return {
    category,
    push: { title, body, data },
    email: { subject: plainLine(subject ?? title, 150), ...email },
  };
}

const job = (t) => plainLine(t || "your job", 80);
const who = (n, fallback) => plainLine(n || fallback, 60);

// "Thu, Nov 19, 9:00 AM" in der Zeitzone des Empfaengers; ohne gueltige Zone in UTC (mit Kennzeichnung)
function formatShiftStart(startTime, timeZone) {
  const d = new Date(startTime);
  if (Number.isNaN(d.getTime())) return "";
  const zone = sanitizeTimeZone(timeZone);
  const text = new Intl.DateTimeFormat("en-US", {
    timeZone: zone || "UTC", weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit",
  }).format(d);
  return zone ? text : `${text} UTC`;
}

// ── Worker: jobActivity ──
function applicationAccepted({ jobTitle, company, jobId, conversationId }) {
  const t = job(jobTitle);
  return make("jobActivity", {
    title: "Application accepted",
    body: `${who(company, "The employer")} accepted your application for "${t}".`,
    data: conversationId ? { type: "chat", conversationId, jobId } : { type: "job", jobId },
    subject: `You're in: ${t}`,
  });
}

function applicationDeclined({ jobTitle, company, jobId }) {
  const t = job(jobTitle);
  return make("jobActivity", {
    title: "Application update",
    body: `${who(company, "The employer")} declined your application for "${t}". There are more jobs waiting for you.`,
    data: { type: "job", jobId },
    subject: `Update on your application: ${t}`,
  });
}

// Der vom Employer frei geschriebene Grund steht NUR im Push (kurz) bzw. in der App — nie in der Mail
// (kein plattformgebrandeter Freitext/Phishing-Links ueber unsere Absenderadresse).
function jobCancelled({ jobTitle, company, reason, jobId }) {
  const t = job(jobTitle);
  const r = plainLine(reason, 300);
  const base = `${who(company, "The employer")} cancelled "${t}".`;
  return make("jobActivity", {
    title: "Job cancelled",
    body: r ? `${base} Reason: ${r}` : base,
    data: { type: "job", jobId },
    subject: `Job cancelled: ${t}`,
    paragraphs: [base, OPEN_APP],
  });
}

// "today at 9:00 AM" / "tomorrow at 9:00 AM" / "Thu, Nov 19, 9:00 AM" (Ortszeit des Empfaengers).
// Ohne gueltige Zeitzone neutral ohne Tageswoerter: "Thu, Nov 19, 2:00 PM UTC".
function describeShiftStart(startTime, timeZone, now = new Date()) {
  const d = new Date(startTime);
  if (Number.isNaN(d.getTime())) return "";
  const zone = sanitizeTimeZone(timeZone);
  if (!zone) return formatShiftStart(d, null);
  const dayKey = (x) => new Intl.DateTimeFormat("en-CA", { timeZone: zone, year: "numeric", month: "2-digit", day: "2-digit" }).format(x);
  const dayNumber = (x) => { const [y, m, dd] = dayKey(x).split("-").map(Number); return Date.UTC(y, m - 1, dd) / 86400000; };
  const diff = dayNumber(d) - dayNumber(new Date(now));
  const time = new Intl.DateTimeFormat("en-US", { timeZone: zone, hour: "numeric", minute: "2-digit" }).format(d);
  if (diff === 0) return `today at ${time}`;
  if (diff === 1) return `tomorrow at ${time}`;
  return formatShiftStart(d, zone);
}

function shiftReminder({ jobTitle, company, startTime, timeZone, jobId, conversationId, now }) {
  const t = job(jobTitle);
  const when = describeShiftStart(startTime, timeZone, now);
  return make("jobActivity", {
    title: "Upcoming shift",
    body: `"${t}" at ${who(company, "the employer")} starts ${when || "soon"}.`,
    data: conversationId ? { type: "chat", conversationId, jobId } : { type: "job", jobId },
    subject: `Reminder: ${t} starts soon`,
  });
}

// ── Employer: jobActivity ──
function newApplication({ workerName, jobTitle, jobId }) {
  const t = job(jobTitle);
  return make("jobActivity", {
    title: "New application",
    body: `${who(workerName, "A worker")} applied for "${t}".`,
    data: { type: "applicants", jobId },
    subject: `New application for ${t}`,
  });
}

function instantMatchBooked({ workerName, jobTitle, jobId }) {
  const t = job(jobTitle);
  return make("jobActivity", {
    title: "Instant Match booked",
    body: `${who(workerName, "A worker")} was booked automatically for "${t}".`,
    data: { type: "applicants", jobId },
    subject: `Instant Match: ${who(workerName, "A worker")} booked for ${t}`,
  });
}

// ── Zuverlaessigkeit ──
// Freundliche Erinnerung nach einem erfassten No-Show (Worker, jobActivity). Nennt die Einspruchsmoeglichkeit.
function noShowRecorded({ jobTitle, company, jobId }) {
  const t = job(jobTitle);
  const c = who(company, "The employer");
  return make("jobActivity", {
    title: "We missed you at your shift",
    body: `${c} marked you as not showing up for "${t}". If that's not right, you can dispute it once in the app.`,
    data: { type: "job", jobId },
    subject: `We missed you at ${t}`,
    paragraphs: [
      `We missed you at "${t}". ${c} recorded that you didn't show up.`,
      "Things come up. Showing up reliably helps you get booked, so we wanted to give you a friendly heads-up.",
      "If this is a mistake, you can dispute it once with a short note: open the app, go to Job Applications and tap Dispute on the shift.",
    ],
  });
}

// Worker: eigene kurzfristige Stornierung wurde vermerkt
function lateCancellationRecorded({ jobTitle, jobId }) {
  const t = job(jobTitle);
  return make("jobActivity", {
    title: "Late cancellation noted",
    body: `You cancelled "${t}" less than 24 hours before it started, so it counts as a late cancellation.`,
    data: { type: "job", jobId },
    subject: `Late cancellation noted: ${t}`,
    paragraphs: [
      `You cancelled "${t}" less than 24 hours before it started, so we noted it as a late cancellation.`,
      "Cancelling earlier gives employers time to find a replacement and keeps your reliability looking good.",
    ],
  });
}

// Employer: ein bestaetigter Worker hat die Schicht storniert
function workerCancelledShift({ workerName, jobTitle, jobId, late }) {
  const t = job(jobTitle);
  const w = who(workerName, "A worker");
  return make("jobActivity", {
    title: "Worker cancelled a shift",
    body: `${w} cancelled their shift for "${t}"${late ? " less than 24 hours before the start" : ""}. The spot is open again.`,
    data: { type: "applicants", jobId },
    subject: `${w} cancelled: ${t}`,
  });
}

// Employer: ~24 h nach Schichtende fehlt noch die Anwesenheit; nach 48 h zaehlt sie automatisch als "showed up"
function attendanceReminder({ jobTitle, pendingCount, jobId }) {
  const t = job(jobTitle);
  const n = Number(pendingCount) || 0;
  return make("jobActivity", {
    title: "Record attendance",
    body: `${n === 1 ? "1 worker is" : `${n} workers are`} still missing an attendance entry for "${t}". Without an entry they count as showed up after 48 hours.`,
    data: { type: "applicants", jobId },
    subject: `Record attendance for ${t}`,
  });
}

// Worker: Admin hat den Einspruch entschieden
function attendanceDisputeResolved({ jobTitle, jobId, resolution, attendance }) {
  const t = job(jobTitle);
  const label = { attended: "showed up", late: "arrived late", no_show: "a no-show" }[attendance];
  const body = resolution === "changed" && label
    ? `We reviewed your dispute for "${t}" and changed the entry to: ${label}.`
    : `We reviewed your dispute for "${t}" and the original entry stays.`;
  return make("jobActivity", {
    title: "Dispute reviewed",
    body,
    data: { type: "job", jobId },
    subject: `Your dispute for ${t} was reviewed`,
  });
}

// ── messages ──
// Push darf eine Vorschau zeigen, die E-Mail NIE den Nachrichtentext.
function newMessagePush({ senderName, jobTitle, text, conversationId }) {
  return {
    title: who(senderName, "New message"),
    body: truncate(text, MAX_BODY),
    data: { type: "chat", conversationId },
  };
}

function unreadMessageEmail({ senderName, jobTitle }) {
  const s = who(senderName, "Someone");
  const t = job(jobTitle);
  const email = renderEmail({
    heading: "You have an unread message",
    paragraphs: [`${s} sent you a message about "${t}".`, "Open the SwipeShift app to read and reply."],
  });
  return { subject: plainLine(`New message from ${s}`, 150), ...email };
}

// ── payments ──
function paymentReceived({ jobTitle, company, jobId }) {
  const t = job(jobTitle);
  return make("payments", {
    title: "Payment sent",
    body: `${who(company, "The employer")} marked your work on "${t}" as paid.`,
    data: { type: "payments", jobId },
    subject: `Payment for ${t}`,
  });
}

function paymentOpen({ jobTitle, unpaidCount, jobId }) {
  const t = job(jobTitle);
  const n = Number(unpaidCount) || 0;
  return make("payments", {
    title: "Payment open",
    body: `${n === 1 ? "1 worker is" : `${n} workers are`} still unpaid for "${t}".`,
    data: { type: "payments", jobId },
    subject: `Payment open for ${t}`,
  });
}

// ── account ──
function reviewReceived({ fromName, jobTitle, jobId }) {
  const t = job(jobTitle);
  return make("account", {
    title: "New review",
    body: `${who(fromName, "Someone")} left you a review for "${t}".`,
    data: { type: "reviews", jobId },
    subject: `You received a new review`,
  });
}

// pausedOk: werden auch an pausierte Konten zugestellt (alle anderen Ereignisse nicht)
function accountPaused() {
  return { pausedOk: true, ...make("account", {
    title: "Account paused",
    body: "Your SwipeShift account is paused. Resume it any time in Settings → Privacy & Data.",
    data: { type: "account" },
    subject: "Your SwipeShift account is paused",
  }) };
}

function accountResumed() {
  return { pausedOk: true, ...make("account", {
    title: "Account resumed",
    body: "Welcome back! Your SwipeShift account is active again.",
    data: { type: "account" },
    subject: "Your SwipeShift account is active again",
  }) };
}

module.exports = {
  formatShiftStart, describeShiftStart, applicationAccepted, applicationDeclined, jobCancelled, shiftReminder,
  noShowRecorded, attendanceReminder, lateCancellationRecorded, workerCancelledShift, attendanceDisputeResolved,
  newApplication, instantMatchBooked, newMessagePush, unreadMessageEmail,
  paymentReceived, paymentOpen, reviewReceived, accountPaused, accountResumed,
};
