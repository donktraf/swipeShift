// scripts/debug-token.js
// Entwickler-Skript: legt fuer ein bestehendes Konto eine UserSession an und gibt ein JWT aus
// (fuer SS_DEBUG_TOKEN in der iOS-App, siehe scripts/ui-snapshot.sh). Ablauf: 1 Tag.
//   npm run --silent debug:token -- test2@example.de
// Ausgabe auf stdout: nur das Token (Fehler/Hinweise auf stderr).
// Schutz: lehnt NODE_ENV=production und Nicht-Localhost-Datenbanken ab.

// dotenv (v17) loggt sonst nach stdout und wuerde die Token-Ausgabe verunreinigen
process.env.DOTENV_CONFIG_QUIET = "true";
require("dotenv").config({ quiet: true });
const jwt = require("jsonwebtoken");
const { prisma } = require("../src/prisma.js");
const { JWT_SECRET } = require("../src/auth.js");

const DAY_MS = 24 * 60 * 60 * 1000;

function describeDatabase(url) {
  try {
    const u = new URL(url);
    return { host: u.hostname.replace(/^\[|\]$/g, "") };
  } catch { return null; }
}

async function main() {
  if (process.env.NODE_ENV === "production") {
    console.error("Refusing to run: NODE_ENV=production.");
    return 1;
  }
  const db = describeDatabase(process.env.DATABASE_URL || "");
  if (!db) { console.error("Refusing to run: DATABASE_URL missing or unreadable."); return 1; }
  if (!["localhost", "127.0.0.1", "::1"].includes(db.host)) {
    console.error(`Refusing to run: database host "${db.host}" is not local.`);
    return 1;
  }
  const email = String(process.argv[2] || "").trim().toLowerCase();
  if (!email) { console.error("Usage: npm run --silent debug:token -- <email>"); return 1; }

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) { console.error(`No user with email ${email}`); return 1; }

  const session = await prisma.userSession.create({
    data: {
      userId: user.id,
      deviceName: "Debug snapshot",
      expiresAt: new Date(Date.now() + DAY_MS),
    },
  });
  // Wie signToken in src/auth.js, aber mit 1 Tag Laufzeit
  process.stdout.write(jwt.sign(
    { sub: user.id, role: user.role, email: user.email, sid: session.id },
    JWT_SECRET,
    { expiresIn: "1d" }
  ) + "\n");
  return 0;
}

main()
  .then((code) => prisma.$disconnect().then(() => process.exit(code)))
  .catch(async (e) => { console.error(e.message); await prisma.$disconnect(); process.exit(1); });
