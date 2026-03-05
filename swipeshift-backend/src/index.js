// src/index.js
console.log("#### index.js loaded");

const express = require("express");
const cors = require("cors");
require("dotenv").config();

const path = require("path");
const uploadsRoutes = require("./routes.upload.js");


const authRoutes = require("./routes.auth.js");
const jobsRoutes = require("./routes.jobs.js");
const meRoutes = require("./routes.me.js");
const onboardingRoutes = require("./routes.onboarding");

const app = express();

app.use(cors());
app.use(express.json());

app.use("/uploads", express.static(path.join(__dirname, "uploads")));
app.use("/uploads", uploadsRoutes);

// Healthcheck
app.get("/health", (req, res) => res.json({ ok: true }));

// Use Routes
app.use("/auth", meRoutes);
app.use("/auth", authRoutes);
app.use("/jobs", jobsRoutes);
app.use("/onboarding", onboardingRoutes);

const PORT = process.env.PORT || 3000;

// app.listen(PORT, () => {
//   console.log(`Backend running on http://localhost:` + PORT);
// });
app.listen(PORT, "0.0.0.0", () => {
  console.log(`Backend running on http://localhost:${PORT}`);
});

console.log("#### Server setup finished");

console.log("FISCHER");


