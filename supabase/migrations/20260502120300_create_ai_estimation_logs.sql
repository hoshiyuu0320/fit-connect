-- AI推定リクエストのログ。Rate limit 判定とコストデバッグ用
CREATE TABLE "public"."ai_estimation_logs" (
  "id"            uuid PRIMARY KEY DEFAULT "gen_random_uuid"(),
  "client_id"     uuid NOT NULL REFERENCES "public"."clients"("client_id") ON DELETE CASCADE,
  "trainer_id"    uuid NOT NULL REFERENCES "public"."trainers"("id") ON DELETE CASCADE,
  "function_name" text NOT NULL,
  "status"        text NOT NULL CHECK ("status" IN ('success', 'error')),
  "error_code"    text,
  "created_at"    timestamptz DEFAULT "now"() NOT NULL
);

CREATE INDEX "idx_ai_logs_client_created"  ON "public"."ai_estimation_logs"("client_id", "created_at" DESC);
CREATE INDEX "idx_ai_logs_trainer_created" ON "public"."ai_estimation_logs"("trainer_id", "created_at" DESC);

ALTER TABLE "public"."ai_estimation_logs" ENABLE ROW LEVEL SECURITY;

-- クライアントは自分のログを SELECT 可能
CREATE POLICY "ai_logs_client_select"
  ON "public"."ai_estimation_logs"
  FOR SELECT
  USING ("client_id" = "auth"."uid"());

-- トレーナーは自分の担当クライアントのログを SELECT 可能
CREATE POLICY "ai_logs_trainer_select"
  ON "public"."ai_estimation_logs"
  FOR SELECT
  USING ("trainer_id" = "auth"."uid"());

-- INSERT は service_role のみ（Edge Function 経由）。明示ポリシーは作らない（RLS有効でanon/authenticatedは弾かれる）
COMMENT ON TABLE "public"."ai_estimation_logs" IS 'AI推定APIのリクエストログ。Rate limit判定とコストデバッグ用';
