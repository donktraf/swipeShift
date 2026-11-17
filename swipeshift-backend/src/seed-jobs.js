#!/usr/bin/env node
// src/seed-jobs.js
// Usage:  node src/seed-jobs.js [count]
// Default count: 30
// Inserts random realistic jobs into PostgreSQL via Prisma.
// Deletes ALL existing jobs first (clean slate) unless --append flag is set.

const { prisma } = require("./prisma");
const { formatAmount, formatPayText } = require("./utils/jobData");

// ─── Config ──────────────────────────────────────────────────────────────────

const COUNT   = parseInt(process.argv[2]) || 30;
const APPEND  = process.argv.includes("--append");

// ─── Location pool (German cities with real coordinates) ─────────────────────

const LOCATIONS = [
  { city: "Berlin Mitte",         lat: 52.5200, lng: 13.4050 },
  { city: "Berlin Prenzlauer Berg", lat: 52.5376, lng: 13.4133 },
  { city: "Berlin Kreuzberg",     lat: 52.4993, lng: 13.4030 },
  { city: "Hamburg Altona",       lat: 53.5500, lng: 9.9350  },
  { city: "Hamburg Eppendorf",    lat: 53.5935, lng: 9.9869  },
  { city: "Hamburg HafenCity",    lat: 53.5410, lng: 9.9998  },
  { city: "Munich Schwabing",     lat: 48.1627, lng: 11.5811 },
  { city: "Munich Maxvorstadt",   lat: 48.1500, lng: 11.5700 },
  { city: "Munich Glockenbachviertel", lat: 48.1290, lng: 11.5670 },
  { city: "Cologne Innenstadt",   lat: 50.9333, lng: 6.9500  },
  { city: "Cologne Ehrenfeld",    lat: 50.9556, lng: 6.9144  },
  { city: "Frankfurt Sachsenhausen", lat: 50.0993, lng: 8.6843 },
  { city: "Frankfurt Bornheim",   lat: 50.1210, lng: 8.7180  },
  { city: "Stuttgart Mitte",        lat: 48.7758, lng: 9.1829  },
  { city: "Stuttgart Vaihingen",    lat: 48.7393, lng: 9.1598  },
  { city: "Stuttgart Bad Cannstatt",lat: 48.8069, lng: 9.2230  },
  { city: "Stuttgart Zuffenhausen", lat: 48.8269, lng: 9.1760  },
  { city: "Stuttgart Degerloch",    lat: 48.7444, lng: 9.1920  },
  { city: "Stuttgart Feuerbach",    lat: 48.8100, lng: 9.1580  },
  { city: "Stuttgart Möhringen",    lat: 48.7230, lng: 9.1700  },
  { city: "Stuttgart Stammheim",    lat: 48.8380, lng: 9.1860  },
  { city: "Stuttgart Weilimdorf",   lat: 48.8192, lng: 9.1325  },
  { city: "Stuttgart Plieningen",   lat: 48.7066, lng: 9.2189  },
  { city: "Stuttgart Wangen",       lat: 48.7740, lng: 9.2410  },
  { city: "Stuttgart Obertürkheim", lat: 48.7769, lng: 9.2673  },
  { city: "Stuttgart Sillenbuch",   lat: 48.7380, lng: 9.2310  },
  { city: "Stuttgart Botnang",      lat: 48.7900, lng: 9.1340  },
  { city: "Stuttgart Mühlhausen",   lat: 48.8460, lng: 9.2190  },
  { city: "Düsseldorf Altstadt",  lat: 51.2255, lng: 6.7762  },
  { city: "Düsseldorf Flingern",  lat: 51.2212, lng: 6.8134  },
  { city: "Leipzig Gohlis",       lat: 51.3599, lng: 12.3723 },
  { city: "Leipzig Connewitz",    lat: 51.3144, lng: 12.3734 },
  { city: "Dresden Neustadt",     lat: 51.0659, lng: 13.7390 },
  { city: "Nuremberg Gostenhof",  lat: 49.4561, lng: 11.0537 },
  { city: "Hannover Linden",      lat: 52.3618, lng: 9.7072  },
  { city: "Bremen Neustadt",      lat: 53.0721, lng: 8.7946  },
  { city: "Dortmund Innenstadt",  lat: 51.5136, lng: 7.4653  },
  { city: "Essen Rüttenscheid",   lat: 51.4398, lng: 7.0160  },
];

// ─── Category pool ────────────────────────────────────────────────────────────

