// src/routes.auth.js
const express = require("express");
const bcrypt = require("bcrypt");
const { z } = require("zod");
const { v4: uuid } = require("uuid");
const { completeLogin, respondIfRestricted } = require("./sessions");
const { normalizeEmail, decideAppleLogin, decideGoogleLogin, needsTakeoverCleanup } = require("./utils/socialLogin");
const { sanitizeTakenOverAccount } = require("./accountTakeover");
const { canonicalEmail } = require("./utils/emailCanonical");
const { isBannedEmailAlias } = require("./emailBan");
const { emailChangedNotice } = require("./utils/emailChangeNotice");
const { prisma } = require("./prisma.js");
const crypto = require("crypto");
const { sendMail } = require("./mailer");
const { passwordResetEmail } = require("./emails/passwordResetEmail");

const { OAuth2Client } = require("google-auth-library");
const { createRemoteJWKSet, jwtVerify } = require("jose");
const { requireAuth } = require("./auth");
const { removeDevicesForSessions } = require("./pushDevices");

const GOOGLE_CLIENT_ID = process.env.GOOGLE_CLIENT_ID; // iOS ClientID
const googleClient = new OAuth2Client(GOOGLE_CLIENT_ID);

// Apple JWKS
const appleJWKS = createRemoteJWKSet(new URL("https://appleid.apple.com/auth/keys"));

const router = express.Router();

// Validierung: passt später zu iOS Requests // -> Restliche Felder hinzufügen 

// Gemeinsame Felder (für beide Rollen)
const baseRegisterSchema = z.object({
  role: z.enum(["worker", "employer"]),
  // optional (alte Clients senden es nicht); wird nur gespeichert, wenn true
  acceptedTerms: z.boolean().optional(),
  firstName: z.string().min(1),
  lastName: z.string().min(1),

  email: z.email(),
  password: z.string().min(6),
  location: z.string().min(1),

  lat: z.number(),
  lng: z.number(),
});

// 18+ Check: siehe utils/age.js
const { isAtLeast18 } = require("./utils/age");
const { mergeConsents } = require("./utils/consents");

// Worker-spezifisch
const workerRegisterSchema = baseRegisterSchema.extend({
  role: z.literal("worker"),

  // required Worker fields
  dateOfBirth: z.string().min(1),
  jobInterests: z.array(z.string().min(1)).min(1),

  // wir erwarten 7 Tage (Mon-Sun). Du kannst das lockerer machen, aber so ist MVP stabil.
  // availability: z.array(
  //   z.object({
  //     name: z.string().min(1),
  //     available: z.boolean(),
  //   })
  // ).length(7),
  availability: z.array(
    z.object({
      name: z.enum(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]),
      available: z.boolean(),
    })
  ).min(1).max(7)
    .refine(
      (arr) => new Set(arr.map(d => d.name)).size === arr.length,
      "Duplicate days not allowed"
    ),

  // optional
  bio: z.string().max(300).optional(),
  profilePhotoUrl: z.string().url().optional(),

}).superRefine((data, ctx) => {
  // ✅ 18+ serverseitig prüfen
  if (!isAtLeast18(data.dateOfBirth)) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["dateOfBirth"],
      message: "You must be at least 18 years old.",
    });
  }

  // ✅ mindestens ein Tag available=true
  const anyAvailable = data.availability.some(d => d.available === true);
  if (!anyAvailable) {
    ctx.addIssue({
      code: z.ZodIssueCode.custom,
      path: ["availability"],
      message: "Please select at least one available day.",
    });
  }
});

// Employer-spezifisch (alles required!)
const employerRegisterSchema = baseRegisterSchema.extend({
  role: z.literal("employer"),

  companyName: z.string().min(1),
  companySize: z.enum(["1-10", "11-50", "50+"]),
  industry: z.string().min(1),

  // OPTIONAL fields
  companyLogoUrl: z.string().url().optional(),
  websiteOrInstagram: z.string().min(1).optional(),
  companyDescription: z.string().max(300).optional(),
});

