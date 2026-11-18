// scripts/rotate-totp-key.js
// Verschluesselt alle mit TOTP_ENCRYPTION_KEY geschuetzten Daten mit dem AKTUELLEN Key neu:
//   - TOTP-Secrets (User.totpSecretEnc / totpPendingEnc)
//   - Bank-Kontonummern der Auszahlung (User.settings.payout.bank.accountEnc, AAD "bank:<userId>")
// Der Key TOTP_ENCRYPTION_KEY schuetzt also TOTP-Secrets UND Bankdaten. Danach TOTP_ENCRYPTION_KEY_PREVIOUS danach entfernt werden kann.
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
// Exit-Code 0 / "remaining: 0" gilt nur, wenn TOTP- UND Bank-Payloads auf dem neuen Key liegen.
// Jede Zeile wird per Compare-and-Set (Bankdaten: jsonb_set mit WHERE auf den alten Wert) aktualisiert (nur wenn der Wert unveraendert ist), das Skript
// ist idempotent und kann parallel zum laufenden Backend laufen. Secrets werden nie ausgegeben.

require("dotenv").config();
const { prisma } = require("../src/prisma.js");
const totp = require("../src/utils/totp");
const bankDetails = require("../src/utils/bankDetails");

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

  // Bank-Kontonummern in User.settings (jsonb); nur das Feld accountEnc wird per jsonb_set ersetzt
  const bankRows = await prisma.$queryRaw`
    SELECT "id", "settings" #>> '{payout,bank,accountEnc}' AS enc FROM "User"
    WHERE "settings" #>> '{payout,bank,accountEnc}' IS NOT NULL`;
  for (const row of bankRows) {
    let next;
    try {
      next = bankDetails.reencryptAccountNumber(row.enc, row.id, keyring);
    } catch (err) {
      failed++;
      console.error(`FAILED userId=${row.id} field=settings.payout.bank.accountEnc: ${err.message}`);
      continue;
    }
    if (next === null) { alreadyCurrent++; continue; }
    if (dryRun) { rotated++; continue; }
    const count = await prisma.$executeRaw`
      UPDATE "User" SET "settings" = jsonb_set("settings", '{payout,bank,accountEnc}', to_jsonb(${next}::text))
      WHERE "id" = ${row.id} AND "settings" #>> '{payout,bank,accountEnc}' = ${row.enc}`;
    if (count === 1) rotated++; else conflicts++;
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
