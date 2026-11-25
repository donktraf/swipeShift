-- CreateTable
CREATE TABLE "DeletedAccount" (
    "id" TEXT NOT NULL,
    "emailCanonicalHash" TEXT NOT NULL,
    "role" TEXT,
    "displayName" TEXT,
    "deletedAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "bannedAt" TIMESTAMP(3),

    CONSTRAINT "DeletedAccount_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "DeletedAccount_emailCanonicalHash_idx" ON "DeletedAccount"("emailCanonicalHash");
