-- AlterTable
ALTER TABLE "Job" ADD COLUMN "requiredSkills" TEXT[],
ADD COLUMN "physicalRequirements" TEXT[],
ADD COLUMN "certifications" TEXT[],
ADD COLUMN "educationLevel" TEXT,
ADD COLUMN "workAuthorizationRequired" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "urgency" TEXT NOT NULL DEFAULT 'normal',
ADD COLUMN "locationType" TEXT NOT NULL DEFAULT 'single',
ADD COLUMN "breakIncluded" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "breakMinutes" INTEGER,
ADD COLUMN "sameDayPay" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "tipsIncluded" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "repeatWork" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "bonusAvailable" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "bonusDescription" TEXT,
ADD COLUMN "cancellationPolicy" TEXT,
ADD COLUMN "cancellationNotes" TEXT,
ADD COLUMN "jobNotes" TEXT,
ADD COLUMN "instantMatch" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN "termsAcceptedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Apply" ADD COLUMN "autoAccepted" BOOLEAN NOT NULL DEFAULT false;
