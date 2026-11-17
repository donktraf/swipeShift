// prisma/seed.js
require("dotenv").config();

const { PrismaClient } = require("@prisma/client");
const { PrismaPg } = require("@prisma/adapter-pg");
const bcrypt = require("bcrypt");

const adapter = new PrismaPg({ connectionString: process.env.DATABASE_URL });
const prisma = new PrismaClient({ adapter });

const now    = new Date();
const in2h   = (h = 2) => new Date(now.getTime() + h * 3_600_000);
const inDays = (d = 1) => new Date(now.getTime() + d * 86_400_000);

function shift(date, start, end, hours, rate) {
  const pay = hours * rate;
  return { date, timeRange: `${start}–${end}`, duration: `${hours} hours`, totalPay: `$${pay} total` };
}

// Employer-User anlegen + zugehöriges Employer-Profil
async function createEmployer({ email, firstName, lastName, location, lat, lng, companyName, companySize, industry }) {
  const pw = await bcrypt.hash("Passwort1", 12);
  const user = await prisma.user.create({
    data: {
      email,
      passwordHash: pw,
      firstName,
      lastName,
      role: "employer",
      emailVerifiedAt: new Date(),
      onboarding: "complete",
      location,
      lat,
      lng,
      employer: {
        create: { companyName, companySize, industry },
      },
    },
    select: { id: true, email: true },
  });
  return user;
}

// Worker-User anlegen
async function createWorker({ email, firstName, lastName, location, lat, lng }) {
  const pw = await bcrypt.hash("Passwort1", 12);
  return prisma.user.create({
    data: {
      email,
      passwordHash: pw,
      firstName,
      lastName,
      role: "worker",
      emailVerifiedAt: new Date(),
      onboarding: "complete",
      location,
      lat,
      lng,
    },
    select: { id: true, email: true },
  });
}

