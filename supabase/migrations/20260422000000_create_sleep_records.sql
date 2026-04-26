-- Create sleep_records table for sleep data tracking
-- Supports HealthKit/Health Connect integration + manual wakeup rating input

CREATE TABLE IF NOT EXISTS "public"."sleep_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "recorded_date" date NOT NULL,
    "bed_time" timestamp with time zone,
    "wake_time" timestamp with time zone,
    "total_sleep_minutes" integer,
    "deep_minutes" integer,
    "light_minutes" integer,
    "rem_minutes" integer,
    "awake_minutes" integer,
    "wakeup_rating" smallint,
    "source" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sleep_records_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "sleep_records_client_date_unique" UNIQUE ("client_id", "recorded_date"),
    CONSTRAINT "sleep_records_source_check"
      CHECK ("source" = ANY (ARRAY['manual'::text, 'healthkit'::text])),
    CONSTRAINT "sleep_records_wakeup_rating_check"
      CHECK ("wakeup_rating" IS NULL OR "wakeup_rating" IN (1, 2, 3)),
    CONSTRAINT "sleep_records_has_data_check"
      CHECK ("total_sleep_minutes" IS NOT NULL OR "wakeup_rating" IS NOT NULL)
);

ALTER TABLE "public"."sleep_records"
  ADD CONSTRAINT "sleep_records_client_id_fkey"
  FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id")
  ON DELETE CASCADE;

CREATE INDEX "idx_sleep_records_client_date"
  ON "public"."sleep_records"("client_id", "recorded_date" DESC);

CREATE OR REPLACE TRIGGER "set_updated_at"
  BEFORE UPDATE ON "public"."sleep_records"
  FOR EACH ROW EXECUTE FUNCTION "public"."update_updated_at_column"();

ALTER TABLE "public"."sleep_records" ENABLE ROW LEVEL SECURITY;

-- 5 RLS Policies (weight_recordsパターン踏襲)
CREATE POLICY "Clients can view own sleep records"
  ON "public"."sleep_records" FOR SELECT
  USING ("client_id" = "auth"."uid"());

CREATE POLICY "Clients can insert own sleep records"
  ON "public"."sleep_records" FOR INSERT
  WITH CHECK ("client_id" = "auth"."uid"());

CREATE POLICY "Clients can update own sleep records"
  ON "public"."sleep_records" FOR UPDATE
  USING ("client_id" = "auth"."uid"())
  WITH CHECK ("client_id" = "auth"."uid"());

CREATE POLICY "Clients can delete own sleep records"
  ON "public"."sleep_records" FOR DELETE
  USING ("client_id" = "auth"."uid"());

CREATE POLICY "sleep_records_trainer_select"
  ON "public"."sleep_records" FOR SELECT
  USING (
    "client_id" IN (
      SELECT "client_id" FROM "public"."clients"
      WHERE "trainer_id" = "auth"."uid"()
    )
  );
