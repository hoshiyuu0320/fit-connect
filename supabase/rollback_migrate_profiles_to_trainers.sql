-- ================================================
-- Rollback: trainers → profiles
-- ================================================

-- Step 1: profilesテーブル再作成
CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "name" "text",
    "email" "text",
    "role" "text",
    "profile_image_url" "text",
    CONSTRAINT "profiles_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE
);

-- Step 2: trainersからprofilesへデータ復元
INSERT INTO "public"."profiles" (id, name, email, role, profile_image_url)
SELECT id, name, email, 'trainer', profile_image_url
FROM "public"."trainers"
ON CONFLICT (id) DO NOTHING;

-- Step 3: 外部キー制約を元に戻す
ALTER TABLE "public"."clients" DROP CONSTRAINT IF EXISTS "clients_trainer_id_fkey";
ALTER TABLE "public"."sessions" DROP CONSTRAINT IF EXISTS "sessions_trainer_id_fkey";

ALTER TABLE "public"."clients"
ADD CONSTRAINT "clients_trainer_id_fkey"
FOREIGN KEY ("trainer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

ALTER TABLE "public"."sessions"
ADD CONSTRAINT "sessions_trainer_id_fkey"
FOREIGN KEY ("trainer_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;

-- Step 4: clientsのemailカラム削除
ALTER TABLE "public"."clients" DROP COLUMN IF EXISTS "email";

-- Step 5: trainersテーブル削除
DROP TABLE IF EXISTS "public"."trainers" CASCADE;

-- Step 6: RLSポリシー復元
ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;

CREATE POLICY "profiles_select_trainer"
ON "public"."profiles"
FOR SELECT
USING (role = 'trainer' OR id = auth.uid());

CREATE POLICY "profiles_insert_own"
ON "public"."profiles"
FOR INSERT
WITH CHECK (id = auth.uid());

CREATE POLICY "profiles_update_own"
ON "public"."profiles"
FOR UPDATE
USING (id = auth.uid());
