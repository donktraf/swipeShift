-- Job.startTime/endTime = fruehester Start / spaetestes Ende ueber ALLE Schichten (bisher: nur die erste Schicht).
-- Nur Jobs, deren shifts-JSON ein Array mit gueltigen ISO-Zeiten (Z oder Offset, Ende > Start) enthaelt; sonst unveraendert.
-- Array-Guard wie in der vorherigen Migration (auswertungsreihenfolge-sicher). timestamp(3) ist UTC.
UPDATE "Job" j
SET "startTime" = s.min_start,
    "endTime"   = s.max_end
FROM (
  SELECT t.job_id, MIN(t.st) AS min_start, MAX(t.en) AS max_end
  FROM (
    SELECT j2."id" AS job_id,
           CASE WHEN (e.value->>'startTimeISO') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$'
                THEN ((e.value->>'startTimeISO')::timestamptz AT TIME ZONE 'UTC') END AS st,
           CASE WHEN (e.value->>'endTimeISO') ~ '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?(Z|[+-]\d{2}:?\d{2})$'
                THEN ((e.value->>'endTimeISO')::timestamptz AT TIME ZONE 'UTC') END AS en
    FROM "Job" j2,
         LATERAL jsonb_array_elements(
           CASE WHEN jsonb_typeof(j2."shifts"::jsonb) = 'array' THEN j2."shifts"::jsonb ELSE '[]'::jsonb END
         ) AS e(value)
    WHERE jsonb_typeof(e.value) = 'object'
  ) t
  WHERE t.en > t.st
  GROUP BY t.job_id
) s
WHERE j."id" = s.job_id;
