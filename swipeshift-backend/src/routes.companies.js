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

    // Alle Jobs + Worker-Reviews für dieses Unternehmen parallel laden
    const [jobs, workerReviews] = await Promise.all([
    prisma.job.findMany({
      where:   { company: { equals: companyName, mode: "insensitive" } },
      select:  {
        id: true, title: true, category: true, location: true,
        payAmount: true, payText: true, shiftText: true, status: true,
        logoEmoji: true, companyRating: true, replyTime: true,
        isVerified: true, tags: true, startTime: true, employerId: true,
      },
      orderBy: { createdAt: "desc" },
    }),
    // Worker-Reviews werden nach employerId gefiltert (nach jobs.load)
    prisma.workerReview.findMany({
      where:   { apply: { job: { company: { equals: companyName, mode: "insensitive" } } } },
      include: {
        apply: {
          include: {
            user: { select: { firstName: true, lastName: true } },
          },
        },
      },
      orderBy: { createdAt: "desc" },
      take: 20,
    }),
    ]);

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
          // Oeffentliche Firmen-Kontaktdaten (vom Employer in "Company Information" gepflegt)
          companyPhone: true, companyEmail: true,
        },
      });
      if (emp) employerProfile = emp;
    }

    // Aggregierte Werte
    const activeJobs         = jobs.filter(j => j.status === "published").length;
    const completedJobsCount = jobs.filter(j => j.status === "completed").length;

    // Rating: Worker-Reviews bevorzugt, sonst Job-companyRating als Fallback
    const avg = (arr) => arr.length ? Math.round((arr.reduce((s, v) => s + v, 0) / arr.length) * 10) / 10 : null;
    const avgRating = workerReviews.length
      ? avg(workerReviews.map(r => r.overallExperience))
      : avg(jobs.map(j => j.companyRating).filter(Boolean));

    // Review-Breakdown
    const reviewBreakdown = workerReviews.length ? {
      communication:          avg(workerReviews.map(r => r.communication)),
      paymentFairness:        avg(workerReviews.map(r => r.paymentFairness)),
      workEnvironment:        avg(workerReviews.map(r => r.workEnvironment)),
      jobDescriptionAccuracy: avg(workerReviews.map(r => r.jobDescriptionAccuracy)),
      overallExperience:      avg(workerReviews.map(r => r.overallExperience)),
      totalReviews:           workerReviews.length,
    } : null;

    // Einzelne Worker-Reviews (max 10)
    const reviewsList = workerReviews.slice(0, 10).map(r => ({
      id:                    r.id,
      workerName:            r.apply?.user ? `${r.apply.user.firstName} ${r.apply.user.lastName}` : "Anonymous",
      communication:          r.communication,
      paymentFairness:        r.paymentFairness,
      workEnvironment:        r.workEnvironment,
      jobDescriptionAccuracy: r.jobDescriptionAccuracy,
      overallExperience:      r.overallExperience,
      comment:               r.comment ?? null,
      createdAt:             r.createdAt,
    }));

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
      phone:          employerProfile?.companyPhone ?? null,
      email:          employerProfile?.companyEmail ?? null,
      industry:       employerProfile?.industry ?? null,
      companySize:    employerProfile?.companySize ?? null,
      // Offene Jobs für "View Open Jobs"
      openJobs: jobs
        .filter(j => j.status === "published")
        .map(j => ({
          id: j.id, title: j.title, payText: j.payText,
          shiftText: j.shiftText, category: j.category,
        })),
      reviewBreakdown,
      workerReviews: reviewsList,
    });
  } catch (err) {
    console.error("GET /companies/:name error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;
