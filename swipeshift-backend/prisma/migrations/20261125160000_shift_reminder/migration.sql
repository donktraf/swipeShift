-- CreateTable
CREATE TABLE "ShiftReminder" (
    "id" TEXT NOT NULL,
    "applyId" TEXT NOT NULL,
    "shiftId" TEXT NOT NULL,
    "kind" TEXT NOT NULL,
    "sentAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "ShiftReminder_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ShiftReminder_applyId_shiftId_kind_key" ON "ShiftReminder"("applyId", "shiftId", "kind");

-- AddForeignKey
ALTER TABLE "ShiftReminder" ADD CONSTRAINT "ShiftReminder_applyId_fkey" FOREIGN KEY ("applyId") REFERENCES "Apply"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- Altbestand: Apply.reminderSentAt bleibt bestehen (wird nur noch gelesen, siehe notifySchedule.dueShiftReminders).
