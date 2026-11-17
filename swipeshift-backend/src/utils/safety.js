// src/utils/safety.js
// Reine, DB-freie Helper fuer Melden/Blockieren (App-Store Guideline 1.2).

const REPORT_REASONS = ["harassment", "spam", "inappropriate", "safety", "payment", "other"];
const MAX_DETAILS_LENGTH = 1000;

// Prueft Reason (Whitelist) + optionale Details. Gibt { ok, error?, value? } zurueck.
function validateReport({ reason, details } = {}) {
  if (typeof reason !== "string" || !REPORT_REASONS.includes(reason)) {
    return { ok: false, error: "Invalid reason" };
  }
  if (details !== undefined && details !== null && typeof details !== "string") {
    return { ok: false, error: "Invalid details" };
  }
  const trimmed = typeof details === "string" ? details.trim() : "";
  if (trimmed.length > MAX_DETAILS_LENGTH) {
    return { ok: false, error: `Details too long (max ${MAX_DETAILS_LENGTH} characters)` };
  }
  return { ok: true, value: { reason, details: trimmed || null } };
}

// blocks: Liste von { blockerId, blockedId }. Liefert die Sicht von `me` auf `other`.
function blockState(blocks, me, other) {
  const list = Array.isArray(blocks) ? blocks : [];
  return {
    blockedByMe:    list.some(b => b.blockerId === me && b.blockedId === other),
    blockedByOther: list.some(b => b.blockerId === other && b.blockedId === me),
  };
}

// true, wenn einer der beiden den anderen blockiert hat (beide Richtungen).
function isBlockedBetween(blocks, a, b) {
  const s = blockState(blocks, a, b);
  return s.blockedByMe || s.blockedByOther;
}

module.exports = { REPORT_REASONS, MAX_DETAILS_LENGTH, validateReport, blockState, isBlockedBetween };
