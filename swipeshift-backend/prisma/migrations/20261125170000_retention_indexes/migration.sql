-- Indizes fuer die Retention-Purge-Abfragen (src/retention.js)
CREATE INDEX "UserSession_expiresAt_idx" ON "UserSession"("expiresAt");
CREATE INDEX "UserSession_revokedAt_idx" ON "UserSession"("revokedAt");
CREATE INDEX "TwoFactorCode_expiresAt_idx" ON "TwoFactorCode"("expiresAt");
CREATE INDEX "UserReport_status_resolvedAt_idx" ON "UserReport"("status", "resolvedAt");
CREATE INDEX "ModerationAction_createdAt_idx" ON "ModerationAction"("createdAt");