// EIN Schema für beide Rollen
const registerSchema = z.discriminatedUnion("role", [
  workerRegisterSchema,
  employerRegisterSchema,
]);

const rateLimit = require('express-rate-limit');

// eher streng (login)
const loginLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 10,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many login attempts, try again later." },
});

// eher locker (register)
const registerLimiter = rateLimit({
  windowMs: 60 * 60 * 1000,
  max: 20,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: "Too many registrations, try again later." },
});

// reset / resend: spam-schutz
const mailLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 5,
  standardHeaders: true,
  legacyHeaders: false,
  message: { ok: true }, // ✅ absichtlich generisch (keine Infos leaken)
});


router.post("/register", registerLimiter, async (req, res) => {

  // E-Mail vor der Validierung normalisieren (trim + lowercase), damit der Bestehende-Konten-/Bann-Check greift.
  // Alias-Umgehung eines Banns (Gmail-Punkte, +tag): siehe isBannedEmailAlias (utils/emailCanonical.js).
  if (req.body && typeof req.body === "object" && typeof req.body.email === "string") {
    req.body = { ...req.body, email: normalizeEmail(req.body.email) };
  }

  const parsed = registerSchema.safeParse(req.body);

  if (!parsed.success) {

    return res.status(400).json({
      error: "Invalid input",
      fieldErrors: parsed.error
    });
    //return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  const data = parsed.data;

  // Email uniqueness
  const exists = await prisma.user.findUnique({
    where: { email: data.email.toLowerCase() }
  });

  // Gebannter Nutzer mit derselben kanonischen E-Mail (Alias) → gleiche generische Antwort, kein Hinweis auf den Bann
  if (exists || await isBannedEmailAlias(data.email)) {
    console.log("Email Existiert.");

    return res.status(409).json({
      error: "Email already registered",
      fieldErrors: { email: ["Email is already registered."] },
    });
  }

  const passwordHash = await bcrypt.hash(data.password, 12);

  const user = await prisma.user.create({
    data: {
      email: data.email.toLowerCase(),
      emailCanonical: canonicalEmail(data.email),
      notificationsSeenAt: new Date(), // neue Konten starten ohne Ungelesen-Badge
      passwordHash,
      role: data.role,
      firstName: data.firstName,
      lastName: data.lastName,
      location: data.location,
      lat: data.lat,
      lng: data.lng,
      onboarding: "complete",
      ...(data.acceptedTerms === true
        ? { legalConsents: mergeConsents(null, { terms: true }, ["terms"]) }
        : {}),

      worker: data.role === "worker"
        ? {
          create: {
            dateOfBirth: new Date(data.dateOfBirth),
            bio: data.bio ?? null,
            profilePhotoUrl: data.profilePhotoUrl ?? null,
            jobInterests: data.jobInterests,
            availability: data.availability,
          }
        }
        : undefined,

      employer: data.role === "employer"
        ? {
          create: {
            companyName: data.companyName,
            companySize: data.companySize,
            industry: data.industry,
            companyLogoUrl: data.companyLogoUrl ?? null,
            websiteOrInstagram: data.websiteOrInstagram ?? null,
            companyDescription: data.companyDescription ?? null,
          }
        }
        : undefined,
    },
  });


  // ✅ Email verification token + mail (nur für normalen Register)
  const rawToken = await issueEmailVerificationToken(user.id);
  const verifyLink = buildVerifyLink(user.email, rawToken);

  // Schlaegt der Versand fehl, bleibt das Konto bestehen → verificationEmailSent=false, die App bietet "Resend" an
  let verificationEmailSent = true;
  try {
    await sendVerificationEmail(user.email, verifyLink);

    console.log("Verification email sent to:", user.email);
    console.log("Verify link:", verifyLink);
  } catch (e) {
    verificationEmailSent = false;
    console.error("Failed to send verification email:", e);
  }




  console.log("User:  ", user)



  try {
    return res.json(await completeLogin(user, req, { extra: { verificationEmailSent } }));
  } catch (err) {
    console.error("POST /auth/register session error:", err);
    return res.status(500).json({ error: "Account created, but sign-in failed. Please log in." });
  }
});

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1),
});

