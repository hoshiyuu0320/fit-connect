-- Allow 'healthkit' as a valid source for weight_records
-- Background: HealthKit sync inserts rows with source='healthkit', but the existing
-- CHECK constraint only permits 'manual' and 'message'. This migration drops the
-- existing constraint and re-adds it with 'healthkit' included.
--
-- Backward compatibility: existing 'manual' / 'message' rows remain valid.

BEGIN;

ALTER TABLE "public"."weight_records"
  DROP CONSTRAINT IF EXISTS "weight_records_source_check";

ALTER TABLE "public"."weight_records"
  ADD CONSTRAINT "weight_records_source_check"
  CHECK ("source" = ANY (ARRAY['manual'::text, 'message'::text, 'healthkit'::text]));

COMMIT;
