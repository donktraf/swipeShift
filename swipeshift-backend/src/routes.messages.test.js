// src/routes.messages.test.js
// Regressionstest: GET /messages hat fuer Employer ein `include: { worker }` auf Conversation
// gesendet, das es im Schema nicht gibt → PrismaClientValidationError, unbehandelt in
// Express 4 → der gesamte Node-Prozess ist abgestuerzt.
//
// Braucht KEINE Datenbank: DATABASE_URL zeigt auf einen nicht erreichbaren Port. Prisma
// validiert die Abfrage vor dem Verbindungsaufbau — ein Validierungsfehler tritt also vor
// dem (erwarteten) Verbindungsfehler auf. Nur die User-Lookups werden gemockt.

process.env.DATABASE_URL = "postgresql://test:test@127.0.0.1:1/none";

const { test, after } = require("node:test");
const assert = require("node:assert/strict");
const express = require("express");
const { prisma } = require("./prisma.js");
const { signToken } = require("./auth.js");
const messagesRoutes = require("./routes.messages.js");

prisma.user.findUnique = async () => ({ role: "employer", firstName: "E", lastName: "M" });
prisma.user.update = async () => ({});

let findManyError = null;
const originalFindMany = prisma.conversation.findMany.bind(prisma.conversation);
prisma.conversation.findMany = async (args) => {
  try {
    return await originalFindMany(args);
  } catch (err) {
    findManyError = err;
    throw err;
  }
};

const app = express();
app.use(express.json());
app.use("/messages", messagesRoutes);
const server = app.listen(0);
after(() => server.close());

test("GET /messages (Employer): gueltige Prisma-Abfrage + 500 statt Absturz ohne DB", async () => {
  const token = signToken({ id: "employer-1", role: "employer", email: "e@example.com" });
  const res = await fetch(`http://127.0.0.1:${server.address().port}/messages`, {
    headers: { Authorization: `Bearer ${token}` },
    signal: AbortSignal.timeout(15000),
  });

  assert.ok(findManyError, "findMany sollte ohne DB fehlschlagen");
  assert.notEqual(
    findManyError.constructor.name,
    "PrismaClientValidationError",
    `Abfrage ist ungueltig: ${findManyError.message}`
  );
  assert.equal(res.status, 500);
  assert.deepEqual(await res.json(), { error: "Internal server error" });
});
