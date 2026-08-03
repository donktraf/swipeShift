-- CreateTable
CREATE TABLE "SavedApplicant" (
    "id" TEXT NOT NULL,
    "employerId" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "SavedApplicant_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "SavedApplicant_applyId_key" ON "SavedApplicant"("applyId");

-- CreateIndex
CREATE INDEX "SavedApplicant_employerId_idx" ON "SavedApplicant"("employerId");

-- CreateIndex
CREATE UNIQUE INDEX "SavedApplicant_employerId_applyId_key" ON "SavedApplicant"("employerId", "applyId");

-- AddForeignKey
ALTER TABLE "SavedApplicant" ADD CONSTRAINT "SavedApplicant_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;
