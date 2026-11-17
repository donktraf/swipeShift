-- AlterEnum
ALTER TYPE "TwoFactorPurpose" ADD VALUE IF NOT EXISTS 'totp_enable';

-- AlterTable
ALTER TABLE "UserSession" ADD COLUMN "city" TEXT;

-- AlterTable
ALTER TABLE "User" ADD COLUMN "twoFactorMethod" TEXT,
ADD COLUMN "totpSecretEnc" TEXT,
ADD COLUMN "totpPendingEnc" TEXT,
ADD COLUMN "totpLastStep" INTEGER,
ADD COLUMN "totpPendingAt" TIMESTAMP(3);

-- Bestehende E-Mail-2FA bekommt die Methode explizit
UPDATE "User" SET "twoFactorMethod" = 'email' WHERE "twoFactorEnabled" = true;

-- CreateTable
CREATE TABLE "TwoFactorBackupCode" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "codeHash" TEXT NOT NULL,
    "usedAt" TIMESTAMP(3),
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "TwoFactorBackupCode_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "TwoFactorBackupCode_userId_idx" ON "TwoFactorBackupCode"("userId");

-- AddForeignKey
ALTER TABLE "TwoFactorBackupCode" ADD CONSTRAINT "TwoFactorBackupCode_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- CreateTable
CREATE TABLE "TwoFactorLock" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "ip" TEXT NOT NULL,
    "failedCount" INTEGER NOT NULL DEFAULT 0,
    "firstFailedAt" TIMESTAMP(3) NOT NULL,
    "lockedUntil" TIMESTAMP(3),
    "notifiedAt" TIMESTAMP(3),

    CONSTRAINT "TwoFactorLock_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "TwoFactorLock_userId_ip_key" ON "TwoFactorLock"("userId", "ip");

-- AddForeignKey
ALTER TABLE "TwoFactorLock" ADD CONSTRAINT "TwoFactorLock_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;
