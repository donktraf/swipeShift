-- AlterTable
ALTER TABLE "Apply" ADD COLUMN "shiftIds" TEXT[] DEFAULT ARRAY[]::TEXT[];

-- AlterTable
ALTER TABLE "User" ADD COLUMN "emailCanonical" TEXT;

-- CreateIndex
CREATE INDEX "User_emailCanonical_idx" ON "User"("emailCanonical");

-- Alle JSON-Zugriffe sind auswertungsreihenfolge-sicher: nur ein JSON-ARRAY wird zerlegt, alles andere (null, {}, Skalare)
-- gilt als leere Liste; Nicht-Objekt-Elemente ([1,2]) werden ignoriert bzw. unveraendert gelassen.

-- Backfill 1: Schichten ohne id bekommen "s<Position ab 1>" (identisch zum Laufzeit-Fallback in utils/shiftBooking.js)
UPDATE "Job" j
SET "shifts" = (
  SELECT COALESCE(
    jsonb_agg(
      CASE
        WHEN jsonb_typeof(e.value) = 'object' AND COALESCE(e.value->>'id', '') = ''
          THEN e.value || jsonb_build_object('id', 's' || e.ord)
        ELSE e.value
      END
      ORDER BY e.ord
    ),
    '[]'::jsonb
  )
  FROM jsonb_array_elements(
    CASE WHEN jsonb_typeof(j."shifts"::jsonb) = 'array' THEN j."shifts"::jsonb ELSE '[]'::jsonb END
  ) WITH ORDINALITY AS e(value, ord)
)
WHERE EXISTS (
  SELECT 1 FROM jsonb_array_elements(
    CASE WHEN jsonb_typeof(j."shifts"::jsonb) = 'array' THEN j."shifts"::jsonb ELSE '[]'::jsonb END
  ) AS x(value)
  WHERE jsonb_typeof(x.value) = 'object' AND COALESCE(x.value->>'id', '') = ''
);

-- Backfill 2: bestehende Bewerbungen buchen bisher implizit ALLE Schichten ihres Jobs → explizit eintragen.
-- Jobs ohne Schicht-Eintraege bleiben leer (= alle, Regel "leer = Altbestand").
UPDATE "Apply" a
SET "shiftIds" = sub.ids
FROM (
  SELECT j."id" AS job_id,
         array_agg(e.value->>'id' ORDER BY e.ord) AS ids
  FROM "Job" j,
       LATERAL jsonb_array_elements(
         CASE WHEN jsonb_typeof(j."shifts"::jsonb) = 'array' THEN j."shifts"::jsonb ELSE '[]'::jsonb END
       ) WITH ORDINALITY AS e(value, ord)
  WHERE jsonb_typeof(e.value) = 'object'
    AND COALESCE(e.value->>'id', '') <> ''
  GROUP BY j."id"
) sub
WHERE a."jobId" = sub.job_id;

UPDATE "Apply" SET "shiftIds" = ARRAY[]::TEXT[] WHERE "shiftIds" IS NULL;

-- Backfill 3: emailCanonical (Spiegel von canonicalEmail() in src/utils/emailCanonical.js):
-- lowercase+trim; +tag entfernen; Gmail: zusaetzlich Punkte entfernen, googlemail.com -> gmail.com.
-- Ist der Rest nach dem Entfernen leer, gilt wie im JS-Code der jeweils vorherige Stand
-- (nur +tag entfernt bzw. unveraendert).
UPDATE "User" u
SET "emailCanonical" = c.canon
FROM (
  SELECT q."id",
    CASE
      WHEN q.dom IS NULL THEN q.e
      WHEN q.dom IN ('gmail.com', 'googlemail.com') THEN
        COALESCE(NULLIF(replace(q.plain, '.', ''), ''), q.plain) || '@gmail.com'
      ELSE q.plain || '@' || q.dom
    END AS canon
  FROM (
    SELECT p."id", p.e, p.dom,
           COALESCE(NULLIF(split_part(p.loc, '+', 1), ''), p.loc) AS plain
    FROM (
      SELECT "id",
             lower(btrim("email")) AS e,
             substring(lower(btrim("email")) from '^(.+)@[^@]+$') AS loc,
             substring(lower(btrim("email")) from '^.+@([^@]+)$') AS dom
      FROM "User"
    ) p
  ) q
) c
WHERE u."id" = c."id";
