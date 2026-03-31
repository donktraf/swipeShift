-- CreateTable
CREATE TABLE "Job" (
    "id" TEXT NOT NULL,
    "title" TEXT NOT NULL,
    "company" TEXT NOT NULL,
    "location" TEXT NOT NULL,
    "lat" DOUBLE PRECISION,
    "lng" DOUBLE PRECISION,
    "payAmount" DOUBLE PRECISION,
    "payText" TEXT NOT NULL,
    "startTime" TIMESTAMP(3),
    "endTime" TIMESTAMP(3),
    "shiftText" TEXT NOT NULL DEFAULT '',
    "duration" TEXT,
    "shortInfo" TEXT NOT NULL DEFAULT '',
    "jobDescription" TEXT,
    "tasks" TEXT[],
    "openSpots" INTEGER NOT NULL DEFAULT 1,
    "dressCode" TEXT,
    "languages" TEXT[],
    "experienceLevel" TEXT,
    "minAge" INTEGER,
    "paymentMethod" TEXT,
    "contractType" TEXT,
    "companyRating" DOUBLE PRECISION,
    "replyTime" TEXT,
    "isVerified" BOOLEAN NOT NULL DEFAULT false,
    "tags" TEXT[],
    "logoEmoji" TEXT NOT NULL DEFAULT '🏢',
    "category" TEXT,
    "shifts" JSONB NOT NULL DEFAULT '[]',
    "status" TEXT NOT NULL DEFAULT 'published',
    "employerId" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Job_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Apply" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Apply_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Skip" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Skip_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "Save" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "jobId" TEXT NOT NULL,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "Save_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "Apply_userId_idx" ON "Apply"("userId");

-- CreateIndex
CREATE INDEX "Apply_jobId_idx" ON "Apply"("jobId");

-- CreateIndex
CREATE UNIQUE INDEX "Apply_userId_jobId_key" ON "Apply"("userId", "jobId");

-- CreateIndex
CREATE INDEX "Skip_userId_idx" ON "Skip"("userId");

-- CreateIndex
CREATE INDEX "Skip_jobId_idx" ON "Skip"("jobId");

-- CreateIndex
CREATE UNIQUE INDEX "Skip_userId_jobId_key" ON "Skip"("userId", "jobId");

-- CreateIndex
CREATE INDEX "Save_userId_idx" ON "Save"("userId");

-- CreateIndex
CREATE INDEX "Save_jobId_idx" ON "Save"("jobId");

-- CreateIndex
CREATE UNIQUE INDEX "Save_userId_jobId_key" ON "Save"("userId", "jobId");

-- AddForeignKey
ALTER TABLE "Apply" ADD CONSTRAINT "Apply_jobId_fkey" FOREIGN KEY ("jobId") REFERENCES "Job"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Skip" ADD CONSTRAINT "Skip_jobId_fkey" FOREIGN KEY ("jobId") REFERENCES "Job"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "Save" ADD CONSTRAINT "Save_jobId_fkey" FOREIGN KEY ("jobId") REFERENCES "Job"("id") ON DELETE CASCADE ON UPDATE CASCADE;
