function passwordResetEmail({ resetLink, fallbackLink, expiresMinutes = 30 }) {
  const subject = "Reset your SwipeShift password";

  const text = [
    "You requested a password reset.",
    `Reset link (expires in ${expiresMinutes} minutes):`,
    resetLink,
    "",
    "If the link doesn't open, use this fallback:",
    fallbackLink,
  ].join("\n");

  const html = `
  <div style="font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Arial; line-height: 1.4;">
    <h2>Reset your password</h2>
    <p>You requested a password reset. This link expires in <b>${expiresMinutes} minutes</b>.</p>

    <p>
      <a href="${resetLink}"
         style="display:inline-block;padding:12px 16px;border-radius:10px;background:#2563eb;color:#fff;text-decoration:none;">
         Reset password
      </a>
    </p>

    <p style="color:#555;">
      If the button doesn't work, open this link:<br/>
      <a href="${resetLink}">${resetLink}</a>
    </p>

    <hr style="border:none;border-top:1px solid #eee;margin:16px 0;" />

    <p style="color:#777;font-size:12px;">
      Fallback (web): <a href="${fallbackLink}">${fallbackLink}</a>
    </p>
  </div>
  `;

  return { subject, text, html };
}

module.exports = { passwordResetEmail };