-- Auszahlung wechselt von IBAN auf US-Bankdaten: alte, unverschluesselte IBANs aus User.settings (jsonb) entfernen.
UPDATE "User"
SET "settings" = "settings" #- '{payout,iban}'
WHERE "settings" #> '{payout,iban}' IS NOT NULL;
