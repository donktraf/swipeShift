const express = require("express");
// const { prisma } = require("./prisma");
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const { z } = require("zod");

const router = express.Router();

const roleSchema = z.object({
  role: z.enum(["worker", "employer"]),
});

/**
 * GET /auth/me
 * Gibt den aktuell eingeloggten User zurück
 */
router.get("/me", requireAuth, async (req, res) => {
  try {
    const userId = req.auth.sub; // kommt aus JWT

    const user = await prisma.user.findUnique({
      where: { id: userId },
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
        passwordHash: true,
        createdAt: true,
      },
    });

    if (!user) {
      return res.status(401).json({ error: "User not found" });
    }

    return res.json({
      id: user.id,
      email: user.email,
      role: user.role,
      firstName: user.firstName,
      lastName: user.lastName,
      location: user.location,
      lat: user.lat,
      lng: user.lng,
      onboarding: user.onboarding,
      isEmailVerified: !!user.emailVerifiedAt,
      hasSocialLogin: user.passwordHash === "SOCIAL_LOGIN",
      createdAt: user.createdAt,
    });

  } catch (err) {

    console.error("GET /auth/me error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * PATCH /auth/me/role
 * Setzt role und schaltet onboarding -> pendingProfile
 */
router.patch("/me/role", requireAuth, async (req, res) => {
  console.log("PATCH /auth/me/role");

  const parsed = roleSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({
      error: "Invalid input",
      details: parsed.error.flatten(),
    });
  }

  try {
    const userId = req.auth.sub;
    const { role } = parsed.data;

    const updated = await prisma.user.update({
      where: { id: userId },
      data: {
        role,
        onboarding: "pendingProfile",
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

    return res.json({
      ...updated,
      isEmailVerified: !!updated.emailVerifiedAt,
    });
  } catch (e) {
    console.error("PATCH /auth/me/role error:", e);
    return res.status(500).json({ error: "Internal server error" });
  }
});


module.exports = router;