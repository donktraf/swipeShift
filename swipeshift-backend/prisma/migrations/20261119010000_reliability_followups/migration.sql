-- AlterTable
ALTER TABLE "Apply" ADD COLUMN     "noShowNotifiedAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Job" ADD COLUMN     "attendanceReminderSentAt" TIMESTAMP(3);
