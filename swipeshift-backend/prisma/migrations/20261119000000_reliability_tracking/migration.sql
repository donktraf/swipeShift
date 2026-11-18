-- AlterTable
ALTER TABLE "Apply" ADD COLUMN     "attendance" TEXT,
ADD COLUMN     "attendanceSetAt" TIMESTAMP(3),
ADD COLUMN     "attendanceSource" TEXT,
ADD COLUMN     "cancelReason" TEXT,
ADD COLUMN     "cancelledAt" TIMESTAMP(3),
ADD COLUMN     "disputeNote" TEXT,
ADD COLUMN     "disputeResolution" TEXT,
ADD COLUMN     "disputeResolvedAt" TIMESTAMP(3),
ADD COLUMN     "disputedAt" TIMESTAMP(3),
ADD COLUMN     "lateCancellation" BOOLEAN NOT NULL DEFAULT false;