router.post("/login", loginLimiter, async (req, res) => {
  console.log("LOGIN")
  const parsed = loginSchema.safeParse(req.body);

  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  const { email, password } = parsed.data;


  const user = await prisma.user.findUnique({
    where: { email: email.trim().toLowerCase() },
    select: {
      id: true,
      email: true,
      role: true,
      onboarding: true,
      location: true,
      lat: true,
      lng: true,
      firstName: true,
      lastName: true,
      emailVerifiedAt: true,
      passwordHash: true,
      twoFactorEnabled: true,
      twoFactorMethod: true,
      bannedAt: true,
      suspendedUntil: true,
      suspensionReason: true,
    },
  });




  if (!user) {
    console.log("Invalid pw ode email")

    return res.status(401).json({ error: "Invalid email or password." });
  }

  // ✅ Social-User: Passwortlogin blocken
  if (user.passwordHash === "SOCIAL_LOGIN") {
    // Wichtig: nicht "invalid pw" sagen, sondern klarer Hinweis
    // (du kannst auch 409 oder 400 nehmen; 401 ist ok, aber semantisch ist 409/400 schöner)
    return res.status(409).json({
      error: "This account uses social login.",
      code: "SOCIAL_ACCOUNT",
      message: "Please sign in with Google/Apple or set a password first."
    });
  }

  const ok = await bcrypt.compare(password, user.passwordHash);
  console.log("Passowrd richtig? :", ok)

  if (!ok) {
    console.log("Invalid pw ode email")
    return res.status(401).json({ error: "Invalid email or password." });
  }

  // Bei aktivierter 2FA: { twoFactorRequired, challengeId, ... } statt Token
  try {
    return res.json(await completeLogin(user, req));
  } catch (err) {
    // z.B. Mailversand fuer den 2FA-Code fehlgeschlagen — nicht den Prozess abstuerzen lassen
    if (respondIfRestricted(err, res)) return;
    console.error("POST /auth/login completeLogin error:", err);
    return res.status(500).json({ error: "Could not complete sign-in. Please try again." });
  }
});

const forgotPasswordSchema = z.object({
  email: z.string().email(),
});

router.post("/forgot-password", async (req, res) => {
  console.log("forgot passowrd aufgerufen");

  const parsed = forgotPasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  const email = parsed.data.email.toLowerCase();

  // ✅ Wichtig: Immer gleiche Antwort (keine User Enumeration)
  const okResponse = { ok: true };

  const user = await prisma.user.findUnique({ where: { email } });

  if (!user) return res.json(okResponse);

  // Token erzeugen (raw) und Hash speichern
  const rawToken = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(Date.now() + 1000 * 60 * 30); // 30 Minuten

  // Optional: alte Tokens invalidieren (Best practice)
  await prisma.passwordResetToken.updateMany({
    where: { userId: user.id, usedAt: null },
    data: { usedAt: new Date() },
  });

  await prisma.passwordResetToken.create({
    data: {
      userId: user.id,
      tokenHash,
      expiresAt,
    },
  });

  //Email versenden
  const scheme = process.env.APP_SCHEME || "swipeshift";
  const resetLink = `${scheme}://reset-password?token=${rawToken}&email=${encodeURIComponent(email)}`;

  // optionaler Web-Fallback (falls Deep Link nicht geht)
  const fallbackBase = process.env.PUBLIC_RESET_FALLBACK_URL || "http://localhost:3000/reset-password";
  const fallbackLink = `${fallbackBase}?token=${rawToken}&email=${encodeURIComponent(email)}`;

  const { subject, text, html } = passwordResetEmail({
    resetLink,
    fallbackLink,
    expiresMinutes: 30,
  });

  try {
    await sendMail({
      to: email,
      subject,
      text,
      html,
    });

    console.log("Password reset email sent to:", email);
  } catch (err) {
    // ✅ Trotzdem ok zurückgeben (keine Enumeration)
    console.error("Failed to send reset email:", err);
  }

  console.log("Password reset link:", resetLink);

  // In non-production: include raw token so the iOS simulator can auto-apply it
  // without needing xcrun simctl openurl
  const isDev = process.env.NODE_ENV !== "production";
  return res.json({
    ...okResponse,
    ...(isDev ? { _devToken: rawToken, _devEmail: email, _devLink: resetLink } : {}),
  });
});

