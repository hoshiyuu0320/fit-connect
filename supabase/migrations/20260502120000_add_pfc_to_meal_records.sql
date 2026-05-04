-- 食事記録に PFC と AI 推定情報を追加
ALTER TABLE "public"."meal_records"
  ADD COLUMN "protein_g"       numeric CHECK (protein_g IS NULL OR protein_g >= 0),
  ADD COLUMN "fat_g"           numeric CHECK (fat_g     IS NULL OR fat_g     >= 0),
  ADD COLUMN "carbs_g"         numeric CHECK (carbs_g   IS NULL OR carbs_g   >= 0),
  ADD COLUMN "estimated_by_ai" boolean DEFAULT false NOT NULL,
  ADD COLUMN "ai_foods"        jsonb;

COMMENT ON COLUMN "public"."meal_records"."protein_g" IS 'タンパク質(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."fat_g" IS '脂質(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."carbs_g" IS '炭水化物(g)。AI推定 or 手動入力';
COMMENT ON COLUMN "public"."meal_records"."estimated_by_ai" IS 'AI推定で作成された記録か';
COMMENT ON COLUMN "public"."meal_records"."ai_foods" IS '食品ごとの推定内訳: [{name, calories, protein_g, fat_g, carbs_g}]';
