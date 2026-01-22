const { prisma } = require("../prisma");

async function requireVerifiedEmail(req, res, next) {
  try {
    const userId = req.auth?.sub;
    if (!userId) return res.status(401).json({ error: "Unauthorized" });

    const user = await prisma.user.findUnique({
      where: { id: userId },
      select: { emailVerifiedAt: true },
    });

    if (!user?.emailVerifiedAt) {
      return res.status(403).json({
        error: "EMAIL_NOT_VERIFIED",
        message: "Please verify your email to use this feature.",
      });
    }

    next();
  } catch (e) {
    return res.status(500).json({ error: "Server error" });
  }
}

module.exports = { requireVerifiedEmail };