const resetPasswordSchema = z.object({
  email: z.string().email(),
  token: z.string().min(10),
  newPassword: z.string().min(6),
});

router.post("/reset-password", mailLimiter, async (req, res) => {
  const parsed = resetPasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: "Invalid input", details: parsed.error.flatten() });
  }

  const { email, token, newPassword } = parsed.data;
  const normalizedEmail = email.toLowerCase();

  const user = await prisma.user.findUnique({ where: { email: normalizedEmail } });
  if (!user) {
    // gleiches Verhalten: generisch
    return res.status(400).json({ error: "Invalid token or expired." });
  }

  const tokenHash = crypto.createHash("sha256").update(token).digest("hex");

  const record = await prisma.passwordResetToken.findFirst({
    where: {
      userId: user.id,
      tokenHash,
      usedAt: null,
      expiresAt: { gt: new Date() },
    },
  });

  if (!record) {
    return res.status(400).json({ error: "Invalid token or expired." });
  }

  const passwordHash = await bcrypt.hash(newPassword, 12);

  // Transaction: Passwort setzen + Token als used markieren
  await prisma.$transaction([
    prisma.user.update({
      where: { id: user.id },
      data: { passwordHash },
    }),
    prisma.userSession.updateMany({ where: { userId: user.id }, data: { reauthAt: null } }), // Step-up verfaellt
    prisma.passwordResetToken.update({
      where: { id: record.id },
      data: { usedAt: new Date() },
    }),
    // Passwort zurueckgesetzt → ueberall abmelden
    prisma.userSession.updateMany({
      where: { userId: user.id, revokedAt: null },
      data: { revokedAt: new Date() },
    }),
  ]);
  await removeDevicesForSessions({ userId: user.id }); // alle Sessions widerrufen → keine Pushes mehr

  return res.json({
    ok: true
  });
});

router.post("/google", async (req, res) => {
  console.log("google Route aufgerufen")

  try {
    const { idToken } = req.body || {};

    //Validierungen 
    if (!idToken)
      return res.status(400).json({ error: "Missing idToken" });

    if (!GOOGLE_CLIENT_ID)
      return res.status(500).json({ error: "GOOGLE_CLIENT_ID not set" });


    const ticket = await googleClient.verifyIdToken({
      idToken,
      audience: GOOGLE_CLIENT_ID,
    });

    const payload = ticket.getPayload();

    if (!payload?.email)
      return res.status(401).json({ error: "Invalid Google token" });

    console.log("Google Object: ", payload);

    const email = normalizeEmail(payload.email);
    const firstName = payload.given_name || "User";
    const lastName = payload.family_name || "Google";

    let user = await prisma.user.findUnique({
      where: { email }
    });

    // Nur die von Google VERIFIZIERTE Token-E-Mail darf ein Konto matchen/anlegen (siehe utils/socialLogin.js)
    const googleSaysVerified = payload.email_verified === true;
    const decision = decideGoogleLogin({ tokenEmail: email, emailVerified: googleSaysVerified, existingUser: user });
    if (decision.action === "reject") return res.status(decision.status).json({ error: decision.error });

    const SOCIAL_LOGIN_PASSWORD_PLACEHOLDER = "SOCIAL_LOGIN";

    //merken ob User gerade neu erstellt wird
    let isNewUser = false;

    if (decision.action === "create") {
      // Alias eines gebannten Nutzers → wie "E-Mail existiert schon" ablehnen (kein Hinweis auf den Bann)
      if (await isBannedEmailAlias(email)) {
        return res.status(409).json({ error: "An account with this email already exists. Please sign in with your original method.", code: "EMAIL_IN_USE" });
      }
      isNewUser = true;
      user = await prisma.user.create({
        data: {
          email,
          emailCanonical: canonicalEmail(email),
          notificationsSeenAt: new Date(),
          passwordHash: SOCIAL_LOGIN_PASSWORD_PLACEHOLDER, // ✅ wird nie genutzt
          onboarding: "pendingRole",
          firstName,
          lastName,
          location: null,
          emailVerifiedAt: new Date(),
        },
      });
      console.log("User gibts nicht also wurde er registriert");
    } else if (needsTakeoverCleanup(user)) {
      // Bisher unverifiziertes Passwort-Konto wird per Google uebernommen: Angreifer-Passwort/2FA/Sitzungen weg
      user = await sanitizeTakenOverAccount(user);
    }

    return res.json(
      await completeLogin(user, req, {
        userOverrides: { profilePhotoUrl: user.profilePhotoUrl, isEmailVerified: googleSaysVerified, hasSocialLogin: true },
        extra: { isNewUser },
      })
    );
  } catch (e) {
    if (respondIfRestricted(e, res)) return;
    console.error("Google auth error:", e);
    console.error(e);
    return res.status(401).json({ error: "Invalid token" });
  }
});

