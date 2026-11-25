// src/emailBan.js
// Ban-Evasion per E-Mail-Alias: gibt es einen dauerhaft gebannten User mit derselben kanonischen E-Mail?
// (utils/emailCanonical.js). Bestehende, NICHT gebannte Konten mit gleicher kanonischer Adresse sind erlaubt.
// Zusaetzlich: Tombstones geloeschter Konten (DeletedAccount) — gebannt, oder mit noch laufender Admin-Sperre.
const crypto = require("crypto");
const { prisma } = require("./prisma");
const { canonicalEmail } = require("./utils/emailCanonical");
const { getEmailBanPepper, getEmailBanPepperPrev } = require("./utils/totp");

function hmac(pepper, label, value) {
  return crypto.createHmac("sha256", pepper).update(label + value).digest("hex");
}

// HMAC der kanonischen Adresse; null bei leerer Adresse
function hashCanonicalEmail(email, pepper = getEmailBanPepper()) {
  const c = canonicalEmail(email);
  return c ? hmac(pepper, "deleted-email:", c) : null;
}

// HMAC der Apple-Subject-ID; null bei leerem Wert
function hashAppleSub(sub, pepper = getEmailBanPepper()) {
  return typeof sub === "string" && sub ? hmac(pepper, "deleted-apple-sub:", sub) : null;
}

// Aktueller + (optional) vorheriger Pepper
function peppers() {
  const prev = getEmailBanPepperPrev();
  return prev ? [getEmailBanPepper(), prev] : [getEmailBanPepper()];
}

// db/now/pepperList injizierbar (Tests)
async function isBannedEmailAlias(email, { excludeUserId, appleSub, db = prisma, now = new Date(), pepperList } = {}) {
  const emailCanonical = canonicalEmail(email);
  if (!emailCanonical) return false;
  const hit = await db.user.findFirst({
    where: { emailCanonical, bannedAt: { not: null }, ...(excludeUserId ? { id: { not: excludeUserId } } : {}) },
    select: { id: true },
  });
  if (hit) return true;
  const list = pepperList || peppers();
  const emailHashes = list.map((p) => hashCanonicalEmail(email, p)).filter(Boolean);
  const subHashes = list.map((p) => hashAppleSub(appleSub, p)).filter(Boolean);
  const or = [];
  if (emailHashes.length) or.push({ emailCanonicalHash: { in: emailHashes } });
  if (subHashes.length) or.push({ appleSubHash: { in: subHashes } });
  if (!or.length) return false;
  const dead = await db.deletedAccount.findFirst({
    where: { OR: or, AND: [{ OR: [{ bannedAt: { not: null } }, { suspendedUntil: { gt: now } }] }] },
    select: { id: true },
  });
  return !!dead;
}

module.exports = { isBannedEmailAlias, hashCanonicalEmail, hashAppleSub };
