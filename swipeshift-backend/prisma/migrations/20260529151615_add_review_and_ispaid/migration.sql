-- AlterTable
ALTER TABLE "Apply" ADD COLUMN     "isPaid" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "Review" (
    "id" TEXT NOT NULL,
    "employerId" TEXT NOT NULL,
    "workerId" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "communication" INTEGER NOT NULL,
    "teamwork" INTEGER NOT NULL,
    "reliability" INTEGER NOT NULL,
    "underPressure" INTEGER NOT NULL,
    "comment" TEXT,
    "wouldRehire" BOOLEAN NOT NULL DEFAULT true,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Review_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "Review_applyId_key" ON "Review"("applyId");

-- CreateIndex
CREATE INDEX "Review_employerId_idx" ON "Review"("employerId");

-- CreateIndex
CREATE INDEX "Review_workerId_idx" ON "Review"("workerId");

-- CreateIndex
CREATE INDEX "Review_jobId_idx" ON "Review"("jobId");

-- AddForeignKey
ALTER TABLE "Review" ADD CONSTRAINT "Review_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;
