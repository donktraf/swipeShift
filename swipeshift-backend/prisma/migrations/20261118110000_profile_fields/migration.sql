-- AlterTable
ALTER TABLE "Worker" ADD COLUMN     "availableTimes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
ADD COLUMN     "experience" JSONB,
ADD COLUMN     "shiftTypes" TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "Employer" ADD COLUMN     "addressLat" DOUBLE PRECISION,
ADD COLUMN     "addressLng" DOUBLE PRECISION,
ADD COLUMN     "postsInMultipleStates" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "publicContactName" TEXT,
ADD COLUMN     "publicContactRole" TEXT,
ADD COLUMN     "remoteFriendly" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "socialLinks" JSONB,
ADD COLUMN     "streetAddress" TEXT,
ADD COLUMN     "tagline" TEXT,
ADD COLUMN     "yearFounded" INTEGER,
ADD COLUMN     "zipCode" TEXT;