router.post("/apple", async (req, res) => {
  try {
    const { idToken, firstName, lastName, email } = req.body || {};
    if (!idToken) return res.status(400).json({ error: "Missing idToken" });

    // verify Apple identityToken
    const { payload } = await jwtVerify(idToken, appleJWKS, {
      issuer: "https://appleid.apple.com",
      // audience kann je nach Setup dein Bundle ID oder Service ID sein.
      // Wenn du es schon hast:
      audience: process.env.APPLE_CLIENT_ID, // setze das in .env
    });

    console.log("Apple aud:", payload.aud, "iss:", payload.iss, "sub:", payload.sub);

    // Apple liefert die E-Mail nicht immer im Token. Der Body (`email`) ist UNVERIFIZIERT:
    // nie zum Einloggen in ein bestehendes Konto, hoechstens als Kontaktangabe fuer ein neues (siehe utils/socialLogin.js).
    const appleSub = typeof payload.sub === "string" ? payload.sub : "";
    const lookupEmail = normalizeEmail(payload.email) || normalizeEmail(email);

    // Entscheidung + Konto laden/anlegen. Bei paralleler Erst-Anmeldung (Unique-Konflikt auf appleSub/email)
    // wird genau einmal neu entschieden — nie "Invalid token".
    const resolveAppleUser = async (attempt) => {
      const [userBySub, userByEmail] = await Promise.all([
        appleSub ? prisma.user.findUnique({ where: { appleSub } }) : null,
        lookupEmail ? prisma.user.findUnique({ where: { email: lookupEmail } }) : null,
      ]);
      const decision = decideAppleLogin({
        tokenSub: appleSub,
        tokenEmail: payload.email,
        tokenEmailVerified: payload.email_verified,
        bodyEmail: email,
        userBySub,
        userByEmail,
      });
      if (decision.action === "reject") return { reject: { status: decision.status, body: { error: decision.error, code: decision.code } } };

      if (decision.action === "login") {
        let user = decision.user;
        // Erster Apple-Login eines bestehenden Kontos (per verifizierter Token-E-Mail): Subject merken
        if (decision.linkSub && user.appleSub && user.appleSub !== appleSub) {
          // Konto ist schon mit einer ANDEREN Apple-ID verknuepft → nicht ueberschreiben
          return { reject: { status: 409, body: { error: "This account is linked to a different Apple ID.", code: "APPLE_ID_MISMATCH" } } };
        }
        if (decision.linkSub && needsTakeoverCleanup(user)) {
          user = await sanitizeTakenOverAccount(user); // Pre-Hijacking-Schutz (siehe accountTakeover.js)
        }
        if (decision.linkSub && !user.appleSub) {
          user = await prisma.user.update({ where: { id: user.id }, data: { appleSub } });
        }
        return { user, isNewUser: false };
      }

      // Alias eines gebannten Nutzers → wie "E-Mail existiert schon" ablehnen (kein Hinweis auf den Bann)
      if (await isBannedEmailAlias(decision.email)) {
        return { reject: { status: 409, body: { error: "An account with this email already exists. Please sign in with your original method.", code: "EMAIL_IN_USE" } } };
      }

      try {
        const user = await prisma.user.create({
          data: {
            email: decision.email,
            emailCanonical: canonicalEmail(decision.email),
            appleSub,
            notificationsSeenAt: new Date(),
            passwordHash: "SOCIAL_LOGIN",
            role: null,
            onboarding: "pendingRole",
            firstName: firstName || "User",
            lastName: lastName || "Apple",
            location: null,
            emailVerifiedAt: decision.emailVerified ? new Date() : null, // Body-E-Mail bleibt unverifiziert
          },
        });
        return { user, isNewUser: true };
      } catch (err) {
        if (err?.code === "P2002" && attempt === 0) return resolveAppleUser(1);
        if (err?.code === "P2002") {
          return { reject: { status: 409, body: { error: "Please try signing in again.", code: "TRY_AGAIN" } } };
        }
        throw err;
      }
    };

    const resolved = await resolveAppleUser(0);
    if (resolved.reject) return res.status(resolved.reject.status).json(resolved.reject.body);
    const { user, isNewUser } = resolved;

    return res.json(
      await completeLogin(user, req, {
        userOverrides: { isEmailVerified: !!user.emailVerifiedAt, hasSocialLogin: true },
        extra: { isNewUser },
      })
    );
  } catch (e) {
    if (respondIfRestricted(e, res)) return;
    console.error("Apple auth error:", e);
    return res.status(401).json({ error: "Invalid token" });
  }
});

