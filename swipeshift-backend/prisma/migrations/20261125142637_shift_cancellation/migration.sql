-- CreateTable
CREATE TABLE "ShiftCancellation" (
    "id" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "shiftId" TEXT NOT NULL,
    "cancelledAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "late" BOOLEAN NOT NULL DEFAULT false,
    "reason" TEXT,

    CONSTRAINT "ShiftCancellation_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "ShiftCancellation_cancelledAt_idx" ON "ShiftCancellation"("cancelledAt");

-- CreateIndex
CREATE UNIQUE INDEX "ShiftCancellation_applyId_shiftId_key" ON "ShiftCancellation"("applyId", "shiftId");

-- AddForeignKey
ALTER TABLE "ShiftCancellation" ADD CONSTRAINT "ShiftCancellation_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;
