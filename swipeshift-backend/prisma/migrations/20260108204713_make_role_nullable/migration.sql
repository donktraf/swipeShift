-- CreateEnum
CREATE TYPE "OnboardingStatus" AS ENUM ('pendingRole', 'pendingProfile', 'complete');

-- AlterTable
ALTER TABLE "User" ADD COLUMN     "onboarding" "OnboardingStatus" NOT NULL DEFAULT 'pendingRole',
ALTER COLUMN "role" DROP NOT NULL;
