/**
 * ⚠️ DEV ONLY
 * Löscht ALLE User und alle abhängigen Daten.
 *
 * Ausführen mit:
 *   node src/scripts/deleteAllUsers.js
 */

require("dotenv").config();
const { prisma } = require("../prisma.js");


//const prisma = new PrismaClient();

async function main() {
  console.log("⚠️ Deleting ALL users and related data...");

  // Reihenfolge ist wichtig wegen Foreign Keys
  await prisma.passwordResetToken.deleteMany();
  await prisma.emailVerificationToken.deleteMany();

  await prisma.worker.deleteMany();
  await prisma.employer.deleteMany();

  const result = await prisma.user.deleteMany();

  console.log(`✅ Deleted ${result.count} users`);
}

main()
  .catch((e) => {
    console.error("Error while deleting users:", e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });