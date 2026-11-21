-- Backfill: bereits veroeffentlichte/aeltere Jobs bekommen den bisherigen Standardsatz (15 %) eingefroren.
-- Entwuerfe bleiben null (Snapshot erst beim Veroeffentlichen).
UPDATE "Job"
SET "platformFeePercent" = 15
WHERE "status" IN ('published', 'inProgress', 'completed', 'cancelled')
  AND "platformFeePercent" IS NULL;