const CATEGORIES = [
  {
    name: "Hospitality",
    emoji: "🍽️",
    titles: ["Bartender", "Waiter", "Waitress", "Restaurant Host", "Barista", "Catering Staff", "Kitchen Helper"],
    tags: ["Customer-facing", "Tips included", "Evening shift", "Fast-paced", "Uniform provided"],
    tasks: [
      "Take orders and serve guests",
      "Prepare drinks and cocktails",
      "Set up and clean tables",
      "Handle cash and card payments",
      "Support kitchen with food prep",
      "Welcome and seat guests",
    ],
    dressCode: ["Smart Casual", "Black & White", "Uniform provided", "Dark clothes"],
    description: "We are looking for a motivated and friendly team member to join our hospitality team. You will be working in a fast-paced environment serving guests and ensuring a great experience. No prior experience required — we train you on the job.",
  },
  {
    name: "Events",
    emoji: "🎪",
    titles: ["Event Staff", "Event Helper", "Venue Assistant", "Event Setup Crew", "Crowd Manager", "Ticket Scanner"],
    tags: ["Flexible", "Same-day pay", "No experience", "Team work", "Indoor/Outdoor"],
    tasks: [
      "Welcome and guide guests at the entrance",
      "Help with venue setup and breakdown",
      "Distribute food, drinks and merchandise",
      "Answer guest questions and assist navigation",
      "Monitor crowd flow and ensure safety",
      "Support the event coordinator",
    ],
    dressCode: ["Smart Casual", "Event t-shirt provided", "Black outfit", "Comfortable shoes required"],
    description: "Join our event team and be part of exciting events across the city. You will support our team with setup, guest management and general event operations. Great opportunity to earn extra income on weekends and evenings.",
  },
  {
    name: "Logistics",
    emoji: "📦",
    titles: ["Warehouse Packer", "Forklift Operator", "Delivery Helper", "Picker & Packer", "Stock Handler", "Night Shift Loader"],
    tags: ["Physical", "Night shift", "Boots required", "Weekly pay", "Heavy lifting"],
    tasks: [
      "Pick and pack outgoing orders",
      "Scan and log incoming shipments",
      "Stack and organise warehouse shelves",
      "Prepare pallets for dispatch",
      "Keep the warehouse clean and tidy",
      "Report stock discrepancies to supervisor",
    ],
    dressCode: ["Safety shoes (mandatory)", "High-vis vest provided", "Comfortable work clothes", "Gloves recommended"],
    description: "We need reliable hands at our logistics hub. The role involves physical work — picking, packing and loading goods for delivery. Safety shoes are required. All other PPE is provided on site. Night and weekend shifts available.",
  },
  {
    name: "Retail",
    emoji: "🛍️",
    titles: ["Retail Assistant", "Shop Floor Helper", "Sales Associate", "Fitting Room Attendant", "Cashier", "Stock Replenisher"],
    tags: ["Weekend", "Customer-facing", "Uniform provided", "Part-time", "Commission possible"],
    tasks: [
      "Assist customers on the shop floor",
      "Operate the cash register",
      "Restock shelves and maintain displays",
      "Process returns and exchanges",
      "Keep the store clean and organised",
      "Support inventory counts",
    ],
    dressCode: ["Own clothes (smart, clean)", "Uniform provided", "Brand clothing required", "Neat appearance"],
    description: "Support our retail team during busy trading hours. You will serve customers, operate the till and keep the store looking great. Previous retail or customer service experience is a plus but not required.",
  },
  {
    name: "Office",
    emoji: "💼",
    titles: ["Office Support", "Admin Assistant", "Data Entry Clerk", "Receptionist", "Document Coordinator", "Office Runner"],
    tags: ["Remote possible", "Part-time", "Flexible", "Professional environment", "Office hours"],
    tasks: [
      "Handle incoming calls and emails",
      "Organise and file documents",
      "Update spreadsheets and databases",
      "Schedule meetings and manage calendars",
      "Support the team with ad-hoc admin tasks",
      "Greet visitors and manage the front desk",
    ],
    dressCode: ["Business Casual", "Smart Casual", "Business Formal", "No dress code (remote)"],
    description: "We need an organised and reliable admin support person to join our office team. Tasks include handling correspondence, managing documents and supporting day-to-day operations. Great opportunity for someone looking for flexible part-time work.",
  },
  {
    name: "Warehouse",
    emoji: "🏭",
    titles: ["Warehouse Worker", "Goods Receiver", "Returns Processor", "Inventory Counter", "Dispatch Handler", "Labelling Operative"],
    tags: ["Physical", "Early start", "Team environment", "Training provided", "Same-day pay"],
    tasks: [
      "Receive and check incoming deliveries",
      "Process customer returns accurately",
      "Label and sort outgoing parcels",
      "Count and verify stock levels",
      "Operate basic warehouse equipment",
      "Maintain a safe and tidy work area",
    ],
    dressCode: ["Safety shoes (mandatory)", "Work clothes provided", "Comfortable clothing", "High-vis vest required"],
    description: "Join our warehouse operations team and help keep our supply chain running smoothly. Physical work in a structured environment. Full training provided. Safety footwear is required — all other equipment is supplied.",
  },
  {
    name: "Cleaning",
    emoji: "🧹",
    titles: ["Office Cleaner", "Hotel Housekeeper", "End-of-Tenancy Cleaner", "Event Venue Cleaner", "Window Cleaner", "Industrial Cleaner"],
    tags: ["Early morning", "Flexible hours", "Equipment provided", "Solo work possible", "Recurring shifts"],
    tasks: [
      "Clean and sanitise offices and common areas",
      "Vacuum, mop and dust all surfaces",
      "Clean toilets, kitchens and break rooms",
      "Restock cleaning supplies and consumables",
      "Report maintenance issues to management",
      "Follow health and safety cleaning protocols",
    ],
    dressCode: ["Uniform provided", "Comfortable work clothes", "Closed-toe shoes", "PPE provided"],
    description: "We are looking for reliable cleaners to maintain our facilities to a high standard. Equipment and supplies are provided. Shifts are available early mornings, evenings and weekends. Ideal for someone who works well independently.",
  },
  {
    name: "Customer Service",
    emoji: "🎧",
    titles: ["Customer Service Agent", "Call Centre Operator", "Help Desk Support", "Live Chat Agent", "Support Specialist", "Customer Advisor"],
    tags: ["Remote possible", "Part-time", "Communication skills", "Evening shifts", "Training provided"],
    tasks: [
      "Handle inbound customer enquiries via phone or chat",
      "Resolve complaints and escalate where needed",
      "Log all interactions in the CRM system",
      "Follow up with customers on open tickets",
      "Maintain a professional and friendly tone",
      "Meet daily call and satisfaction targets",
    ],
    dressCode: ["Smart Casual (on-site)", "No dress code (remote)", "Professional appearance", "Brand polo provided"],
    description: "Join our customer service team and help our customers get the support they need. You will handle inbound calls and chats, resolve queries and escalate complex issues. Full training provided. Excellent communication skills required.",
  },
];