router.get("/verify-email", async (req, res) => {
  console.log("sending verification Email");
  try {
    const token = String(req.query.token || "");
    const email = String(req.query.email || "").toLowerCase();
    const redirect = String(req.query.redirect || "");

    if (!token || !email)
      return res.status(400).send("Missing token/email");

    const user = await prisma.user.findUnique({
      where: { email }
    });

    if (!user)
      return res.status(400).send("Invalid link");

    const tokenHash = crypto.createHash("sha256").update(token).digest("hex");

    const row = await prisma.emailVerificationToken.findUnique({
      where: { tokenHash },
    });

    if (!row || row.userId !== user.id)
      return res.status(400).send("Invalid link");

    if (row.usedAt)
      return res.status(400).send("Link already used");

    if (row.expiresAt < new Date())
      return res.status(400).send("Link expired");

    // ✅ mark used + verify user
    await prisma.$transaction([
      prisma.emailVerificationToken.update({
        where: { id: row.id },
        data: { usedAt: new Date() },
      }),
      prisma.user.update({
        where: { id: user.id },
        data: { emailVerifiedAt: new Date() },
      }),
    ]);

    // Redirect zurück in App (wenn redirect param da ist)
    if (redirect) {
      return res.redirect(302, redirect);
    }

    // Fallback simple HTML
    return res.send("Email verified. You can return to the app.");
  } catch (e) {
    console.error("verify-email error:", e);
    return res.status(500).send("Server error");
  }
});

const resendSchema = z.object({ email: z.string().email() });

// Antwortet bewusst IMMER { ok: true } (keine User-Enumeration); Versandfehler sind fuer die App hier nicht sichtbar.
router.post("/resend-verification", mailLimiter, async (req, res) => {
  const parsed = resendSchema.safeParse(req.body);
  if (!parsed.success) return res.status(400).json({ error: "Invalid input" });

  const email = parsed.data.email.toLowerCase();

  // ✅ immer ok antworten (keine enumeration)
  const okResponse = { ok: true };

  const user = await prisma.user.findUnique({ where: { email } });
  if (!user) return res.json(okResponse);

  // wenn schon verified, keine mail
  if (user.emailVerifiedAt) return res.json(okResponse);

  const rawToken = await issueEmailVerificationToken(user.id);
  const verifyLink = buildVerifyLink(user.email, rawToken);

  try {
    await sendVerificationEmail(user.email, verifyLink);
    console.log("✅ Resent verification mail:", user.email);
  } catch (e) {
    console.error("❌ Failed to resend verification:", e);
  }

  return res.json(okResponse);
});

