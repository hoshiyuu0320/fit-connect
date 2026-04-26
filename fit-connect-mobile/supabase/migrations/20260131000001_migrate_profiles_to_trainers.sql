-- ================================================
-- Migration: profiles → trainers (Idempotent)
-- ================================================

-- Step 1: trainersテーブル作成（存在しない場合のみ）
CREATE TABLE IF NOT EXISTS "public"."trainers" (
    "id" "uuid" NOT NULL,
    "name" "text" NOT NULL DEFAULT '',
    "email" "text",
    "profile_image_url" "text",
    "created_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    "updated_at" TIMESTAMPTZ DEFAULT NOW() NOT NULL,
    CONSTRAINT "trainers_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "trainers_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE
);

-- Step 2: データ移行（profilesが存在する場合のみ）
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'profiles') THEN
    INSERT INTO "public"."trainers" (id, name, email, profile_image_url, created_at, updated_at)
    SELECT id, COALESCE(name, ''), email, profile_image_url, NOW(), NOW()
    FROM "public"."profiles"
    WHERE role = 'trainer'
    ON CONFLICT (id) DO NOTHING;
  END IF;
END $$;

-- Step 3: clientsテーブルにemailカラム追加
ALTER TABLE "public"."clients"
ADD COLUMN IF NOT EXISTS "email" TEXT;

COMMENT ON COLUMN "public"."clients"."email" IS 'クライアントのメールアドレス';

-- Step 4: 既存の外部キー制約を削除
ALTER TABLE "public"."clients" DROP CONSTRAINT IF EXISTS "clients_trainer_id_fkey";
ALTER TABLE "public"."sessions" DROP CONSTRAINT IF EXISTS "sessions_trainer_id_fkey";

-- Step 5: 新しい外部キー制約を追加（trainers参照）
-- 制約が存在しない場合のみ追加
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'clients_trainer_id_fkey'
    AND table_name = 'clients'
  ) THEN
    ALTER TABLE "public"."clients"
    ADD CONSTRAINT "clients_trainer_id_fkey"
    FOREIGN KEY ("trainer_id") REFERENCES "public"."trainers"("id") ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.table_constraints
    WHERE constraint_name = 'sessions_trainer_id_fkey'
    AND table_name = 'sessions'
  ) THEN
    ALTER TABLE "public"."sessions"
    ADD CONSTRAINT "sessions_trainer_id_fkey"
    FOREIGN KEY ("trainer_id") REFERENCES "public"."trainers"("id") ON DELETE CASCADE;
  END IF;
END $$;

-- Step 6: RLSポリシー設定
ALTER TABLE "public"."trainers" ENABLE ROW LEVEL SECURITY;

-- ポリシーを再作成（存在する場合は先に削除）
DROP POLICY IF EXISTS "trainers_select_all" ON "public"."trainers";
CREATE POLICY "trainers_select_all"
ON "public"."trainers"
FOR SELECT
USING (true);

DROP POLICY IF EXISTS "trainers_update_own" ON "public"."trainers";
CREATE POLICY "trainers_update_own"
ON "public"."trainers"
FOR UPDATE
USING (id = auth.uid());

DROP POLICY IF EXISTS "trainers_insert_own" ON "public"."trainers";
CREATE POLICY "trainers_insert_own"
ON "public"."trainers"
FOR INSERT
WITH CHECK (id = auth.uid());

-- Step 7: updated_atトリガー作成（関数が存在する場合）
DO $$
BEGIN
  -- トリガーが存在しない場合のみ作成
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_updated_at_column') THEN
    IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_trainers') THEN
      CREATE TRIGGER "set_updated_at_trainers"
      BEFORE UPDATE ON "public"."trainers"
      FOR EACH ROW
      EXECUTE FUNCTION "public"."update_updated_at_column"();
    END IF;
  END IF;
END $$;

-- Step 8: profilesテーブル削除
DROP TABLE IF EXISTS "public"."profiles" CASCADE;
