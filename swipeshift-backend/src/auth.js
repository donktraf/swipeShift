// src/auth.js
const jwt = require("jsonwebtoken");
const { shouldTouchLastSeen } = require("./utils/chatPresence");

// In-Memory-Drosselung fuer lastSeenAt/lastActiveAt-Updates (pro Prozess), damit nicht jeder
// Request einen DB-Write ausloest. Verlust bei Neustart ist unkritisch.
const lastSeenTouches = new Map();
const sessionTouches = new Map();

// Lazy require, um Ladezyklen zu vermeiden
function db() {
  return require("./prisma.js").prisma;
}

function touchLastSeen(userId) {
  const now = Date.now();
  if (!shouldTouchLastSeen(lastSeenTouches.get(userId), now)) return;
  lastSeenTouches.set(userId, now);
  // Fire-and-forget, Fehler blockieren nie den Request
  db()
    .user.update({ where: { id: userId }, data: { lastSeenAt: new Date(now) } })
    .catch(() => lastSeenTouches.delete(userId));
}

function touchSession(sessionId) {
  const now = Date.now();
  if (!shouldTouchLastSeen(sessionTouches.get(sessionId), now)) return;
  sessionTouches.set(sessionId, now);
  db()
    .userSession.update({ where: { id: sessionId }, data: { lastActiveAt: new Date(now) } })
    .catch(() => sessionTouches.delete(sessionId));
}

const JWT_SECRET = process.env.JWT_SECRET || "dev_secret_change_me";
const JWT_EXPIRES_IN = "7d";
const SESSION_TTL_MS = 7 * 24 * 60 * 60 * 1000; // identisch zu JWT_EXPIRES_IN

// Jeder Token gehoert zu genau einer UserSession (sid). Ohne sid ist ein Token ungueltig.
function signToken(user, sessionId) {
  return jwt.sign(
    { sub: user.id, role: user.role, email: user.email, sid: sessionId },
    JWT_SECRET,
    { expiresIn: JWT_EXPIRES_IN }
  );
}

function sessionError(res) {
  return res.status(401).json({
    error: "Your session has ended. Please sign in again.",
    code: "SESSION_REVOKED",
  });
}

async function requireAuth(req, res, next) {
  const header = req.headers.authorization || "";
  const [type, token] = header.split(" ");

  if (type !== "Bearer" || !token) {
    return res.status(401).json({ error: "Missing or invalid Authorization header" });
  }

  let payload;
  try {
    payload = jwt.verify(token, JWT_SECRET);
  } catch (err) {
    return res.status(401).json({ error: "Invalid token" });
  }

  // Tokens von vor Einfuehrung der Sessions haben kein sid → einmal neu einloggen
  if (!payload?.sid || !payload?.sub) return sessionError(res);

  let session;
  try {
    session = await db().userSession.findUnique({
      where: { id: payload.sid },
      select: { userId: true, revokedAt: true, expiresAt: true },
    });
  } catch (err) {
    console.error("requireAuth session lookup failed:", err);
    return res.status(500).json({ error: "Internal server error" });
  }

  if (
    !session ||
    session.userId !== payload.sub ||
    session.revokedAt ||
    new Date(session.expiresAt).getTime() <= Date.now()
  ) {
    return sessionError(res);
  }

  req.auth = payload; // { sub, role, email, sid, iat, exp }
  touchLastSeen(payload.sub);
  touchSession(payload.sid);
  next();
}

module.exports = { signToken, requireAuth, JWT_SECRET, SESSION_TTL_MS };
