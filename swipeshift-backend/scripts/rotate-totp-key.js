// scripts/rotate-totp-key.js
// Verschluesselt alle gespeicherten TOTP-Secrets (User.totpSecretEnc / totpPendingEnc) mit dem
// AKTUELLEN Key neu, damit TOTP_ENCRYPTION_KEY_PREVIOUS danach entfernt werden kann.
//
// Ablauf einer Key-Rotation:
//   1. Neuen Key erzeugen:   openssl rand -hex 32
//   2. In der Umgebung setzen: TOTP_ENCRYPTION_KEY_PREVIOUS=<alter Key>, TOTP_ENCRYPTION_KEY=<neuer Key>
//      (BACKUP_CODE_PEPPER bleibt unveraendert — Backup-Codes sind davon nicht betroffen)
//   3. Backend neu starten, dann dieses Skript ausfuehren:
//        node scripts/rotate-totp-key.js            # rotiert
//        node scripts/rotate-totp-key.js --dry-run  # zaehlt nur
//   4. Bei Exit-Code 0 (keine Fehler, "remaining: 0") TOTP_ENCRYPTION_KEY_PREVIOUS entfernen.
//
// Jede Zeile wird per Compare-and-Set aktualisiert (nur wenn der Wert unveraendert ist), das Skript
// ist idempotent und kann parallel zum laufenden Backend laufen. Secrets werden nie ausgegeben.

require("dotenv").config();
const { prisma } = require("../src/prisma.js");
const totp = require("../src/utils/totp");

async function main() {
  const dryRun = process.argv.includes("--dry-run");
  const keyring = totp.getKeyring();
  console.log(`Current key id: ${keyring.current.kid}; previous: ${keyring.previous ? keyring.previous.kid : "none"}${dryRun ? " (dry run)" : ""}`);

  const users = await prisma.user.findMany({
    where: { OR: [{ totpSecretEnc: { not: null } }, { totpPendingEnc: { not: null } }] },
    select: { id: true, totpSecretEnc: true, totpPendingEnc: true },
  });

  let rotated = 0, alreadyCurrent = 0, failed = 0, conflicts = 0;
  for (const u of users) {
    for (const field of ["totpSecretEnc", "totpPendingEnc"]) {
      const old = u[field];
      if (!old) continue;
      let next;
      try {
        next = totp.reencryptPayload(old, u.id, keyring);
      } catch (err) {
        failed++;
        console.error(`FAILED userId=${u.id} field=${field}: ${err.message}`);
        continue;
      }
      if (next === null) { alreadyCurrent++; continue; }
      if (dryRun) { rotated++; continue; }
      const { count } = await prisma.user.updateMany({ where: { id: u.id, [field]: old }, data: { [field]: next } });
      if (count === 1) rotated++; else conflicts++;
    }
  }

  const remaining = dryRun ? rotated : conflicts + failed;
  console.log(`rotated: ${rotated}, already current: ${alreadyCurrent}, conflicts (rerun): ${conflicts}, failed: ${failed}, remaining: ${remaining}`);
  await prisma.$disconnect();
  process.exit(failed > 0 || conflicts > 0 ? 1 : 0);
}

main().catch(async (err) => {
  console.error(err);
  await prisma.$disconnect().catch(() => {});
  process.exit(1);
});
