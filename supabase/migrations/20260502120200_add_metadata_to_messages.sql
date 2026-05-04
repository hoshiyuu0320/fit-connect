-- メッセージに任意の構造化メタデータを持たせる（AI推定結果など）
ALTER TABLE "public"."messages"
  ADD COLUMN "metadata" jsonb;

COMMENT ON COLUMN "public"."messages"."metadata" IS 'メッセージ付随メタデータ。例: meal_estimation = {foods, calories, protein_g, fat_g, carbs_g}';