async function main() {
  console.log("🌱 Seeding database...\n");

  // ─── Alte Daten löschen ───────────────────────
  await prisma.message.deleteMany();
  await prisma.conversation.deleteMany();
  await prisma.apply.deleteMany();
  await prisma.skip.deleteMany();
  await prisma.save.deleteMany();
  await prisma.job.deleteMany();
  await prisma.user.deleteMany({ where: { email: { endsWith: "@swipeshift.test" } } });

  // ─── Employers ───────────────────────────────
  const emp1 = await createEmployer({
    email: "eventpro@swipeshift.test",
    firstName: "Maria", lastName: "Hoffmann",
    location: "Stuttgart", lat: 48.7758, lng: 9.1829,
    companyName: "EventPro GmbH", companySize: "11-50", industry: "Events & Entertainment",
  });

  const emp2 = await createEmployer({
    email: "logispeed@swipeshift.test",
    firstName: "Klaus", lastName: "Berger",
    location: "Stuttgart", lat: 48.7393, lng: 9.1598,
    companyName: "LogiSpeed GmbH", companySize: "51-200", industry: "Logistics & Warehouse",
  });

  const emp3 = await createEmployer({
    email: "retailgroup@swipeshift.test",
    firstName: "Sandra", lastName: "Koch",
    location: "Hamburg", lat: 53.5753, lng: 10.0153,
    companyName: "RetailGroup AG", companySize: "201-500", industry: "Retail & Customer Service",
  });

  const emp4 = await createEmployer({
    email: "brewco@swipeshift.test",
    firstName: "Jonas", lastName: "Meier",
    location: "München", lat: 48.1476, lng: 11.5715,
    companyName: "Brew & Co.", companySize: "1-10", industry: "Hospitality",
  });

  const emp5 = await createEmployer({
    email: "cleanpro@swipeshift.test",
    firstName: "Ayse", lastName: "Yilmaz",
    location: "Berlin", lat: 52.5236, lng: 13.4115,
    companyName: "CleanPro Services", companySize: "11-50", industry: "Cleaning",
  });

  console.log("✅ Employers created");

  // ─── Workers ─────────────────────────────────
  await createWorker({
    email: "worker1@swipeshift.test",
    firstName: "Kevin", lastName: "Owusu",
    location: "Stuttgart", lat: 48.7758, lng: 9.1829,
  });

  await createWorker({
    email: "worker2@swipeshift.test",
    firstName: "Lisa", lastName: "Müller",
    location: "Hamburg", lat: 53.5500, lng: 10.0000,
  });

  console.log("✅ Workers created\n");

  // ─── Jobs ────────────────────────────────────
  const jobs = [

    // ── EventPro GmbH ──────────────────────────
    {
      employerId: emp1.id,
      title: "Event Staff",
      company: "EventPro GmbH",
      location: "Stuttgart",
      lat: 48.7758, lng: 9.1829,
      payText: "$15 / hr", payAmount: 15,
      startTime: in2h(3), endTime: in2h(8),
      shiftText: "Today, 18:00–23:00", duration: "5 hours",
      shortInfo: "Gästeempfang, Aufbau und Betreuung bei einem Abend-Event.",
      jobDescription: "Wir suchen freundliche Event-Mitarbeiter für unser Abend-Event im Herzen von Stuttgart. Du begrüßt Gäste, unterstützt beim Aufbau und sorgst für einen reibungslosen Abend.",
      tasks: ["Gäste empfangen & registrieren", "Aufbau und Abbau unterstützen", "Getränke & Snacks verteilen", "Auf Fragen der Gäste eingehen"],
      openSpots: 4,
      tags: ["Flexible", "Same-day pay", "No experience"],
      logoEmoji: "🎪", category: "Events",
      shifts: [
        shift("Mon, May 5", "18:00", "23:00", 5, 15),
        shift("Tue, May 6", "19:00", "23:00", 4, 15),
        shift("Fri, May 9", "18:00", "00:00", 6, 15),
      ],
      dressCode: "Smart Casual (dunkle Hose, weißes Hemd)",
      languages: ["Deutsch", "Englisch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Freelance",
      companyRating: 4.6, replyTime: "Usually replies within 2 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp1.id,
      title: "Bartender",
      company: "EventPro GmbH",
      location: "Stuttgart-Mitte",
      lat: 48.7784, lng: 9.1800,
      payText: "$18 / hr", payAmount: 18,
      startTime: in2h(5), endTime: in2h(11),
      shiftText: "Today, 20:00–02:00", duration: "6 hours",
      shortInfo: "Cocktails & Drinks mixen bei einem Club-Event.",
      jobDescription: "Du arbeitest als Bartender bei einem exklusiven Club-Event. Cocktail-Kenntnisse sind von Vorteil, wir zeigen dir aber alles Nötige.",
      tasks: ["Cocktails & Longdrinks mixen", "Kasse führen", "Bar sauber halten", "Gäste beraten & unterhalten"],
      openSpots: 2,
      tags: ["Night shift", "Tips included", "Fast-paced"],
      logoEmoji: "🍸", category: "Hospitality",
      shifts: [
        shift("Mon, May 5", "20:00", "02:00", 6, 18),
        shift("Fri, May 9", "21:00", "04:00", 7, 18),
        shift("Sat, May 10", "20:00", "03:00", 7, 18),
      ],
      dressCode: "Schwarze Kleidung, Schürze wird gestellt",
      languages: ["Deutsch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Freelance",
      companyRating: 4.6, replyTime: "Usually replies within 2 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp1.id,
      title: "Promoter / Brand Ambassador",
      company: "EventPro GmbH",
      location: "Stuttgart Königstraße",
      lat: 48.7782, lng: 9.1770,
      payText: "$14 / hr", payAmount: 14,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 4 * 3_600_000),
      shiftText: "Mon, 10:00–14:00", duration: "4 hours",
      shortInfo: "Produkte auf der Einkaufsstraße präsentieren und Passanten ansprechen.",
      jobDescription: "Als Brand Ambassador repräsentierst du eine bekannte Getränkemarke auf der Königstraße. Du sprichst Passanten an, verteilst Proben und erklärst das Produkt.",
      tasks: ["Passanten ansprechen & beraten", "Produktproben verteilen", "Feedback-Formulare ausfüllen", "Stand aufbauen & abbauen"],
      openSpots: 3,
      tags: ["Outdoor", "Customer-facing", "Friendly team"],
      logoEmoji: "📢", category: "Customer Service",
      shifts: [
        shift("Mon, May 5", "10:00", "14:00", 4, 14),
        shift("Tue, May 6", "11:00", "15:00", 4, 14),
        shift("Wed, May 7", "10:00", "14:00", 4, 14),
        shift("Thu, May 8", "11:00", "15:00", 4, 14),
        shift("Fri, May 9", "10:00", "14:00", 4, 14),
      ],
      dressCode: "T-Shirt der Marke wird gestellt",
      languages: ["Deutsch", "Englisch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 16, paymentMethod: "Weekly", contractType: "Mini-Job",
      companyRating: 4.6, replyTime: "Usually replies within 2 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp1.id,
      title: "Office Support",
      company: "EventPro GmbH",
      location: "Stuttgart-Mitte",
      lat: 48.7758, lng: 9.1829,
      payText: "$20 / hr", payAmount: 20,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 4 * 3_600_000),
      shiftText: "Mon, 09:00–13:00", duration: "4 hours",
      shortInfo: "Büroalltag unterstützen: E-Mails, Termine, Dokumente.",
      jobDescription: "Unterstützung unserer Eventplanung im Büro. Du hilfst bei der Koordination, bearbeitest Anfragen und pflegst unsere Kundendatenbank.",
      tasks: ["E-Mails beantworten & weiterleiten", "Termine koordinieren", "Angebote erstellen", "Kundendaten pflegen"],
      openSpots: 1,
      tags: ["Part-time", "Flexible", "High pay"],
      logoEmoji: "💻", category: "Office",
      shifts: [
        shift("Mon, May 5", "09:00", "13:00", 4, 20),
        shift("Wed, May 7", "09:00", "13:00", 4, 20),
        shift("Fri, May 9", "09:00", "13:00", 4, 20),
      ],
      dressCode: "Business Casual",
      languages: ["Deutsch", "Englisch"],
      experienceLevel: "1+ Jahr bevorzugt",
      minAge: 18, paymentMethod: "Weekly", contractType: "Freelance",
      companyRating: 4.6, replyTime: "Usually replies within 2 hours",
      isVerified: true, status: "published",
    },

    // ── LogiSpeed GmbH ──────────────────────────
    {
      employerId: emp2.id,
      title: "Warehouse Packer",
      company: "LogiSpeed GmbH",
      location: "Stuttgart-Vaihingen",
      lat: 48.7393, lng: 9.1598,
      payText: "$19 / hr", payAmount: 19,
      startTime: in2h(4), endTime: in2h(8),
      shiftText: "Today, 20:00–00:00", duration: "4 hours",
      shortInfo: "Pakete packen und etikettieren in einem Logistikzentrum.",
      jobDescription: "Als Lagermitarbeiter packst und etikettierst du Sendungen in unserem modernen Logistikzentrum. Sicherheitsschuhe sind Pflicht.",
      tasks: ["Pakete packen & versiegeln", "Versandetiketten aufkleben", "Ware scannen & einbuchen", "Lager ordentlich halten"],
      openSpots: 6,
      tags: ["Night shift", "Physical", "Boots required", "Same-day pay"],
      logoEmoji: "📦", category: "Logistics",
      shifts: [
        shift("Mon, May 5", "20:00", "00:00", 4, 19),
        shift("Tue, May 6", "20:00", "00:00", 4, 19),
        shift("Wed, May 7", "20:00", "00:00", 4, 19),
        shift("Thu, May 8", "20:00", "00:00", 4, 19),
        shift("Fri, May 9", "20:00", "00:00", 4, 19),
      ],
      dressCode: "Sicherheitsschuhe (Pflicht), bequeme Kleidung",
      languages: ["Deutsch oder Englisch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Temporary",
      companyRating: 3.9, replyTime: "Antwortet meist innerhalb von 30 Minuten",
      isVerified: false, status: "published",
    },

    {
      employerId: emp2.id,
      title: "LKW-Entlader",
      company: "LogiSpeed GmbH",
      location: "Stuttgart-Vaihingen",
      lat: 48.7393, lng: 9.1598,
      payText: "$21 / hr", payAmount: 21,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 5 * 3_600_000),
      shiftText: "Mon, 06:00–11:00", duration: "5 hours",
      shortInfo: "LKW entladen und Waren ins Lager einräumen.",
      jobDescription: "Früh aufstehen lohnt sich! Als LKW-Entlader startest du deinen Tag früh und hilfst dabei, täglich eingehende Waren zu sortieren und ins Lager einzuräumen.",
      tasks: ["LKW entladen", "Pakete sortieren", "Waren ins Regal einräumen", "Lieferscheine kontrollieren"],
      openSpots: 4,
      tags: ["Early morning", "Physical", "High pay"],
      logoEmoji: "🚚", category: "Logistics",
      shifts: [
        shift("Mon, May 5", "06:00", "11:00", 5, 21),
        shift("Wed, May 7", "06:00", "11:00", 5, 21),
        shift("Fri, May 9", "06:00", "11:00", 5, 21),
        shift("Sat, May 10", "07:00", "12:00", 5, 21),
      ],
      dressCode: "Sicherheitsschuhe und Warnweste (wird gestellt)",
      languages: ["Deutsch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Temporary",
      companyRating: 3.9, replyTime: "Antwortet meist innerhalb von 30 Minuten",
      isVerified: false, status: "published",
    },

    {
      employerId: emp2.id,
      title: "Staplerfahrer",
      company: "LogiSpeed GmbH",
      location: "München-Nord",
      lat: 48.1700, lng: 11.5600,
      payText: "$24 / hr", payAmount: 24,
      startTime: inDays(3), endTime: new Date(inDays(3).getTime() + 8 * 3_600_000),
      shiftText: "Wed, 07:00–15:00", duration: "8 hours",
      shortInfo: "Gabelstapler bedienen und Waren im Hochregallager transportieren.",
      jobDescription: "Für unser Münchner Depot suchen wir erfahrene Staplerfahrer mit gültigem Staplerschein. Sehr gute Bezahlung, sicheres Umfeld.",
      tasks: ["Waren mit Gabelstapler transportieren", "Hochregal be- & entladen", "Lieferscheine prüfen", "Sicherheitsregeln einhalten"],
      openSpots: 2,
      tags: ["High pay", "Forklift license required", "Experienced"],
      logoEmoji: "🏗️", category: "Logistics",
      shifts: [
        shift("Wed, May 7", "07:00", "15:00", 8, 24),
        shift("Thu, May 8", "07:00", "15:00", 8, 24),
        shift("Fri, May 9", "07:00", "15:00", 8, 24),
      ],
      dressCode: "Sicherheitskleidung wird gestellt",
      languages: ["Deutsch"],
      experienceLevel: "1+ Jahr bevorzugt",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Temporary",
      companyRating: 3.9, replyTime: "Antwortet meist innerhalb von 30 Minuten",
      isVerified: false, status: "published",
    },

    // ── RetailGroup AG ──────────────────────────
    {
      employerId: emp3.id,
      title: "Retail Assistant",
      company: "RetailGroup AG",
      location: "Hamburg-Altona",
      lat: 53.5500, lng: 9.9350,
      payText: "$13 / hr", payAmount: 13,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 8 * 3_600_000),
      shiftText: "Mon, 10:00–18:00", duration: "8 hours",
      shortInfo: "Kunden beraten und Kasse bedienen im Flagship-Store.",
      jobDescription: "Du unterstützt unser Team im Flagship-Store und sorgst für ein tolles Einkaufserlebnis. Kassenerfahrung ist willkommen aber kein Muss.",
      tasks: ["Kunden auf der Fläche beraten", "Kassenabwicklung", "Regale auffüllen", "Inventur unterstützen"],
      openSpots: 3,
      tags: ["Weekend", "Customer-facing", "Tips included"],
      logoEmoji: "🛍️", category: "Retail",
      shifts: [
        shift("Mon, May 5", "10:00", "14:00", 4, 13),
        shift("Mon, May 5", "14:00", "18:00", 4, 13),
        shift("Sat, May 10", "10:00", "18:00", 8, 13),
        shift("Sun, May 11", "12:00", "18:00", 6, 13),
      ],
      dressCode: "Eigene Kleidung (modisch, sauber)",
      languages: ["Deutsch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 16, paymentMethod: "Weekly", contractType: "Mini-Job",
      companyRating: 4.2, replyTime: "Usually replies within 4 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp3.id,
      title: "Kassenkraft",
      company: "RetailGroup AG",
      location: "Hamburg-Innenstadt",
      lat: 53.5503, lng: 10.0006,
      payText: "$12 / hr", payAmount: 12,
      startTime: in2h(2), endTime: in2h(7),
      shiftText: "Today, 13:00–18:00", duration: "5 hours",
      shortInfo: "Kassenabwicklung und Kundenservice im Supermarkt.",
      jobDescription: "Wir suchen kurzfristig Unterstützung an unseren Kassen. Du kassierst, berätst und sorgst für einen reibungslosen Ablauf.",
      tasks: ["Kasse bedienen", "Rabatte & Gutscheine einlösen", "Kunden freundlich begrüßen", "Kassensturz am Ende der Schicht"],
      openSpots: 5,
      tags: ["Same-day pay", "No experience", "Part-time"],
      logoEmoji: "🏪", category: "Retail",
      shifts: [
        shift("Today", "13:00", "18:00", 5, 12),
        shift("Mon, May 5", "08:00", "13:00", 5, 12),
        shift("Tue, May 6", "13:00", "18:00", 5, 12),
        shift("Wed, May 7", "08:00", "13:00", 5, 12),
      ],
      dressCode: "Kassenkleidung wird gestellt",
      languages: ["Deutsch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 16, paymentMethod: "Same-day Pay", contractType: "Mini-Job",
      companyRating: 4.2, replyTime: "Usually replies within 4 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp3.id,
      title: "Customer Service Agent",
      company: "RetailGroup AG",
      location: "Remote (Hamburg)",
      lat: 53.5753, lng: 10.0153,
      payText: "$17 / hr", payAmount: 17,
      startTime: inDays(2), endTime: new Date(inDays(2).getTime() + 6 * 3_600_000),
      shiftText: "Tue, 09:00–15:00", duration: "6 hours",
      shortInfo: "Kundenanfragen per Telefon und Chat beantworten.",
      jobDescription: "Du bearbeitest Kundenanfragen und Reklamationen für unseren Online-Shop. Alles läuft remote — Laptop und Headset werden gestellt.",
      tasks: ["Telefon- & Chat-Support", "Beschwerden bearbeiten", "Retouren koordinieren", "CRM-Daten pflegen"],
      openSpots: 4,
      tags: ["Remote", "Phone", "CRM experience a plus"],
      logoEmoji: "🎧", category: "Customer Service",
      shifts: [
        shift("Tue, May 6", "09:00", "15:00", 6, 17),
        shift("Wed, May 7", "09:00", "15:00", 6, 17),
        shift("Thu, May 8", "09:00", "15:00", 6, 17),
        shift("Fri, May 9", "09:00", "15:00", 6, 17),
      ],
      dressCode: "Kein Dresscode (Remote)",
      languages: ["Deutsch", "Englisch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 18, paymentMethod: "Weekly", contractType: "Temporary",
      companyRating: 4.2, replyTime: "Usually replies within 4 hours",
      isVerified: true, status: "published",
    },

    // ── Brew & Co. ──────────────────────────────
    {
      employerId: emp4.id,
      title: "Barista",
      company: "Brew & Co.",
      location: "München-Maxvorstadt",
      lat: 48.1476, lng: 11.5715,
      payText: "$14 / hr", payAmount: 14,
      startTime: in2h(3), endTime: in2h(10),
      shiftText: "Today, 07:00–14:00", duration: "7 hours",
      shortInfo: "Kaffeespezialitäten zubereiten und Gäste im Morning Rush bedienen.",
      jobDescription: "Du bist das Herzstück unseres Morgens! Als Barista bereitest du Kaffeespezialitäten zu und sorgst dafür, dass unsere Gäste perfekt in den Tag starten.",
      tasks: ["Kaffee- & Teegetränke zubereiten", "Kasse bedienen", "Maschinen reinigen", "Gäste freundlich empfangen"],
      openSpots: 2,
      tags: ["Morning", "Customer-facing", "Tips included"],
      logoEmoji: "☕", category: "Hospitality",
      shifts: [
        shift("Mon, May 5", "07:00", "14:00", 7, 14),
        shift("Tue, May 6", "07:00", "11:00", 4, 14),
        shift("Wed, May 7", "07:00", "14:00", 7, 14),
        shift("Thu, May 8", "07:00", "11:00", 4, 14),
        shift("Fri, May 9", "07:00", "14:00", 7, 14),
        shift("Sat, May 10", "08:00", "15:00", 7, 14),
      ],
      dressCode: "Schürze wird gestellt, dunkle Kleidung bevorzugt",
      languages: ["Deutsch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 16, paymentMethod: "In-app Wallet", contractType: "Mini-Job",
      companyRating: 4.5, replyTime: "Usually replies within 3 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp4.id,
      title: "Kellner / Servicekraft",
      company: "Brew & Co.",
      location: "München-Schwabing",
      lat: 48.1600, lng: 11.5820,
      payText: "$16 / hr", payAmount: 16,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 6 * 3_600_000),
      shiftText: "Mon, 17:00–23:00", duration: "6 hours",
      shortInfo: "Gäste im Restaurant betreuen und Bestellungen aufnehmen.",
      jobDescription: "Du betreust unsere Gäste im Abendbereich, nimmst Bestellungen auf und sorgst für einen reibungslosen Service.",
      tasks: ["Bestellungen aufnehmen", "Speisen & Getränke servieren", "Tische abräumen & eindecken", "Abrechnung"],
      openSpots: 3,
      tags: ["Evening", "Tips included", "Friendly team"],
      logoEmoji: "🍽️", category: "Hospitality",
      shifts: [
        shift("Mon, May 5", "17:00", "23:00", 6, 16),
        shift("Tue, May 6", "17:00", "23:00", 6, 16),
        shift("Thu, May 8", "17:00", "23:00", 6, 16),
        shift("Fri, May 9", "18:00", "00:00", 6, 16),
        shift("Sat, May 10", "17:00", "01:00", 8, 16),
      ],
      dressCode: "Schwarze Kleidung (sauber und gebügelt)",
      languages: ["Deutsch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 18, paymentMethod: "In-app Wallet", contractType: "Mini-Job",
      companyRating: 4.5, replyTime: "Usually replies within 3 hours",
      isVerified: true, status: "published",
    },

    {
      employerId: emp4.id,
      title: "Küchenhilfe",
      company: "Brew & Co.",
      location: "München-Maxvorstadt",
      lat: 48.1476, lng: 11.5715,
      payText: "$13 / hr", payAmount: 13,
      startTime: inDays(3), endTime: new Date(inDays(3).getTime() + 4 * 3_600_000),
      shiftText: "Wed, 11:00–15:00", duration: "4 hours",
      shortInfo: "Küchenteam beim Mittagsservice unterstützen.",
      jobDescription: "Du unterstützt unser Küchenteam beim täglichen Mittagsservice: Zutaten vorbereiten, Gerichte anrichten und Küche sauber halten.",
      tasks: ["Zutaten schneiden & vorbereiten", "Gerichte anrichten", "Küchengeräte reinigen", "Abfälle entsorgen"],
      openSpots: 2,
      tags: ["Part-time", "No experience", "Friendly team"],
      logoEmoji: "🍳", category: "Hospitality",
      shifts: [
        shift("Wed, May 7", "11:00", "15:00", 4, 13),
        shift("Thu, May 8", "11:00", "15:00", 4, 13),
        shift("Fri, May 9", "11:00", "15:00", 4, 13),
      ],
      dressCode: "Küchenkleidung wird gestellt",
      languages: ["Deutsch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 16, paymentMethod: "Weekly", contractType: "Mini-Job",
      companyRating: 4.5, replyTime: "Usually replies within 3 hours",
      isVerified: true, status: "published",
    },

    // ── CleanPro Services ────────────────────────
    {
      employerId: emp5.id,
      title: "Reinigungskraft",
      company: "CleanPro Services",
      location: "Berlin-Mitte",
      lat: 52.5236, lng: 13.4115,
      payText: "$16 / hr", payAmount: 16,
      startTime: in2h(5), endTime: in2h(8),
      shiftText: "Today, 22:00–01:00", duration: "3 hours",
      shortInfo: "Veranstaltungsraum nach Event reinigen.",
      jobDescription: "Reinigung eines großen Veranstaltungsraums nach einem Abend-Event. Material und Hilfsmittel werden gestellt.",
      tasks: ["Böden fegen & wischen", "Müll entsorgen", "Sanitäranlagen reinigen", "Stühle & Tische abbauen"],
      openSpots: 6,
      tags: ["Late night", "No experience", "Same-day pay"],
      logoEmoji: "🧹", category: "Cleaning",
      shifts: [
        shift("Mon, May 5", "22:00", "01:00", 3, 16),
        shift("Tue, May 6", "22:00", "01:00", 3, 16),
        shift("Wed, May 7", "22:00", "01:00", 3, 16),
      ],
      dressCode: "Bequeme Arbeitskleidung",
      languages: ["Deutsch oder Englisch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 18, paymentMethod: "Same-day Pay", contractType: "Mini-Job",
      companyRating: 3.7, replyTime: "Usually replies within 2 hours",
      isVerified: false, status: "published",
    },

    {
      employerId: emp5.id,
      title: "Büroreinigung (Frühdienst)",
      company: "CleanPro Services",
      location: "Berlin-Charlottenburg",
      lat: 52.5167, lng: 13.3000,
      payText: "$15 / hr", payAmount: 15,
      startTime: inDays(1), endTime: new Date(inDays(1).getTime() + 3 * 3_600_000),
      shiftText: "Mon, 06:00–09:00", duration: "3 hours",
      shortInfo: "Büro vor Arbeitsbeginn reinigen.",
      jobDescription: "Du reinigst täglich ein modernes Bürogebäude in Berlin-Charlottenburg vor Arbeitsbeginn der Mitarbeiter.",
      tasks: ["Böden saugen & wischen", "Müllkörbe leeren", "Sanitäranlagen reinigen", "Küche & Gemeinschaftsräume reinigen"],
      openSpots: 2,
      tags: ["Early morning", "Recurring", "Stable income"],
      logoEmoji: "🏢", category: "Cleaning",
      shifts: [
        shift("Mon, May 5", "06:00", "09:00", 3, 15),
        shift("Tue, May 6", "06:00", "09:00", 3, 15),
        shift("Wed, May 7", "06:00", "09:00", 3, 15),
        shift("Thu, May 8", "06:00", "09:00", 3, 15),
        shift("Fri, May 9", "06:00", "09:00", 3, 15),
      ],
      dressCode: "Bequeme Kleidung",
      languages: ["Deutsch"],
      experienceLevel: "Keine Erfahrung nötig",
      minAge: 18, paymentMethod: "Weekly", contractType: "Mini-Job",
      companyRating: 3.7, replyTime: "Usually replies within 2 hours",
      isVerified: false, status: "published",
    },

    {
      employerId: emp5.id,
      title: "Security Guard",
      company: "CleanPro Services",
      location: "Berlin-Prenzlauer Berg",
      lat: 52.5350, lng: 13.4200,
      payText: "$20 / hr", payAmount: 20,
      startTime: inDays(2), endTime: new Date(inDays(2).getTime() + 8 * 3_600_000),
      shiftText: "Tue, 22:00–06:00", duration: "8 hours",
      shortInfo: "Gebäude und Gelände in der Nacht absichern.",
      jobDescription: "Als Sicherheitsmitarbeiter überwachst du ein Gebäude in der Nacht, kontrollierst den Zutritt und meldest Unregelmäßigkeiten.",
      tasks: ["Einlasskontrolle", "Rundgänge auf dem Gelände", "Überwachung des Kameramonitors", "Ereignisse im Schichtbuch dokumentieren"],
      openSpots: 2,
      tags: ["Night", "High pay", "Uniform required"],
      logoEmoji: "🛡️", category: "Events",
      shifts: [
        shift("Tue, May 6", "22:00", "06:00", 8, 20),
        shift("Thu, May 8", "22:00", "06:00", 8, 20),
        shift("Sat, May 10", "22:00", "06:00", 8, 20),
      ],
      dressCode: "Schwarze Kleidung (Uniform wird gestellt)",
      languages: ["Deutsch"],
      experienceLevel: "3–12 Monate bevorzugt",
      minAge: 21, paymentMethod: "Weekly", contractType: "Freelance",
      companyRating: 3.7, replyTime: "Usually replies within 2 hours",
      isVerified: false, status: "published",
    },
  ];

  for (const job of jobs) {
    const created = await prisma.job.create({ data: { ...job, shifts: job.shifts } });
    console.log(`  ✅ ${created.company.padEnd(20)} — ${created.title} (${created.location})`);
  }

  console.log(`\n🎉 Fertig! ${jobs.length} Jobs, 5 Employers, 2 Workers angelegt.\n`);
  console.log("📋 Test-Zugangsdaten (Passwort überall: Passwort1):");
  console.log("  Employer — EventPro:     eventpro@swipeshift.test");
  console.log("  Employer — LogiSpeed:    logispeed@swipeshift.test");
  console.log("  Employer — RetailGroup:  retailgroup@swipeshift.test");
  console.log("  Employer — Brew & Co.:   brewco@swipeshift.test");
  console.log("  Employer — CleanPro:     cleanpro@swipeshift.test");
  console.log("  Worker   — Stuttgart:    worker1@swipeshift.test");
  console.log("  Worker   — Hamburg:      worker2@swipeshift.test");
}

main()
  .catch((e) => { console.error(e); process.exit(1); })
  .finally(() => prisma.$disconnect());
