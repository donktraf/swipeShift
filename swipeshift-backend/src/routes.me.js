const express = require("express");
// const { prisma } = require("./prisma");
const { prisma } = require("./prisma.js");
const { requireAuth } = require("./auth");
const { z } = require("zod");
const { releaseUploads, checkPhotoUrl, INVALID_PHOTO_MESSAGE } = require("./uploadCleanup");
const { isAtLeast18, UNDERAGE_MESSAGE } = require("./utils/age");
const { validateWorkerProfileFields, cleanExperience, cleanWhitelist, cleanSocialLinks, AVAILABLE_TIMES, SHIFT_TYPES } = require("./utils/profileFields");
const { mergeConsents, consentsToFlags, allowedKeysForRole } = require("./utils/consents");

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
    const userId = req.auth.sub;

    const user = await prisma.user.findUnique({
      where:  { id: userId },
      select: {
        id: true, email: true, role: true, onboarding: true,
        firstName: true, lastName: true, location: true, lat: true, lng: true,
        emailVerifiedAt: true, passwordHash: true, createdAt: true, twoFactorEnabled: true, twoFactorMethod: true, pausedAt: true, legalConsents: true, isAdmin: true,
        worker: {
          select: {
            bio: true, dateOfBirth: true, jobInterests: true, availability: true, profilePhotoUrl: true,
            phone: true, willingToRelocate: true, maxTravelDistance: true, transport: true,
            availableForSameDay: true, preferredCategories: true, payRangeMin: true, payRangeMax: true,
            skills: true, workAuthorization: true,
            availableTimes: true, shiftTypes: true, experience: true,
          },
        },
        employer: {
          select: {
            companyName: true, companySize: true, industry: true,
            companyLogoUrl: true, websiteOrInstagram: true, companyDescription: true,
            companyPhone: true, companyEmail: true, businessAreas: true,
            locations: true, primaryHiringLocation: true, teamMembers: true,
            jobTitle: true, managerRole: true,
            yearFounded: true, tagline: true, socialLinks: true, streetAddress: true, zipCode: true,
            addressLat: true, addressLng: true, publicContactName: true, publicContactRole: true,
            postsInMultipleStates: true, remoteFriendly: true,
          },
        },
      },
    });

    if (!user) return res.status(401).json({ error: "User not found" });

    return res.json({
      id:               user.id,
      email:            user.email,
      role:             user.role,
      firstName:        user.firstName,
      lastName:         user.lastName,
      location:         user.location,
      lat:              user.lat,
      lng:              user.lng,
      onboarding:       user.onboarding,
      isEmailVerified:  !!user.emailVerifiedAt,
      hasSocialLogin:   user.passwordHash === "SOCIAL_LOGIN",
      twoFactorEnabled: user.twoFactorEnabled,
      twoFactorMethod: user.twoFactorEnabled ? (user.twoFactorMethod || "email") : null,
      isPaused:         !!user.pausedAt,
      isAdmin:          user.isAdmin === true,
      legalConsents:    consentsToFlags(user.legalConsents),
      createdAt:        user.createdAt,
      // Worker fields
      bio:                  user.worker?.bio                ?? null,
      dateOfBirth:          user.worker?.dateOfBirth?.toISOString().slice(0, 10) ?? null, // reines yyyy-MM-dd
      jobInterests:         user.worker?.jobInterests        ?? [],
      availability:         user.worker?.availability        ?? [],
      profilePhotoUrl:      user.worker?.profilePhotoUrl     ?? null,
      phone:                user.worker?.phone               ?? null,
      willingToRelocate:    user.worker?.willingToRelocate   ?? false,
      maxTravelDistance:    user.worker?.maxTravelDistance   ?? 10,
      transport:            user.worker?.transport           ?? "car",
      availableForSameDay:  user.worker?.availableForSameDay ?? false,
      preferredCategories:  user.worker?.preferredCategories ?? [],
      payRangeMin:          user.worker?.payRangeMin         ?? null,
      payRangeMax:          user.worker?.payRangeMax         ?? null,
      skills:               user.worker?.skills              ?? null,
      workAuthorization:    user.worker?.workAuthorization   ?? false,
      availableTimes:       cleanWhitelist(user.worker?.availableTimes, AVAILABLE_TIMES),
      shiftTypes:           cleanWhitelist(user.worker?.shiftTypes, SHIFT_TYPES),
      experience:           cleanExperience(user.worker?.experience),
      // Employer fields
      companyName:              user.employer?.companyName              ?? null,
      companySize:              user.employer?.companySize              ?? null,
      industry:                 user.employer?.industry                 ?? null,
      companyLogoUrl:           user.employer?.companyLogoUrl           ?? null,
      websiteOrInstagram:       user.employer?.websiteOrInstagram       ?? null,
      companyDescription:       user.employer?.companyDescription       ?? null,
      companyPhone:             user.employer?.companyPhone             ?? null,
      companyEmail:             user.employer?.companyEmail             ?? null,
      businessAreas:            user.employer?.businessAreas            ?? [],
      companyLocations:         user.employer?.locations                ?? [],
      primaryHiringLocation:    user.employer?.primaryHiringLocation    ?? null,
      teamMembers:              user.employer?.teamMembers              ?? null,
      jobTitle:                 user.employer?.jobTitle                 ?? null,
      managerRole:              user.employer?.managerRole              ?? null,
      yearFounded:              user.employer?.yearFounded              ?? null,
      tagline:                  user.employer?.tagline                  ?? null,
      socialLinks:              cleanSocialLinks(user.employer?.socialLinks),
      streetAddress:            user.employer?.streetAddress            ?? null,
      zipCode:                  user.employer?.zipCode                  ?? null,
      addressLat:               user.employer?.addressLat               ?? null,
      addressLng:               user.employer?.addressLng               ?? null,
      publicContactName:        user.employer?.publicContactName        ?? null,
      publicContactRole:        user.employer?.publicContactRole        ?? null,
      postsInMultipleStates:    user.employer?.postsInMultipleStates    ?? false,
      remoteFriendly:           user.employer?.remoteFriendly           ?? false,
    });
  } catch (err) {
    console.error("GET /auth/me error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

/**
 * PATCH /auth/me
 * Aktualisiert Profil-Felder des eingeloggten Users
 */
router.patch("/me", requireAuth, async (req, res) => {
  try {
    const userId = req.auth.sub;
    const {
      firstName, lastName, location, bio, dateOfBirth, availability, jobInterests,
      phone, willingToRelocate, maxTravelDistance, transport,
      availableForSameDay, preferredCategories, payRangeMin, payRangeMax,
      skills, workAuthorization, profilePhotoUrl, legalConsents,
    } = req.body;

    // 18+ serverseitig pruefen, bevor irgendetwas gespeichert wird
    if (dateOfBirth && !isAtLeast18(dateOfBirth)) {
      return res.status(400).json({ error: UNDERAGE_MESSAGE });
    }

    // Foto nur als eigene Upload-URL (oder leer) speichern
    const photoCheck = profilePhotoUrl !== undefined
      ? checkPhotoUrl(profilePhotoUrl, req, (await prisma.worker.findUnique({ where: { userId }, select: { profilePhotoUrl: true } }))?.profilePhotoUrl)
      : null;
    if (photoCheck && !photoCheck.ok) return res.status(400).json({ error: INVALID_PHOTO_MESSAGE });

    // Neue Worker-Felder (Tageszeiten, Schicht-Typen, Erfahrung) validieren, bevor etwas gespeichert wird
    const extra = validateWorkerProfileFields(req.body);
    if (extra.errors.length > 0) {
      return res.status(400).json({ error: extra.errors.join(" ") });
    }

    // User-Felder aktualisieren
    const userUpdate = {};
    if (firstName  !== undefined) userUpdate.firstName = firstName;
    if (lastName   !== undefined) userUpdate.lastName  = lastName;
    if (location   !== undefined) {
      userUpdate.location = location;
      // Geocode location
      if (location) {
        try {
          const { geocodeLocation } = require("./utils/geocode");
          const coords = await geocodeLocation(location);
          if (coords) { userUpdate.lat = coords.lat; userUpdate.lng = coords.lng; }
        } catch (_) {}
      }
    }

    // Rechtliche Zustimmungen (Whitelist je Rolle)
    if (legalConsents !== undefined) {
      const current = await prisma.user.findUnique({ where: { id: userId }, select: { role: true, legalConsents: true } });
      userUpdate.legalConsents = mergeConsents(current?.legalConsents, legalConsents, allowedKeysForRole(current?.role));
    }

    if (Object.keys(userUpdate).length > 0) {
      await prisma.user.update({ where: { id: userId }, data: userUpdate });
    }

    // Worker-Felder aktualisieren (upsert: Worker-Profil anlegen falls noch nicht vorhanden)
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { role: true } });
    if (user?.role === "worker") {
      const existingWorker = await prisma.worker.findUnique({ where: { userId } });
      const workerUpdate = {};
      if (bio                 !== undefined) workerUpdate.bio                = bio ?? null;
      if (dateOfBirth         !== undefined) workerUpdate.dateOfBirth        = dateOfBirth ? new Date(dateOfBirth) : (existingWorker?.dateOfBirth ?? new Date());
      if (availability        !== undefined) workerUpdate.availability       = availability;
      if (jobInterests        !== undefined) workerUpdate.jobInterests       = jobInterests;
      if (phone               !== undefined) workerUpdate.phone              = phone ?? null;
      if (willingToRelocate   !== undefined) workerUpdate.willingToRelocate  = !!willingToRelocate;
      if (maxTravelDistance   !== undefined) workerUpdate.maxTravelDistance  = Number(maxTravelDistance) || 10;
      if (transport           !== undefined) workerUpdate.transport          = transport ?? "car";
      if (availableForSameDay !== undefined) workerUpdate.availableForSameDay = !!availableForSameDay;
      if (preferredCategories !== undefined) workerUpdate.preferredCategories = preferredCategories ?? [];
      if (payRangeMin         !== undefined) workerUpdate.payRangeMin        = payRangeMin != null ? Number(payRangeMin) : null;
      if (payRangeMax         !== undefined) workerUpdate.payRangeMax        = payRangeMax != null ? Number(payRangeMax) : null;
      if (skills              !== undefined) workerUpdate.skills             = skills ?? null;
      if (workAuthorization   !== undefined) workerUpdate.workAuthorization  = !!workAuthorization;
      if (profilePhotoUrl     !== undefined) workerUpdate.profilePhotoUrl    = photoCheck.value;
      Object.assign(workerUpdate, extra.data);

      if (Object.keys(workerUpdate).length > 0) {
        const oldPhoto = "profilePhotoUrl" in workerUpdate
          ? (await prisma.worker.findUnique({ where: { userId }, select: { profilePhotoUrl: true } }))?.profilePhotoUrl
          : null;
        await prisma.worker.upsert({
          where:  { userId },
          update: workerUpdate,
          create: {
            userId,
            dateOfBirth: workerUpdate.dateOfBirth ?? new Date(),
            jobInterests: workerUpdate.jobInterests ?? [],
            availability: workerUpdate.availability ?? [],
            ...workerUpdate,
          },
        });
        // Altes Foto entfernen, wenn es ersetzt/geloescht wurde (fehlertolerant)
        if (oldPhoto) releaseUploads([oldPhoto], [workerUpdate.profilePhotoUrl]).catch(() => {});
      }
    }

    return res.json({ ok: true });
  } catch (err) {
    console.error("PATCH /auth/me error:", err);
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