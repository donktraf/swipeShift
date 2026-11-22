// src/utils/emailChangeNotice.js
// Sicherheits-Mail an die ALTE Adresse nach einer E-Mail-Aenderung (rein, DB-frei). Alle Texte HTML-escaped (renderEmail).
const { renderEmail, plainLine } = require("./emailTemplate");

const SUPPORT_EMAIL = "support@swipeshift.app";

// "kevin@gmail.com" → "k***@gmail.com" (nur erstes Zeichen des Local-Parts sichtbar)
function maskEmail(email) {
  const e = plainLine(email, 254);
  const at = e.lastIndexOf("@");
  if (at < 1) return "***";
  return `${e.slice(0, 1)}***${e.slice(at)}`;
}

// → { subject, text, html }
function emailChangedNotice({ newEmail }) {
  const masked = maskEmail(newEmail);
  const { html, text } = renderEmail({
    heading: "Your SwipeShift email was changed",
    paragraphs: [
      `Your email was changed to ${masked}. If this wasn't you, contact ${SUPPORT_EMAIL}.`,
    ],
    footer: "This is a security notice about your SwipeShift account.",
  });
  return { subject: "Your SwipeShift email was changed", text, html };
}

module.exports = { SUPPORT_EMAIL, maskEmail, emailChangedNotice };