// MARK: - Set Password (für Social-Login-User die noch kein Passwort haben)
const setPasswordSchema = z.object({
  newPassword: z.string().min(8, "Password must be at least 8 characters"),
});

// POST /auth/change-password
router.post("/change-password", requireAuth, async (req, res) => {
  const { currentPassword, newPassword } = req.body;
  if (!currentPassword || !newPassword) return res.status(400).json({ error: "Missing fields" });
  if (newPassword.length < 8) return res.status(400).json({ error: "Password must be at least 8 characters" });

  const userId = req.auth.sub;
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { passwordHash: true } });
  if (!user || !user.passwordHash || user.passwordHash === "SOCIAL_LOGIN")
    return res.status(400).json({ error: "No password set on this account" });

  const valid = await bcrypt.compare(currentPassword, user.passwordHash);
  if (!valid) return res.status(401).json({ error: "Current password is incorrect" });

  const hash = await bcrypt.hash(newPassword, 12);
  // Neues Passwort → alle anderen Geraete abmelden (aktuelles bleibt eingeloggt)
  await prisma.$transaction([
    prisma.user.update({ where: { id: userId }, data: { passwordHash: hash } }),
    prisma.userSession.updateMany({ where: { userId }, data: { reauthAt: null } }), // Step-up verfaellt
    prisma.userSession.updateMany({
      where: { userId, revokedAt: null, id: { not: req.auth.sid } },
      data: { revokedAt: new Date() },
    }),
  ]);
  await removeDevicesForSessions({ userId, sessionId: { not: req.auth.sid } }); // andere Geraete abgemeldet
  return res.json({ ok: true });
});

// PATCH /auth/me/email
router.patch("/me/email", requireAuth, async (req, res) => {
  const { password } = req.body;
  const newEmail = normalizeEmail(req.body.newEmail); // trim + lowercase, wie bei Register
  if (!newEmail || !password) return res.status(400).json({ error: "Missing fields" });

  try {
  const userId = req.auth.sub;
  const user = await prisma.user.findUnique({ where: { id: userId }, select: { passwordHash: true, email: true } });
  if (!user || !user.passwordHash || user.passwordHash === "SOCIAL_LOGIN")
    return res.status(400).json({ error: "No password set on this account" });

  const valid = await bcrypt.compare(password, user.passwordHash);
  if (!valid) return res.status(401).json({ error: "Password is incorrect" });

  const existing = await prisma.user.findUnique({ where: { email: newEmail } });
  // Alias eines gebannten Nutzers → gleiche generische Antwort wie bei bestehender E-Mail
  if (existing || await isBannedEmailAlias(newEmail, { excludeUserId: userId })) return res.status(409).json({ error: "Email already in use" });

  // Vorher: Schreiben in ein nicht existierendes User.verificationToken-Feld → Prisma-Fehler (Route war kaputt).
  try {
    await prisma.user.update({
      where: { id: userId },
      data: { email: newEmail, emailCanonical: canonicalEmail(newEmail), emailVerifiedAt: null },
    });
  } catch (err) {
    if (err?.code === "P2002") return res.status(409).json({ error: "Email already in use" }); // paralleler Wechsel auf dieselbe Adresse
    throw err;
  }

  // Sicherheits-Hinweis an die ALTE Adresse (immer; ein Fehler blockiert die Aenderung nicht)
  try {
    const notice = emailChangedNotice({ newEmail });
    await sendMail({ to: user.email, ...notice });
  } catch (err) {
    console.error("PATCH /auth/me/email: security notice failed:", err);
  }

  // Verifizierungs-Mail an die neue Adresse; schlaegt der Versand fehl, ist die Aenderung trotzdem gespeichert →
  // verificationEmailSent=false, die App bietet "Resend" an
  let verificationEmailSent = true;
  try {
    const rawToken = await issueEmailVerificationToken(userId);
    await sendVerificationEmail(newEmail, buildVerifyLink(newEmail, rawToken));
  } catch (err) {
    verificationEmailSent = false;
    console.error("PATCH /auth/me/email: verification mail failed:", err);
  }
  return res.json({ ok: true, verificationEmailSent });
  } catch (err) {
    console.error("PATCH /auth/me/email error:", err);
    return res.status(500).json({ error: "Internal server error" });
  }
});

