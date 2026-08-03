-- AlterTable
ALTER TABLE "Employer" ADD COLUMN     "businessAreas" TEXT[],
ADD COLUMN     "companyEmail" TEXT,
ADD COLUMN     "companyPhone" TEXT,
ADD COLUMN     "jobTitle" TEXT,
ADD COLUMN     "locations" TEXT[],
ADD COLUMN     "managerRole" TEXT,
ADD COLUMN     "primaryHiringLocation" TEXT,
ADD COLUMN     "teamMembers" JSONB;
