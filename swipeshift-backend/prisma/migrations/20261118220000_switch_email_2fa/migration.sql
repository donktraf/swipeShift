-- 2FA-Methodenwechsel TOTP -> E-Mail: eigener Code-Zweck + Bindung des Mail-Codes an die Sitzung
ALTER TYPE "TwoFactorPurpose" ADD VALUE 'switch_email';
ALTER TABLE "TwoFactorCode" ADD COLUMN "sessionId" TEXT;
