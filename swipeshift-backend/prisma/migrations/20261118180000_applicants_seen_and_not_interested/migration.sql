-- AlterTable
ALTER TABLE "Job" ADD COLUMN     "applicantsSeenAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Skip" ADD COLUMN     "notInterested" BOOLEAN NOT NULL DEFAULT false;
