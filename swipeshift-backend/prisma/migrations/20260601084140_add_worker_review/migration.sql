-- CreateTable
CREATE TABLE "WorkerReview" (
    "id" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "employerId" TEXT NOT NULL,
    "workerId" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "communication" INTEGER NOT NULL,
    "paymentFairness" INTEGER NOT NULL,
    "workEnvironment" INTEGER NOT NULL,
    "jobDescriptionAccuracy" INTEGER NOT NULL,
    "overallExperience" INTEGER NOT NULL,
    "comment" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "WorkerReview_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "WorkerReview_applyId_key" ON "WorkerReview"("applyId");

-- CreateIndex
CREATE INDEX "WorkerReview_employerId_idx" ON "WorkerReview"("employerId");

-- CreateIndex
CREATE INDEX "WorkerReview_workerId_idx" ON "WorkerReview"("workerId");

-- CreateIndex
CREATE INDEX "WorkerReview_jobId_idx" ON "WorkerReview"("jobId");

-- AddForeignKey
ALTER TABLE "WorkerReview" ADD CONSTRAINT "WorkerReview_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;
