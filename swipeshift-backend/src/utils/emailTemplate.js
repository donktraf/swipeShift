// src/utils/emailTemplate.js
// Einheitliches, schlichtes Layout fuer Benachrichtigungs-Mails (HTML + Text, Englisch). Reine Funktion.
// ALLE Strings werden HTML-escaped — Nutzereingaben (Namen, Jobtitel, Gruende) landen nie roh im HTML.

const FOOTER = "You can change which emails you get in the SwipeShift app under Settings → Notifications.";

function escapeHtml(value) {
  return String(value ?? "")
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")
    .replace(/"/g, "&quot;")
    .replace(/'/g, "&#39;");
}

// Steuerzeichen/Zeilenumbrueche raus (Betreff-/Header-Injection), Laenge begrenzen
function plainLine(value, max = 120) {
  const s = String(value ?? "").replace(/[\u0000-\u001f\u007f\u2028\u2029]/g, " ").replace(/\s+/g, " ").trim();
  return s.length <= max ? s : `${s.slice(0, max - 1).trimEnd()}…`;
}

// { heading, paragraphs: string[] } → { html, text }
function renderEmail({ heading, paragraphs = [] }) {
  const h = plainLine(heading, 160);
  const ps = paragraphs.map((p) => plainLine(p, 600)).filter(Boolean);
  const html = `<div style="font-family:-apple-system,Helvetica,Arial,sans-serif;max-width:480px;margin:0 auto;color:#1c1c1e">
<h2 style="margin:0 0 16px">${escapeHtml(h)}</h2>
${ps.map((p) => `<p style="font-size:15px;line-height:1.5;margin:0 0 12px">${escapeHtml(p)}</p>`).join("\n")}
<hr style="border:none;border-top:1px solid #e5e5ea;margin:24px 0 12px">
<p style="font-size:12px;color:#8e8e93;margin:0">${escapeHtml(FOOTER)}</p>
</div>`;
  const text = `${h}\n\n${ps.join("\n\n")}\n\n--\n${FOOTER}`;
  return { html, text };
}

module.exports = { FOOTER, escapeHtml, plainLine, renderEmail };
