-- Migration: repair_misc_schema_drift
-- 目的: リモートDBへ直接加えられ migration 管理外となっていた以下を追認し、
--       空DBからの `supabase db reset` でリモートと同一形状を再現する。
--       - clients.fcm_token / trainers.fcm_token（schema-drift-facts.md §7）
--       - client_notes のインデックス2本 + trainer系ポリシー4本（同 §5。
--         clients_select_shared_notes は 20260215115338 側で作成済みのため含めない）
--       - storage バケット2件（client-notes / profile-images）+ storage.objects ポリシー6本（同 §8）
--
-- リモートには no-op である理由:
--   - ADD COLUMN は IF NOT EXISTS / CREATE INDEX は IF NOT EXISTS（リモートでは存在済み）
--   - バケットは INSERT ... ON CONFLICT (id) DO NOTHING（既存バケットを一切変更しない）
--   - CREATE POLICY は pg_policies の存在チェック付き DO ブロック（既存ポリシーには触れない）

-- ============================================================
-- 1. fcm_token カラム（§7）
-- ============================================================

ALTER TABLE clients ADD COLUMN IF NOT EXISTS fcm_token text;
ALTER TABLE trainers ADD COLUMN IF NOT EXISTS fcm_token text;

-- ============================================================
-- 2. client_notes のインデックス + trainer系ポリシー（§5）
-- ============================================================

CREATE INDEX IF NOT EXISTS idx_client_notes_client_id ON client_notes(client_id);
CREATE INDEX IF NOT EXISTS idx_client_notes_trainer_id ON client_notes(trainer_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_notes' AND policyname = 'trainers_select_own_notes'
  ) THEN
    CREATE POLICY "trainers_select_own_notes"
      ON client_notes FOR SELECT
      USING (auth.uid() = trainer_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_notes' AND policyname = 'trainers_insert_own_notes'
  ) THEN
    CREATE POLICY "trainers_insert_own_notes"
      ON client_notes FOR INSERT
      WITH CHECK (auth.uid() = trainer_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_notes' AND policyname = 'trainers_update_own_notes'
  ) THEN
    CREATE POLICY "trainers_update_own_notes"
      ON client_notes FOR UPDATE
      USING (auth.uid() = trainer_id);
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_notes' AND policyname = 'trainers_delete_own_notes'
  ) THEN
    CREATE POLICY "trainers_delete_own_notes"
      ON client_notes FOR DELETE
      USING (auth.uid() = trainer_id);
  END IF;
END $$;

-- ============================================================
-- 3. Storage バケット（§8）
-- file_size_limit / allowed_mime_types は未確認のため id/name/public のみ指定し、
-- ON CONFLICT (id) DO NOTHING で既存バケットには一切触れない。
-- ============================================================

INSERT INTO storage.buckets (id, name, public)
VALUES ('client-notes', 'client-notes', true)
ON CONFLICT (id) DO NOTHING;

INSERT INTO storage.buckets (id, name, public)
VALUES ('profile-images', 'profile-images', true)
ON CONFLICT (id) DO NOTHING;

-- ============================================================
-- 4. storage.objects のポリシー6本（§8）
-- ============================================================

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Profile images are publicly accessible'
  ) THEN
    CREATE POLICY "Profile images are publicly accessible"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'profile-images');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Trainers can upload own profile images'
  ) THEN
    CREATE POLICY "Trainers can upload own profile images"
      ON storage.objects FOR INSERT TO authenticated
      WITH CHECK ((bucket_id = 'profile-images') AND ((storage.foldername(name))[1] = (auth.uid())::text));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'Trainers can update own profile images'
  ) THEN
    CREATE POLICY "Trainers can update own profile images"
      ON storage.objects FOR UPDATE TO authenticated
      USING ((bucket_id = 'profile-images') AND ((storage.foldername(name))[1] = (auth.uid())::text));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'trainers_read_notes'
  ) THEN
    CREATE POLICY "trainers_read_notes"
      ON storage.objects FOR SELECT
      USING (bucket_id = 'client-notes');
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'trainers_upload_notes'
  ) THEN
    CREATE POLICY "trainers_upload_notes"
      ON storage.objects FOR INSERT
      WITH CHECK ((bucket_id = 'client-notes') AND (auth.role() = 'authenticated'));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'storage' AND tablename = 'objects'
      AND policyname = 'trainers_delete_notes'
  ) THEN
    CREATE POLICY "trainers_delete_notes"
      ON storage.objects FOR DELETE
      USING ((bucket_id = 'client-notes') AND (auth.role() = 'authenticated'));
  END IF;
END $$;