// ─── Company pool ─────────────────────────────────────────────────────────────

const COMPANIES = [
  { name: "EventPro GmbH",      rating: 4.6, reply: "Usually replies within 2 hours",  verified: true  },
  { name: "LogiSpeed AG",       rating: 3.9, reply: "Usually replies within 30 minutes", verified: false },
  { name: "Urban Retail Group", rating: 4.2, reply: "Usually replies within 4 hours",  verified: true  },
  { name: "TalentForce GmbH",   rating: 4.8, reply: "Usually replies within 1 hour",   verified: true  },
  { name: "QuickShift Berlin",  rating: 4.5, reply: "Usually replies within 3 hours",  verified: true  },
  { name: "FlexWork Solutions", rating: 4.1, reply: "Usually replies within 6 hours",  verified: false },
  { name: "StaffHub Hamburg",   rating: 4.7, reply: "Usually replies within 2 hours",  verified: true  },
  { name: "ProClean Services",  rating: 4.3, reply: "Usually replies within 5 hours",  verified: true  },
  { name: "NightOwl Logistics", rating: 4.0, reply: "Usually replies within 1 hour",   verified: true  },
  { name: "FreshBrew Co.",      rating: 4.5, reply: "Usually replies within 3 hours",  verified: true  },
  { name: "GourmetEvents AG",   rating: 4.9, reply: "Usually replies within 1 hour",   verified: true  },
  { name: "MetroRetail GmbH",   rating: 3.8, reply: "Usually replies within 8 hours",  verified: false },
  { name: "Skyline Services",   rating: 4.6, reply: "Usually replies within 2 hours",  verified: true  },
  { name: "Helix Office Group", rating: 4.4, reply: "Usually replies within 4 hours",  verified: true  },
  { name: "PackFast GmbH",      rating: 4.2, reply: "Usually replies within 2 hours",  verified: true  },
];

