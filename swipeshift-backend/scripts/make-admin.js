// scripts/make-admin.js
// Vergibt/entzieht das Admin-Recht (Moderation) — der EINZIGE Weg, isAdmin zu setzen (nie per API).
//   npm run make-admin -- <email>
//   npm run make-admin -- <email> --remove

require("dotenv").config();
const { prisma } = require("../src/prisma.js");

async function main() {
  const args = process.argv.slice(2);
  const remove = args.includes("--remove");
  const email = args.find((a) => !a.startsWith("--"));
  if (!email) {
    console.error("Usage: npm run make-admin -- <email> [--remove]");
    return 1;
  }
  const user = await prisma.user.findUnique({ where: { email: email.trim().toLowerCase() }, select: { id: true, email: true, isAdmin: true } });
  if (!user) {
    console.error(`No user with email ${email}`);
    return 1;
  }
  await prisma.user.update({ where: { id: user.id }, data: { isAdmin: !remove } });
  console.log(`${user.email}: isAdmin = ${!remove}`);
  return 0;
}

main()
  .then((code) => { process.exitCode = code; })
  .catch((err) => { console.error(err); process.exitCode = 1; })
  .finally(() => prisma.$disconnect());
