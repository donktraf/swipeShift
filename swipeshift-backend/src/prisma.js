// src/prisma.js
require("dotenv").config();

const { PrismaClient } = require("@prisma/client");
const { PrismaPg } = require("@prisma/adapter-pg");

if (!process.env.DATABASE_URL) {
  throw new Error("DATABASE_URL is missing. Check your .env / docker env.");
}

const adapter = new PrismaPg({
  connectionString: process.env.DATABASE_URL,
});

// platformFeePercent ist Employer-intern (Snapshot der Servicegebuehr) und soll nicht in Worker-Job-Antworten
// auftauchen: global ausgeblendet; Employer-Routen lesen es explizit per select (utils/jobCost.js).
const prisma = new PrismaClient({ adapter, omit: { job: { platformFeePercent: true } } });

module.exports = { prisma };