// src/routes.companies.js
// Öffentliche Company-Profile – kein Auth nötig

const express = require("express");
const router  = express.Router();
const { prisma } = require("./prisma.js");

// GET /companies/:name
// Gibt Company-Daten aus Jobs + Employer-Profil zurück
router.get("/:name", async (req, res) => {
  try {
    const companyName = decodeURIComponent(req.params.name);

    // Alle Jobs dieses Unternehmens
    const jobs = await prisma.job.findMany({
      where:   { company: { equals: companyName, mode: "insensitive" } },
      select:  {
        id: true, title: true, category: true, location: true,
        payAmount: true, payText: true, shiftText: true, status: true,
        logoEmoji: true, companyRating: true, replyTime: true,
        isVerified: true, tags: true, startTime: true, employerId: true,
      },
      orderBy: { createdAt: "desc" },
    });

    if (!jobs.length) return res.status(404).json({ error: "Company not found" });

    // Employer-Nutzer für erweiterte Firmeninfos (optional)
    const employerId = jobs[0].employerId;
    let employerProfile = null;
    if (employerId) {
      const emp = await prisma.employer.findFirst({
        where:  { userId: employerId },
        select: {
          companyName: true, companySize: true, industry: true,
          companyLogoUrl: true, websiteOrInstagram: true, companyDescription: true,
        },
      });
      if (emp) employerProfile = emp;
    }

    // Aggregierte Werte
    const activeJobs       = jobs.filter(j => j.status === "published").length;
    const completedJobsCount = jobs.filter(j => j.status === "completed").length;
    const ratings          = jobs.map(j => j.companyRating).filter(Boolean);
    const avgRating        = ratings.length
      ? Math.round((ratings.reduce((s, r) => s + r, 0) / ratings.length) * 10) / 10
      : null;

    // Kategorien
    const categories = [...new Set(jobs.map(j => j.category).filter(Boolean))];

    // Standorte
    const locations = [...new Set(jobs.map(j => j.location).filter(Boolean))];

    return res.json({
      name:           companyName,
      logoEmoji:      jobs[0].logoEmoji,
      isVerified:     jobs[0].isVerified,
      rating:         avgRating,
      completedJobs:  completedJobsCount,
      activeJobs,
      businessAreas:  categories,
      locations,
      replyTime:      jobs[0].replyTime ?? null,
      // Aus Employer-Profil (falls vorhanden)
      about:          employerProfile?.companyDescription ?? null,
      website:        employerProfile?.websiteOrInstagram ?? null,
      industry:       employerProfile?.industry ?? null,
      companySize:    employerProfile?.companySize ?? null,
      // Offene Jobs für "View Open Jobs"
      openJobs: jobs
        .filter(j => j.status === "published")
        .map(j => ({
          id: j.id, title: j.title, payText: j.payText,
          shiftText: j.shiftText, category: j.category,
        })),
    });
  } catch (err) {
    console.error("GET /companies/:name error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
