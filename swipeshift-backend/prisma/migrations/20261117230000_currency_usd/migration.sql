-- Waehrung EUR -> USD: Bestandstexte umstellen. Alle bekannten Formate haben das Symbol
-- vorangestellt ("€18 / hour"); Betraege selbst bleiben unveraendert (kein Umrechnen).
-- Bewusst NUR payText und shifts (systemerzeugte Texte). Nutzer-Freitexte (Beschreibung, Tasks,
-- Chat, Reviews) werden nicht angefasst, ein "€" dort ist Absicht des Autors.
UPDATE "Job" SET "payText" = replace("payText", '€', '$') WHERE "payText" LIKE '%€%';
-- shifts ist JSONB (siehe 20260329231940_add_job_apply_skip_save)
UPDATE "Job" SET "shifts" = replace("shifts"::text, '€', '$')::jsonb WHERE "shifts"::text LIKE '%€%';
