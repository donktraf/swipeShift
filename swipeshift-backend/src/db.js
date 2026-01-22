// src/db.js
// In-memory DB fürs MVP. Später ersetzen wir das durch Postgres (Prisma/Knex).

const { v4: uuid } = require("uuid");
const bcrypt = require("bcrypt");

// --- Users ---
// user = { id, fullName, email, passwordHash, role, createdAt }
// const users = [];
const users = [
  {
    id: uuid(),
    fullName: "Demo Worker",
    email: "demo@test.de",
    passwordHash: bcrypt.hashSync("pw", 10),
    role: "worker",
    createdAt: new Date().toISOString(),
    location: "Berlin"
  }
];

// --- Jobs ---
// job = { id, title, company, location, payText, distanceText, shiftText, shortInfo, tags, logoEmoji }
const jobs = [
  {
    id: uuid(),
    title: "Event Staff",
    company: "Berlin Events GmbH",
    location: "Berlin",
    payText: "€15 / hour",
    distanceText: "1.2 km away",
    shiftText: "Today, 18:00–23:00",
    shortInfo: "Help with setup, registration and guest support at an evening event.",
    tags: ["Flexible", "Same-day pay", "No experience"],
    logoEmoji: "🎪",
  },
  {
    id: uuid(),
    title: "Retail Assistant",
    company: "Urban Fashion Store",
    location: "Hamburg",
    payText: "€13 / hour",
    distanceText: "3.5 km away",
    shiftText: "Sat, 10:00–18:00",
    shortInfo: "Support customers on the floor and help with inventory.",
    tags: ["Weekend", "Customer-facing"],
    logoEmoji: "🛍️",
  },
  {
    id: uuid(),
    title: "Office Support von Kevin",
    company: "Startup Hub",
    location: "Berlin",
    payText: "€18 / hour",
    distanceText: "Remote",
    shiftText: "Mon–Wed, 09:00–13:00",
    shortInfo: "Light admin tasks, email replies and calendar updates.",
    tags: ["Remote", "Part-time"],
    logoEmoji: "💻",
  },  {
    id: uuid(),
    title: "Kevin Super Firma",
    company: "Berlin Events GmbH",
    location: "HH",
    payText: "€15 / hour",
    distanceText: "1.2 km away",
    shiftText: "Today, 18:00–23:00",
    shortInfo: "Help with setup, registration and guest support at an evening event.",
    tags: ["Flexible", "Same-day pay", "No experience"],
    logoEmoji: "🎪",
  },  {
    id: uuid(),
    title: "p2Trapp Gebäude",
    company: "Berlin Events GmbH",
    location: "HH",
    payText: "€15 / hour",
    distanceText: "1.2 km away",
    shiftText: "Today, 18:00–23:00",
    shortInfo: "Help with setup, registration and guest support at an evening event.",
    tags: ["Flexible", "Same-day pay", "No experience"],
    logoEmoji: "🎪",
  }
];

// --- Interactions (für später) ---
// z.B. apply/skip/save: { userId, jobId, createdAt }
const applies = [];
const skips = [];
const saves = [];

module.exports = {
  users,
  jobs,
  applies,
  skips,
  saves,
};
