-- AlterTable
ALTER TABLE "User" ADD COLUMN     "lastSeenAt" TIMESTAMP(3);

-- AlterTable
ALTER TABLE "Conversation" ADD COLUMN     "employerLastReadAt" TIMESTAMP(3),
ADD COLUMN     "employerTypingAt" TIMESTAMP(3),
ADD COLUMN     "workerLastReadAt" TIMESTAMP(3),
ADD COLUMN     "workerTypingAt" TIMESTAMP(3);
