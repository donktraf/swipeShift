-- AlterTable
ALTER TABLE "Review" ADD COLUMN     "workQuality" INTEGER,
ADD COLUMN     "topWorker" BOOLEAN NOT NULL DEFAULT false;

-- AlterTable
ALTER TABLE "WorkerReview" ADD COLUMN     "wouldWorkAgain" BOOLEAN;

-- CreateTable
CREATE TABLE "ReviewDraft" (
    "id" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "employerId" TEXT NOT NULL,
    "data" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ReviewDraft_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ReviewDraft_applyId_key" ON "ReviewDraft"("applyId");

-- CreateIndex
CREATE INDEX "ReviewDraft_employerId_idx" ON "ReviewDraft"("employerId");

-- AddForeignKey
ALTER TABLE "ReviewDraft" ADD CONSTRAINT "ReviewDraft_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;
