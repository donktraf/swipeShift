// src/accountTakeover.js
// Pre-Hijacking-Schutz: wird ein bisher UNVERIFIZIERTES Passwort-Konto per Social Login (verifizierte Token-E-Mail)
// uebernommen, verliert alles, was ein Angreifer vorher setzen konnte: Passwort, 2FA/TOTP/Backup-Codes,
// hinterlegte Auszahlungsdaten, Sitzungen und Push-Geraete. Danach gilt die E-Mail als verifiziert.
const { prisma } = require("./prisma.js");
const { revokeAllSessions } = require("./moderation");
const { stripPayout } = require("./utils/socialLogin");

async function sanitizeTakenOverAccount(user) {
  const userId = user.id;
  const updated = await prisma.$transaction(async (tx) => {
    await tx.twoFactorBackupCode.deleteMany({ where: { userId } });
    await tx.twoFactorCode.deleteMany({ where: { userId } });
    await tx.twoFactorLock.deleteMany({ where: { userId } });
    return tx.user.update({
      where: { id: userId },
      data: {
        passwordHash: "SOCIAL_LOGIN", // vom Angreifer gesetztes Passwort ist ungueltig
        emailVerifiedAt: new Date(),
        twoFactorEnabled: false, twoFactorMethod: null,
        totpSecretEnc: null, totpPendingEnc: null, totpLastStep: null, totpPendingAt: null,
        settings: stripPayout(user.settings) ?? undefined,
      },
    });
  });
  await revokeAllSessions(userId); // inkl. Push-Geraete
  return updated;
}

module.exports = { sanitizeTakenOverAccount };
