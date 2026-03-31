// prisma/seed.js
// Füllt die Datenbank mit den Job-Testdaten aus db.js
require("dotenv").config();

const { PrismaClient } = require("@prisma/client");
const { PrismaPg } = require("@prisma/adapter-pg");

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });

const now = new Date();
const inThreeHours = new Date(now.getTime() + 3  * 60 * 60 * 1000);
const inFourHours  = new Date(now.getTime() + 4  * 60 * 60 * 1000);
const tomorrow     = new Date(now.getTime() + 24 * 60 * 60 * 1000);

const jobData = [
  {
    title: "Event Staff",
    company: "Berlin Events GmbH",
    location: "Stuttgart",
    lat: 48.7758, lng: 9.1829,
    payText: "€15 / hour", payAmount: 15,
    startTime: inThreeHours, endTime: new Date(inThreeHours.getTime() + 5 * 3600_000),
    shiftText: "Today, 18:00–23:00", duration: "5 Stunden",
    shortInfo: "Help with setup, registration and guest support at an evening event.",
    jobDescription: "Wir suchen freundliche und zuverlässige Event-Mitarbeiter für unser Abend-Event im Herzen von Stuttgart.",
    tasks: ["Gäste empfangen und registrieren", "Aufbau und Abbau unterstützen", "Getränke & Snacks verteilen", "Auf Fragen der Gäste eingehen"],
    openSpots: 3,
    tags: ["Flexible", "Same-day pay", "No experience"],
    logoEmoji: "🎪", category: "Events",
    shifts: [
      { date: "Mo, 12. Mai", timeRange: "18:00–23:00", duration: "5 Stunden", totalPay: "€75 gesamt" },
      { date: "Di, 13. Mai", timeRange: "19:00–23:00", duration: "4 Stunden", totalPay: "€60 gesamt" },
      { date: "Fr, 16. Mai", timeRange: "18:00–00:00", duration: "6 Stunden", totalPay: "€90 gesamt" },
    ],
    dressCode: "Smart Casual (dunkle Hose, weißes Hemd)",
    languages: ["Deutsch", "Englisch"],
    experienceLevel: "Keine Erfahrung nötig",
    minAge: 18, paymentMethod: "Same-day Pay", contractType: "Freelance",
    companyRating: 4.6, replyTime: "Antwortet meist innerhalb von 2 Stunden",
    isVerified: true, status: "published",
  },
  {
    title: "Retail Assistant",
    company: "Urban Fashion Store",
    location: "Hamburg",
    lat: 53.5753, lng: 10.0153,
    payText: "€13 / hour", payAmount: 13,
    startTime: tomorrow, endTime: new Date(tomorrow.getTime() + 8 * 3600_000),
    shiftText: "Sat, 10:00–18:00", duration: "8 Stunden",
    shortInfo: "Support customers on the floor and help with inventory.",
    jobDescription: "Du unterstützt unser Team im Flagship-Store und sorgst für ein tolles Einkaufserlebnis.",
    tasks: ["Kunden auf der Fläche beraten", "Kassenabwicklung", "Regale auffüllen und Ordnung halten", "Inventur unterstützen"],
    openSpots: 2,
    tags: ["Weekend", "Customer-facing"],
    logoEmoji: "🛍️", category: "Retail",
    shifts: [
      { date: "Sa, 10. Mai", timeRange: "10:00–14:00", duration: "4 Stunden", totalPay: "€52 gesamt" },
      { date: "So, 11. Mai", timeRange: "12:00–18:00", duration: "6 Stunden", totalPay: "€78 gesamt" },
    ],
    dressCode: "Eigene Kleidung (modisch, sauber)",
    languages: ["Deutsch"],
    experienceLevel: "3–12 Monate bevorzugt",
    minAge: 16, paymentMethod: "Weekly", contractType: "Mini-Job",
    companyRating: 4.2, replyTime: "Antwortet meist innerhalb von 4 Stunden",
    isVerified: true, status: "published",
  },
  {
    title: "Office Support",
    company: "Startup Hub",
    location: "Berlin",
    lat: 52.52, lng: 13.405,
    payText: "€20 / hour", payAmount: 20,
    startTime: tomorrow, endTime: new Date(tomorrow.getTime() + 4 * 3600_000),
    shiftText: "Mon–Wed, 09:00–13:00", duration: "4 Stunden / Tag",
    shortInfo: "Light admin tasks, email replies and calendar updates.",
    jobDescription: "Wir suchen eine zuverlässige Unterstützung für leichte administrative Aufgaben in unserem schnell wachsenden Startup.",
    tasks: ["E-Mails beantworten und weiterleiten", "Kalender und Termine koordinieren", "Dokumente erstellen und bearbeiten", "Daten in Spreadsheets pflegen"],
    openSpots: 1,
    tags: ["Remote", "Part-time", "Flexible"],
    logoEmoji: "💻", category: "Office",
    shifts: [],
    dressCode: "Kein Dresscode (Remote)",
    languages: ["Deutsch", "Englisch"],
    experienceLevel: "1+ Jahr bevorzugt",
    minAge: 18, paymentMethod: "Weekly", contractType: "Freelance",
    companyRating: 4.8, replyTime: "Antwortet meist innerhalb von 1 Stunde",
    isVerified: true, status: "published",
  },
  {
    title: "Warehouse Packer",
    company: "LogiSpeed GmbH",
    location: "Stuttgart-Vaihingen",
    lat: 48.7393, lng: 9.1598,
    payText: "€19 / hour", payAmount: 19,
    startTime: inFourHours, endTime: new Date(inFourHours.getTime() + 4 * 3600_000),
    shiftText: "Today, 20:00–00:00", duration: "4 Stunden",
    shortInfo: "Pack and label outgoing shipments at a busy logistics hub.",
    jobDescription: "Als Lagermitarbeiter packst und beschriftest du ausgehende Sendungen in unserem Logistikzentrum.",
    tasks: ["Pakete packen und versiegeln", "Versandetiketten drucken und aufkleben", "Ware scannen und im System erfassen", "Lager sauber und ordentlich halten"],
    openSpots: 5,
    tags: ["Night shift", "Physical", "Boots required"],
    logoEmoji: "📦", category: "Logistics",
    shifts: [],
    dressCode: "Sicherheitsschuhe (Pflicht), bequeme Kleidung",
    languages: ["Deutsch oder Englisch"],
    experienceLevel: "Keine Erfahrung nötig",
    minAge: 18, paymentMethod: "Same-day Pay", contractType: "Temporary",
    companyRating: 3.9, replyTime: "Antwortet meist innerhalb von 30 Minuten",
    isVerified: false, status: "published",
  },
  {
    title: "Barista",
    company: "Brew & Co.",
    location: "Stuttgart-Plieningen",
    lat: 48.7066, lng: 9.2189,
    payText: "€14 / hour", payAmount: 14,
    startTime: inThreeHours, endTime: new Date(inThreeHours.getTime() + 7 * 3600_000),
    shiftText: "Today, 07:00–14:00", duration: "7 Stunden",
    shortInfo: "Prepare coffee and support the morning rush at a busy café.",
    jobDescription: "Du bist das Herzstück unseres Morgens! Als Barista bereitest du Kaffeespezialitäten zu und sorgst dafür, dass unsere Gäste perfekt in den Tag starten.",
    tasks: ["Kaffee- und Teegetränke zubereiten", "Kasse bedienen", "Theke und Maschinen reinigen", "Gäste freundlich empfangen"],
    openSpots: 1,
    tags: ["Morning", "Customer-facing", "Tips included"],
    logoEmoji: "☕", category: "Hospitality",
    shifts: [],
    dressCode: "Schürze wird gestellt, dunkle Kleidung bevorzugt",
    languages: ["Deutsch"],
    experienceLevel: "3–12 Monate bevorzugt",
    minAge: 16, paymentMethod: "In-app Wallet", contractType: "Mini-Job",
    companyRating: 4.5, replyTime: "Antwortet meist innerhalb von 3 Stunden",
    isVerified: true, status: "published",
  },
  {
    title: "Security Guard",
    company: "Safe & Sound GmbH",
    location: "München",
    lat: 48.1351, lng: 11.5820,
    payText: "€18 / hour", payAmount: 18,
    startTime: tomorrow, endTime: new Date(tomorrow.getTime() + 8 * 3600_000),
    shiftText: "Sa, 20:00–04:00", duration: "8 Stunden",
    shortInfo: "Door control and crowd management at a large club event.",
    jobDescription: "Als Sicherheitskraft überwachst du den Eingang, prüfst Ausweise und sorgst für einen reibungslosen Ablauf.",
    tasks: ["Einlasskontrolle", "Ausweisüberprüfung", "Patrouille im Gebäude", "Kommunikation mit Event-Team"],
    openSpots: 4,
    tags: ["Night", "Physical", "Uniform required"],
    logoEmoji: "🛡️", category: "Events",
    shifts: [],
    dressCode: "Schwarze Kleidung (Uniform wird gestellt)",
    languages: ["Deutsch"],
    experienceLevel: "3–12 Monate bevorzugt",
    minAge: 21, paymentMethod: "Same-day Pay", contractType: "Freelance",
    companyRating: 4.1, replyTime: "Antwortet meist innerhalb von 1 Stunde",
    isVerified: true, status: "published",
  },
  {
    title: "Cleaning Staff",
    company: "Glanz & Sauber UG",
    location: "Berlin-Mitte",
    lat: 52.5236, lng: 13.4115,
    payText: "€16 / hour", payAmount: 16,
    startTime: inFourHours, endTime: new Date(inFourHours.getTime() + 3 * 3600_000),
    shiftText: "Today, 22:00–01:00", duration: "3 Stunden",
    shortInfo: "Post-event cleanup at a Berlin venue.",
    jobDescription: "Reinigung eines großen Veranstaltungsraums nach einem Abend-Event. Material und Hilfsmittel werden gestellt.",
    tasks: ["Böden fegen und wischen", "Müll entsorgen", "Sanitäranlagen reinigen", "Stühle und Tische abbauen"],
    openSpots: 6,
    tags: ["Late night", "No experience", "Same-day pay"],
    logoEmoji: "🧹", category: "Cleaning",
    shifts: [],
    dressCode: "Bequeme Arbeitskleidung",
    languages: ["Deutsch oder Englisch"],
    experienceLevel: "Keine Erfahrung nötig",
    minAge: 18, paymentMethod: "Same-day Pay", contractType: "Mini-Job",
    companyRating: 3.7, replyTime: "Antwortet meist innerhalb von 2 Stunden",
    isVerified: false, status: "published",
  },
  {
    title: "Customer Service Agent",
    company: "HelpDesk Solutions",
    location: "Hamburg",
    lat: 53.5500, lng: 10.0000,
    payText: "€17 / hour", payAmount: 17,
    startTime: tomorrow, endTime: new Date(tomorrow.getTime() + 6 * 3600_000),
    shiftText: "Mo, 09:00–15:00", duration: "6 Stunden",
    shortInfo: "Handle inbound customer queries by phone and chat.",
    jobDescription: "Du bearbeitest eingehende Kundenanfragen per Telefon und Chat für einen großen E-Commerce-Kunden.",
    tasks: ["Telefon- und Chat-Support", "Beschwerden bearbeiten", "Retouren koordinieren", "Daten im CRM pflegen"],
    openSpots: 3,
    tags: ["Remote", "Phone", "CRM experience a plus"],
    logoEmoji: "🎧", category: "Customer Service",
    shifts: [],
    dressCode: "Kein Dresscode (Remote)",
    languages: ["Deutsch", "Englisch"],
    experienceLevel: "3–12 Monate bevorzugt",
    minAge: 18, paymentMethod: "Weekly", contractType: "Temporary",
    companyRating: 4.3, replyTime: "Antwortet meist innerhalb von 3 Stunden",
    isVerified: true, status: "published",
  },
];

async function main() {
  console.log("Seeding jobs...");

  // Bestehende Jobs löschen um Duplikate zu vermeiden
  await prisma.job.deleteMany();

  for (const job of jobData) {
    const created = await prisma.job.create({
      data: {
        ...job,
        shifts: job.shifts,
      },
    });
    console.log(`Created: ${created.title} (${created.id})`);
  }

  console.log(`Done. ${jobData.length} jobs seeded.`);
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
