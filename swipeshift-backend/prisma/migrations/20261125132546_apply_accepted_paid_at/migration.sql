-- AlterTable
ALTER TABLE "Apply" ADD COLUMN     "acceptedAt" TIMESTAMP(3),
ADD COLUMN     "paidAt" TIMESTAMP(3);

-- Backfill bestehende Daten
UPDATE "Apply" SET "acceptedAt" = COALESCE("respondedAt", "createdAt") WHERE "status" = 'accepted' AND "acceptedAt" IS NULL;
UPDATE "Apply" SET "paidAt" = COALESCE("respondedAt", "createdAt") WHERE "isPaid" = true AND "paidAt" IS NULL;
-- Bestands-User: bisherige Benachrichtigungen gelten als gelesen (sonst Badge-Flut nach dem Update)
UPDATE "User" SET "notificationsSeenAt" = now() WHERE "notificationsSeenAt" IS NULL;
