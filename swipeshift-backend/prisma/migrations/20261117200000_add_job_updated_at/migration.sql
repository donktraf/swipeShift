-- AlterTable
ALTER TABLE "Job" ADD COLUMN     "updatedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP;

-- Bestehende Jobs: updatedAt = createdAt statt Migrationszeitpunkt
UPDATE "Job" SET "updatedAt" = "createdAt";
