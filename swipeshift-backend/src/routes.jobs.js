// src/routes.jobs.js
const express = require("express");
const { z } = require("zod");
const { jobs, applies, skips, saves } = require("./db");
const { requireAuth } = require("./auth");
const { requireVerifiedEmail } = require("./middlewares/requireVerifiedEmail");

const router = express.Router();

// src/routes.jobs.js

router.get("/", requireAuth, requireVerifiedEmail, (req, res) => {
  console.log("JOBS ROUTE")
  const userId = req.auth.sub;

  // 1) Job-IDs sammeln, die der User bereits applied oder skipped hat
  const appliedIds = new Set();
  for (let i = 0; i < applies.length; i++) {
    const entry = applies[i];
    if (entry.userId === userId) {
      appliedIds.add(entry.jobId);
    }
  }

  const skippedIds = new Set();
  
  for (let i = 0; i < skips.length; i++) {
    const entry = skips[i];
    if (entry.userId === userId) {
      skippedIds.add(entry.jobId);
    }
  }

  console.log("appliedIds", appliedIds);
  console.log("skippedIds", skippedIds);

  console.log("ALL JOB IDS:", jobs.map(j => j.id));
  console.log("SKIPPED IDS:", [...skippedIds]);

  // 2) Jobs entfernen, die der User schon applied oder skipped hat
  const filteredJobs = [];
  for (let i = 0; i < jobs.length; i++) {
    const job = jobs[i];

    const wasApplied = appliedIds.has(job.id);
    const wasSkipped = skippedIds.has(job.id);

    if (!wasApplied && !wasSkipped) {
      filteredJobs.push(job);
    }
  }


  // 4️⃣ OPTIONAL: Location-Filter aus Query lesen (?location=Berlin)
  let qLocation = "";
  if (req.query.location !== undefined && req.query.location !== null) {
    qLocation = String(req.query.location);
  }

  // Leerzeichen entfernen und kleinschreiben
  qLocation = qLocation.trim().toLowerCase();

  // 4) Nach Location filtern (nur wenn Location gesetzt ist)
  let locationFilteredJobs = [];

  if (qLocation === "") {
    // Keine Location angegeben → alle Jobs übernehmen
    for (let i = 0; i < filteredJobs.length; i++) {
      locationFilteredJobs.push(filteredJobs[i]);

    }
  } else {
    // Location angegeben → nur passende Jobs übernehmen
    for (let i = 0; i < filteredJobs.length; i++) {
      const job = filteredJobs[i];

      let jobLocation = "";
      if (job.location !== undefined && job.location !== null) {
        jobLocation = String(job.location).toLowerCase();
      }

      if (jobLocation.includes(qLocation)) {
        locationFilteredJobs.push(job);
      }
    }
  }




  // 5️⃣ Response zurückgeben
  // res.json({
  //   jobs: personalizedJobs,
  //   meta: {
  //     totalJobs: jobs.length,
  //     afterInteractionFilter: filteredJobs.length,
  //     afterLocationFilter: personalizedJobs.length,
  //     locationQuery: qLocation || null,
  //   },
  // });
  res.json({ jobs: locationFilteredJobs });

});





const actionSchema = z.object({

  jobId: z.string().min(1),
});

// Helper
function addInteraction(list, userId, jobId) {

  list.push({ userId, jobId, createdAt: new Date().toISOString() });
}

router.post("/:id/apply", requireAuth, requireVerifiedEmail,(req, res) => {
  const jobId = req.params.id;
  const userId = req.auth.sub;

  addInteraction(applies, userId, jobId);

  res.json({ ok: true });
});

router.post("/:id/skip", requireAuth, requireVerifiedEmail,(req, res) => {
  const jobId = req.params.id;
  const userId = req.auth.sub;

  addInteraction(skips, userId, jobId);

  res.json({ ok: true });
});

router.post("/:id/save", requireAuth, requireVerifiedEmail,(req, res) => {
  const jobId = req.params.id;
  const userId = req.auth.sub;

  addInteraction(saves, userId, jobId);

  res.json({ ok: true });
});

module.exports = router;
