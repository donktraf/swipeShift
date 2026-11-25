-- DropIndex
DROP INDEX "DeletedAccount_emailCanonicalHash_idx";

-- AlterTable
ALTER TABLE "DeletedAccount" ADD COLUMN     "appleSubHash" TEXT,
ADD COLUMN     "emailVerified" BOOLEAN NOT NULL DEFAULT false,
ADD COLUMN     "hashVersion" INTEGER NOT NULL DEFAULT 1,
ADD COLUMN     "suspendedUntil" TIMESTAMP(3);

-- CreateIndex
CREATE INDEX "DeletedAccount_emailCanonicalHash_bannedAt_idx" ON "DeletedAccount"("emailCanonicalHash", "bannedAt");

-- CreateIndex
CREATE INDEX "DeletedAccount_appleSubHash_idx" ON "DeletedAccount"("appleSubHash");
