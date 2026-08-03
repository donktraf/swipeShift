-- AlterTable
ALTER TABLE "Worker" ADD COLUMN     "availableForSameDay" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "maxTravelDistance" INTEGER NOT NULL DEFAULT 10,
ADD COLUMN     "payRangeMax" DOUBLE PRECISION,
ADD COLUMN     "payRangeMin" DOUBLE PRECISION,
ADD COLUMN     "phone" TEXT,
ADD COLUMN     "preferredCategories" TEXT[],
ADD COLUMN     "skills" JSONB,
ADD COLUMN     "transport" TEXT NOT NULL DEFAULT 'car',
ADD COLUMN     "willingToRelocate" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "workAuthorization" BOOLEAN NOT NULL DEFAULT false;
