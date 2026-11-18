-- Step-up Re-Auth vor dem Aendern von Auszahlungsdaten: Nachweis pro Sitzung + eigener Code-Zweck
ALTER TYPE "TwoFactorPurpose" ADD VALUE 'reauth';
ALTER TABLE "UserSession" ADD COLUMN "reauthAt" TIMESTAMP(3);