// ─── Pay ranges per category ──────────────────────────────────────────────────

const PAY = {
  Hospitality:      { min: 12, max: 18 },
  Events:           { min: 11, max: 16 },
  Logistics:        { min: 14, max: 22 },
  Retail:           { min: 12, max: 15 },
  Office:           { min: 16, max: 28 },
  Warehouse:        { min: 14, max: 20 },
  Cleaning:         { min: 11, max: 16 },
  "Customer Service": { min: 13, max: 20 },
};

// ─── Shift time pools ─────────────────────────────────────────────────────────

const SHIFT_STARTS = [
  { label: "Morning",   start: "07:00", duration: 5 },
  { label: "Morning",   start: "08:00", duration: 4 },
  { label: "Morning",   start: "09:00", duration: 6 },
  { label: "Afternoon", start: "12:00", duration: 4 },
  { label: "Afternoon", start: "13:00", duration: 5 },
  { label: "Afternoon", start: "14:00", duration: 6 },
  { label: "Evening",   start: "17:00", duration: 5 },
  { label: "Evening",   start: "18:00", duration: 5 },
  { label: "Evening",   start: "19:00", duration: 4 },
  { label: "Night",     start: "22:00", duration: 6 },
  { label: "Night",     start: "23:00", duration: 7 },
];

const CONTRACT_TYPES   = ["Freelance", "Temporary", "Mini-Job", "Insurance"];
const PAYMENT_METHODS  = ["Same-day Pay", "Weekly", "Biweekly", "In-app Wallet"];
const EXPERIENCE_LEVELS = ["No experience needed", "3–12 months preferred", "1+ year preferred", "2+ years required"];
const LANGUAGES         = ["German", "English", "Both German and English", "German or English"];

// ─── Helpers ──────────────────────────────────────────────────────────────────

function pick(arr) {
  return arr[Math.floor(Math.random() * arr.length)];
}

function randInt(min, max) {
  return Math.floor(Math.random() * (max - min + 1)) + min;
}

function shuffle(arr) {
  return [...arr].sort(() => Math.random() - 0.5);
}

function addMinutes(date, mins) {
  return new Date(date.getTime() + mins * 60_000);
}

function addHours(date, h) {
  return new Date(date.getTime() + h * 3_600_000);
}

function addDays(date, d) {
  return new Date(date.getTime() + d * 86_400_000);
}

function setHHMM(date, hhmm) {
  const [h, m] = hhmm.split(":").map(Number);
  const d = new Date(date);
  d.setHours(h, m, 0, 0);
  return d;
}

function formatHHMM(date) {
  return date.toTimeString().slice(0, 5);
}

