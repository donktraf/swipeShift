// src/emailBan.js
// Ban-Evasion per E-Mail-Alias: gibt es einen dauerhaft gebannten User mit derselben kanonischen E-Mail?
// (utils/emailCanonical.js). Bestehende, NICHT gebannte Konten mit gleicher kanonischer Adresse sind erlaubt.
const { prisma } = require("./prisma");
const { canonicalEmail } = require("./utils/emailCanonical");

async function isBannedEmailAlias(email, { excludeUserId } = {}) {
  const emailCanonical = canonicalEmail(email);
  if (!emailCanonical) return false;
  const hit = await prisma.user.findFirst({
    where: { emailCanonical, bannedAt: { not: null }, ...(excludeUserId ? { id: { not: excludeUserId } } : {}) },
    select: { id: true },
  });
  return !!hit;
}

module.exports = { isBannedEmailAlias };