// DELETE /auth/me
router.delete("/me", requireAuth, async (req, res) => {
  const userId = req.auth.sub;
  try {
    await prisma.user.delete({ where: { id: userId } });
    return res.json({ ok: true });
  } catch (err) {
    console.error("DELETE /auth/me error:", err);
    return res.status(500).json({ error: "Could not delete account" });
  }
});

router.post("/set-password", requireAuth, async (req, res) => {
  const parsed = setPasswordSchema.safeParse(req.body);
  if (!parsed.success) {
    return res.status(400).json({ error: parsed.error.errors[0].message });
  }

  const userId = req.auth.sub;
  const user = await prisma.user.findUnique({
    where: { id: userId },
    select: { id: true, passwordHash: true },
  });

  if (!user) return res.status(401).json({ error: "User not found" });

  if (user.passwordHash !== "SOCIAL_LOGIN") {
    return res.status(409).json({ error: "Account already has a password. Use change-password instead." });
  }

  const newHash = await bcrypt.hash(parsed.data.newPassword, 12);
  await prisma.$transaction([
    prisma.user.update({ where: { id: userId }, data: { passwordHash: newHash } }),
    prisma.userSession.updateMany({ where: { userId }, data: { reauthAt: null } }), // Step-up verfaellt
  ]);

  return res.json({ ok: true });
});


//Helper Funktionen
function buildVerifyLink(email, rawToken) {
  const base = process.env.PUBLIC_API_BASE_URL || "http://localhost:3000";
  const scheme = process.env.APP_SCHEME || "swipeshift";

  // ✅ Email klickt auf HTTPS endpoint (besser), der danach in die App zurückleiten kann
  // Endpoint: GET /auth/verify-email?token=...&email=...
  return `${base}/auth/verify-email?token=${rawToken}&email=${encodeURIComponent(email)}&redirect=${encodeURIComponent(`${scheme}://email-verified`)}`;
}

async function issueEmailVerificationToken(userId) {
  const rawToken = crypto.randomBytes(32).toString("hex");
  const tokenHash = crypto.createHash("sha256").update(rawToken).digest("hex");
  const expiresAt = new Date(Date.now() + 1000 * 60 * 60 * 24); // 24h

  // alte Tokens invalidieren
  await prisma.emailVerificationToken.updateMany({
    where: { userId, usedAt: null },
    data: { usedAt: new Date() },
  });

  await prisma.emailVerificationToken.create({
    data: { userId, tokenHash, expiresAt },
  });

  return rawToken;
}

async function sendVerificationEmail(email, verifyLink) {
  const subject = "Verify your email for SwipeShift";
  const text = `Verify your email by opening this link: ${verifyLink}`;
  const html = `
    <div style="font-family: -apple-system, system-ui, Arial; line-height: 1.4">
      <h2>Verify your email</h2>
      <p>Click the button below to verify your email for SwipeShift.</p>
      <p>
        <a href="${verifyLink}"
           style="display:inline-block;padding:12px 16px;border-radius:10px;
                  background:#2563eb;color:#fff;text-decoration:none;font-weight:600">
          Verify Email
        </a>
      </p>
      <p style="color:#666;font-size:12px">
        If you didn’t request this, you can ignore this email.
      </p>
    </div>
  `;

  await sendMail({ to: email, subject, html, text });
}


module.exports = router;
