// Nach requireAuth verwenden. isAdmin wird bei JEDEM Request frisch aus der DB gelesen (kein JWT-Claim),
// damit ein entzogenes Admin-Recht sofort wirkt. Admin-Rechte werden nur per CLI-Skript vergeben.
const { prisma } = require("../prisma");

async function requireAdmin(req, res, next) {
  try {
    const userId = req.auth?.sub;
    if (!userId) return res.status(401).json({ error: "Unauthorized" });
    const user = await prisma.user.findUnique({ where: { id: userId }, select: { isAdmin: true } });
    if (!user?.isAdmin) return res.status(403).json({ error: "Forbidden", code: "NOT_ADMIN" });
    next();
  } catch (e) {
    console.error("requireAdmin error:", e);
    return res.status(500).json({ error: "Server error" });
  }
}

module.exports = { requireAdmin };
