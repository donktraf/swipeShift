const nodemailer = require("nodemailer");

function createTransporter() {
  const host = process.env.SMTP_HOST || "localhost";
  const port = Number(process.env.SMTP_PORT || 1025);

  // MailHog braucht kein Auth. Wenn du später SendGrid/SES nutzt, schaltest du auth ein.
  const transporter = nodemailer.createTransport({
    host,
    port,
    secure: false,
    ignoreTLS: true, // MailHog ist plain SMTP
  });

  return transporter;
}

async function sendMail({ to, subject, html, text }) {
  console.log("Email verschickt.")
  const transporter = createTransporter();

  const from = process.env.MAIL_FROM || "SwipeShift <no-reply@swipeshift.local>";

  const info = await transporter.sendMail({
    from,
    to,
    subject,
    text,
    html,
  });

  return info;
}

module.exports = { sendMail };