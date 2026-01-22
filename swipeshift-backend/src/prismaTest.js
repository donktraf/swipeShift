const { prisma } = require("@prisma/client");
//const prisma = new PrismaClient();

async function test() {
  const result = await prisma.$queryRaw`SELECT 1 as ok`;
  console.log("DB connected:", result);
}

test()
  .catch(console.error)
