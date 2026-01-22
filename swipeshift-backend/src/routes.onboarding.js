// src/routes.onboarding.js
const express = require("express");
const { prisma } = require("./prisma");
const { requireAuth } = require("./auth");
const { z } = require("zod");

const router = express.Router();

/**
 * Worker onboarding body
 */
const workerSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  location: z.string().min(1),
  lat: z.number(),
  lng: z.number(),
  dateOfBirth: z.string().min(1),
  jobInterests: z.array(z.string().min(1)).min(1),
  availability: z.array(z.object({
    name: z.string().min(1),
    available: z.boolean(),
  })).length(7),

  bio: z.string().max(300).optional(),
  profilePhotoUrl: z.string().url().optional(),
});

router.patch("/worker", requireAuth, async (req, res) => {
  const parsed = workerSchema.safeParse(req.body);

  console.log("Aufruf API. onBoarding Worker. Empfangende Daten: ", parsed);

  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  try {
    const userId = req.auth.sub;

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.status(401).json({ error: "User not found" });

    if (user.role !== "worker") {
      return res.status(409).json({ error: "Role is not worker. Set role first." });
    }

    const data = parsed.data;

    // Upsert Worker
    await prisma.worker.upsert({
      where: { userId },
      update: {
        dateOfBirth: new Date(data.dateOfBirth),
        bio: data.bio ?? null,
        profilePhotoUrl: data.profilePhotoUrl ?? null,
        jobInterests: data.jobInterests,
        availability: data.availability,
      },
      create: {
        userId,
        dateOfBirth: new Date(data.dateOfBirth),
        bio: data.bio ?? null,
        profilePhotoUrl: data.profilePhotoUrl ?? null,
        jobInterests: data.jobInterests,
        availability: data.availability,
      },
    });

    const updated = await prisma.user.update({
      where: { id: userId },
      data: {
        onboarding: "complete",
        location: data.location,
        lat: data.lat,
        lng: data.lng,
        ...(data.firstName ? { firstName: data.firstName } : {}),
        ...(data.lastName ? { lastName: data.lastName } : {}),
      },
      select: {
        id: true,
        email: true,
        role: true,
        onboarding: true,
        firstName: true,
        lastName: true,
        location: true,
        lat: true,
        lng: true,
        emailVerifiedAt: true,
      },
    });

    console.log("Onboarding/ Aktualisierter User: ", updated);
    console.log("isEmailVerified: ", !!updated.emailVerifiedAt);

    return res.json({
      ...updated,
      isEmailVerified: !!updated.emailVerifiedAt,
    });
  } catch (e) {
    console.error("PATCH /onboarding/worker error:", e);
    return res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * Employer onboarding body
 */
const employerSchema = z.object({
  firstName: z.string().min(1).optional(),
  lastName: z.string().min(1).optional(),
  location: z.string().min(1),

  companyName: z.string().min(1),
  companySize: z.enum(["1-10", "11-50", "50+"]),
  industry: z.string().min(1),

  companyLogoUrl: z.string().url().optional(),
  websiteOrInstagram: z.string().min(1).optional(),
  companyDescription: z.string().max(300).optional(),
});

router.patch("/employer", requireAuth, async (req, res) => {
  const parsed = employerSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  try {
    const userId = req.auth.sub;

    const user = await prisma.user.findUnique({ where: { id: userId } });
    if (!user) return res.status(401).json({ error: "User not found" });

    if (user.role !== "employer") {
      return res.status(409).json({ error: "Role is not employer. Set role first." });
    }

    const data = parsed.data;

    // Upsert Employer
    await prisma.employer.upsert({
      where: { userId },
      update: {
        companyName: data.companyName,
        companySize: data.companySize,
        industry: data.industry,
        companyLogoUrl: data.companyLogoUrl ?? null,
        websiteOrInstagram: data.websiteOrInstagram ?? null,
        companyDescription: data.companyDescription ?? null,
      },
      create: {
        userId,
        companyName: data.companyName,
        companySize: data.companySize,
        industry: data.industry,
        companyLogoUrl: data.companyLogoUrl ?? null,
        websiteOrInstagram: data.websiteOrInstagram ?? null,
        companyDescription: data.companyDescription ?? null,
      },
    });

    const updated = await prisma.user.update({
      where: { id: userId },
      data: {
        onboarding: "complete",
        location: data.location,
        ...(data.firstName ? { firstName: data.firstName } : {}),
        ...(data.lastName ? { lastName: data.lastName } : {}),
      },
      select: {
        id: true,
        email: true,
        role: true,
        onboarding: true,
        firstName: true,
        lastName: true,
        location: true,
        emailVerifiedAt: true,
      },
    });

    return res.json({
      ...updated,
      isEmailVerified: !!updated.emailVerifiedAt,
    });
  } catch (e) {
    console.error("PATCH /onboarding/employer error:", e);
    return res.status(500).json({ error: "Internal server error" });
  }
});

module.exports = router;