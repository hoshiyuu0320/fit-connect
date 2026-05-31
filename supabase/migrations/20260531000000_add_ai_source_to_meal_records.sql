-- AI推定の入力経路を記録する列を追加
-- 'text'（テキスト推定）/ 'photo'（料理写真）/ 'screenshot:<app名>'（他アプリのスクショ）
-- AI推定でない記録は NULL。<app名> が可変のため CHECK 制約は付けずアプリ層で値を制御する。
ALTER TABLE "public"."meal_records"
  ADD COLUMN "ai_source" text;

COMMENT ON COLUMN "public"."meal_records"."ai_source" IS 'AI推定の入力経路: text / photo / screenshot:<app名>。手動記録は NULL';
