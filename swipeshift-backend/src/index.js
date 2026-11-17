// src/index.js

const express = require("express");
const cors = require("cors");
require("dotenv").config();

const path = require("path");
const uploadsRoutes = require("./routes.upload.js");


const authRoutes      = require("./routes.auth.js");
const securityRoutes  = require("./routes.security.js");
const settingsRoutes  = require("./routes.settings.js");
const jobsRoutes      = require("./routes.jobs.js");
const meRoutes        = require("./routes.me.js");
const onboardingRoutes = require("./routes.onboarding");
const employerRoutes   = require("./routes.employer");
const workerRoutes     = require("./routes.worker");
const messagesRoutes        = require("./routes.messages");
const companiesRoutes       = require("./routes.companies");
const notificationsRoutes   = require("./routes.notifications");
const safetyRoutes          = require("./routes.safety");

const app = express();

app.use(cors());
app.use(express.json());

// Muss mit uploadDir in routes.upload.js übereinstimmen (Projekt-Root/uploads, nicht src/uploads)
app.use("/uploads", express.static(path.join(__dirname, "..", "uploads")));
app.use("/uploads", uploadsRoutes);

// Healthcheck
app.get("/health", (req, res) => res.json({ ok: true }));

// Use Routes
app.use("/auth",      meRoutes);
app.use("/auth",      authRoutes);
app.use("/auth",      securityRoutes);
app.use("/auth",      settingsRoutes);
app.use("/jobs",      jobsRoutes);
app.use("/onboarding", onboardingRoutes);
app.use("/employer",  employerRoutes);
app.use("/worker",    workerRoutes);
app.use("/messages",       messagesRoutes);
app.use("/companies",      companiesRoutes);
app.use("/notifications",  notificationsRoutes);
app.use("/safety",         safetyRoutes);

const PORT = process.env.PORT || 3000;

app.listen(PORT, () => {
  console.log(`Backend running on http://localhost:` + PORT);
});
// app.listen(PORT, "0.0.0.0", () => {
//   console.log(`Backend running on http://localhost:${PORT}`);
// });