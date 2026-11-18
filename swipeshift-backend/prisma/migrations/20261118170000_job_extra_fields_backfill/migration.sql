-- Alte Jobs haben NULL in den neuen Listenfeldern → auf leere Arrays setzen
UPDATE "Job" SET "requiredSkills" = '{}' WHERE "requiredSkills" IS NULL;
UPDATE "Job" SET "physicalRequirements" = '{}' WHERE "physicalRequirements" IS NULL;
UPDATE "Job" SET "certifications" = '{}' WHERE "certifications" IS NULL;