function formatShiftDate(date) {
  const days = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${days[date.getDay()]}, ${date.getDate()}. ${months[date.getMonth()]}`;
}

function formatShiftDateShort(date) {
  const months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
  return `${months[date.getMonth()]} ${date.getDate()}`;
}

// ─── Job factory ──────────────────────────────────────────────────────────────

function generateJob(index) {
  const cat     = pick(CATEGORIES);
  const loc     = pick(LOCATIONS);
  const company = pick(COMPANIES);
  const title   = pick(cat.titles);
  const pay     = PAY[cat.name];
  const payAmt  = randInt(pay.min, pay.max);

  // Add small random noise to coordinates so jobs don't cluster on the exact same spot
  const latJitter = (Math.random() - 0.5) * 0.03;
  const lngJitter = (Math.random() - 0.5) * 0.05;

  const now = new Date();

  // Spread start times across several time windows so all dashboard sections get populated:
  // 20% → starts in 1-4h  (quickMoney candidates)
  // 30% → starts in 4-48h (startingSoon candidates)
  // 50% → starts in 2-14 days (general pool)
  const dice = Math.random();
  let startDate;
  if (dice < 0.20) {
    startDate = addHours(now, randInt(1, 4));
  } else if (dice < 0.50) {
    startDate = addHours(now, randInt(4, 48));
  } else {
    startDate = addDays(now, randInt(2, 14));
  }

  const shiftTemplate = pick(SHIFT_STARTS);
  const shiftStart    = setHHMM(startDate, shiftTemplate.start);
  const shiftEnd      = addHours(shiftStart, shiftTemplate.duration);
  const endHHMM       = formatHHMM(shiftEnd);

  const isToday    = shiftStart.toDateString() === now.toDateString();
  const isTomorrow = shiftStart.toDateString() === addDays(now, 1).toDateString();
  const dayLabel   = isToday ? "Today" : isTomorrow ? "Tomorrow" : formatShiftDate(shiftStart);

  const shiftText  = `${dayLabel}, ${shiftTemplate.start}–${endHHMM}`;
  const duration   = `${shiftTemplate.duration} hours`;

  const openSpots = randInt(1, 6);
  const totalPay  = payAmt * shiftTemplate.duration;

  // Build 1–3 extra shifts
  const numShifts = randInt(1, 3);
  const shifts = [];
  for (let s = 0; s < numShifts; s++) {
    const sd = addDays(shiftStart, s * randInt(1, 3));
    const se = addHours(sd, shiftTemplate.duration);
    shifts.push({
      id:        `${Date.now()}-${index}-${s}`,
      date:      formatShiftDate(sd),
      timeRange: `${shiftTemplate.start}–${formatHHMM(se)}`,
      duration,
      totalPay:  `${formatAmount(payAmt * shiftTemplate.duration)} total`,
    });
  }

  const selectedTasks = shuffle(cat.tasks).slice(0, randInt(3, 5));
  const selectedTags  = shuffle(cat.tags).slice(0, randInt(2, 4));

  return {
    title,
    company:       company.name,
    location:      loc.city,
    lat:           loc.lat + latJitter,
    lng:           loc.lng + lngJitter,
    payAmount:     payAmt,
    payText:       formatPayText(payAmt),
    startTime:     shiftStart,
    endTime:       shiftEnd,
    shiftText,
    duration,
    shortInfo:     cat.description.slice(0, 120),
    jobDescription: cat.description,
    tasks:         selectedTasks,
    openSpots,
    tags:          selectedTags,
    logoEmoji:     cat.emoji,
    category:      cat.name,
    shifts,
    dressCode:     pick(cat.dressCode),
    languages:     [pick(LANGUAGES)],
    experienceLevel: pick(EXPERIENCE_LEVELS),
    minAge:        randInt(16, 21),
    paymentMethod: pick(PAYMENT_METHODS),
    contractType:  pick(CONTRACT_TYPES),
    companyRating: company.rating,
    replyTime:     company.reply,
    isVerified:    company.verified,
    status:        "published",
    employerId:    null,
  };
}

// ─── Main ─────────────────────────────────────────────────────────────────────

async function main() {
  console.log(`\n🌱  SwipeShift Job Seeder`);
  console.log(`   Mode:  ${APPEND ? "append" : "replace"}`);
  console.log(`   Count: ${COUNT}\n`);

  if (!APPEND) {
    const deleted = await prisma.job.deleteMany({});
    console.log(`🗑️   Deleted ${deleted.count} existing jobs`);
  }

  const jobsData = Array.from({ length: COUNT }, (_, i) => generateJob(i));

  // Insert in batches of 10 to stay within Prisma limits
  const BATCH = 10;
  let created = 0;
  for (let i = 0; i < jobsData.length; i += BATCH) {
    const batch = jobsData.slice(i, i + BATCH);
    await Promise.all(batch.map((data) => prisma.job.create({ data })));
    created += batch.length;
    process.stdout.write(`   ✓ ${created}/${COUNT} jobs created\r`);
  }

  console.log(`\n\n✅  Done! ${COUNT} jobs seeded successfully.`);

  // Print a summary of what was created
  const byCategory = {};
  jobsData.forEach((j) => {
    byCategory[j.category] = (byCategory[j.category] || 0) + 1;
  });
  console.log("\n📊  Jobs by category:");
  Object.entries(byCategory).sort((a, b) => b[1] - a[1]).forEach(([cat, count]) => {
    console.log(`   ${cat.padEnd(20)} ${count}`);
  });

  const quickMoney = jobsData.filter((j) => {
    const diff = (new Date(j.startTime) - new Date()) / 3_600_000;
    return diff >= 0 && diff <= 4 && j.payAmount >= 15;
  }).length;
  const startingSoon = jobsData.filter((j) => {
    const diff = (new Date(j.startTime) - new Date()) / 3_600_000;
    return diff >= 0 && diff <= 48;
  }).length;

  console.log(`\n⚡  Quick Money (≤4h, ≥$15/hr): ${quickMoney} jobs`);
  console.log(`🕐  Starting Soon (≤48h):        ${startingSoon} jobs\n`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
