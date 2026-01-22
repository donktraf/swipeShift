// scripts/backfillOnboarding.js
const { prisma } = require("../src/prisma");

async function main() {
  await prisma.user.updateMany({
    where: { role: { not: null } },
    data: { onboarding: "complete" },
  });

  await prisma.user.updateMany({
    where: { role: null },
    data: { onboarding: "pendingRole" },
  });

  console.log("✅ Backfill done.");
}

main()
  .catch((e) => {
    console.error(e);
    process.exit(1);
  })
  .finally(async () => {
    await prisma.$disconnect();
  });