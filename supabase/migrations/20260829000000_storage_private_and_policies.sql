-- =============================================================================
-- Migration: storage_private_and_policies
-- フェーズ8.2（カタログ cat7 課題2 施策2-A / 課題8）:
--   Storage 4バケットの private 化 + storage.objects ポリシー再編
--
-- 仕様出典: docs/tasks/2026-08-29-storage-private-plan.md「Storage ポリシー最終形」
--
-- 方針:
--   - リモートには手動作成された同名ポリシーが存在するため、存在チェック付き
--     DO ブロック（20260710010002 パターン）ではなく DROP POLICY IF EXISTS →
--     CREATE POLICY で冪等化する（再実行しても最終形に収束する）
--   - message-photos の UPDATE/DELETE own-folder ポリシー
--     （"Users can update own images" / "Users can delete own images"、
--       20260102075114）と client-avatars の書込系3本
--     （"Users can upload/update/delete own avatar"、20260204100000）は
--     現状のまま維持し、本 migration では一切触れない
--
-- フォルダ規約（storage.foldername(name) = パス階層の配列。最終要素=ファイル名は含まない）:
--   - message-photos: Mobile = {clientUid}/… ・ {clientUid}/ai/…
--                     Web    = {trainerUid}/{clientUid}/…
--   - client-avatars: {clientUid}/…
--   - profile-images: {trainerUid}/…
--   - client-notes:   {trainerUid}/{clientUid}/…
--
-- 注意: private 化後、DB 保存値はフルURL→バケット相対パスへ移行する
--   （20260829000200_normalize_storage_urls_to_paths.sql）。表示は署名URL
--   （TTL 3600秒）を Web/Mobile の表示ヘルパーが発行する。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 4バケットの private 化
--    バケット行は既存 migration が INSERT（ON CONFLICT DO NOTHING）済みのため、
--    public フラグの変更は UPDATE 文で行う。
-- -----------------------------------------------------------------------------
UPDATE storage.buckets
SET public = false
WHERE id IN ('message-photos', 'client-avatars', 'client-notes', 'profile-images');

-- -----------------------------------------------------------------------------
-- 1. message-photos
--    - 全公開 SELECT（"Public read access for message photos"）を廃止し、
--      当事者（本人・担当トレーナー・担当クライアント）限定の SELECT に置換
--    - フォルダ制限の無かった INSERT（"Authenticated users can upload images"）を
--      自フォルダ限定に置換（他人フォルダへのアップロード封鎖 = タスク8.2 明示項目）
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Public read access for message photos" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload images" ON storage.objects;
DROP POLICY IF EXISTS "message_photos_select_participants" ON storage.objects;
DROP POLICY IF EXISTS "message_photos_insert_own_folder" ON storage.objects;

CREATE POLICY "message_photos_select_participants"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'message-photos'
  AND (
    -- 本人のフォルダ（Mobile: {clientUid}/… と {clientUid}/ai/…、Web: {trainerUid}/…）
    (storage.foldername(name))[1] = auth.uid()::text
    -- 担当トレーナーがクライアントフォルダを閲覧（Mobile アップロード分）
    -- ※ サブクエリ内の無修飾 name は clients.name に解決されてしまうため
    --    必ず objects.name と修飾すること（RLS テストで検出した実バグ）
    OR EXISTS (
      SELECT 1 FROM public.clients c
      WHERE c.client_id::text = (storage.foldername(objects.name))[1]
        AND c.trainer_id = auth.uid()
    )
    -- クライアントが担当トレーナーの {trainerUid}/{clientUid}/… を閲覧（Web アップロード分）
    OR EXISTS (
      SELECT 1 FROM public.clients c
      WHERE c.trainer_id::text = (storage.foldername(objects.name))[1]
        AND c.client_id = auth.uid()
        AND (storage.foldername(objects.name))[2] = auth.uid()::text
    )
  )
);

CREATE POLICY "message_photos_insert_own_folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'message-photos'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- -----------------------------------------------------------------------------
-- 2. client-avatars
--    全公開 SELECT（"Public avatar access"）を廃止し、本人 + 担当トレーナー限定に置換。
--    書込系3本（upload/update/delete own avatar）は既存維持。
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Public avatar access" ON storage.objects;
DROP POLICY IF EXISTS "client_avatars_select_own_or_trainer" ON storage.objects;

CREATE POLICY "client_avatars_select_own_or_trainer"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'client-avatars'
  AND (
    -- 本人のアバター
    (storage.foldername(name))[1] = auth.uid()::text
    -- 担当トレーナーがクライアントのアバターを閲覧
    -- ※ サブクエリ内では必ず objects.name と修飾（clients.name への誤解決防止）
    OR EXISTS (
      SELECT 1 FROM public.clients c
      WHERE c.client_id::text = (storage.foldername(objects.name))[1]
        AND c.trainer_id = auth.uid()
    )
  )
);

-- -----------------------------------------------------------------------------
-- 3. profile-images
--    - 全公開 SELECT（"Profile images are publicly accessible"）を廃止し、
--      authenticated 全体の SELECT に置換。
--      （登録フロー（QR）で clients 行の作成前にトレーナーアバターの表示が必要。
--        trainers 全行が authenticated に読める既存 RLS と整合する緩和）
--    - 欠落していた DELETE own-folder ポリシーを新設
--    - INSERT/UPDATE（"Trainers can upload/update own profile images"）は既存維持
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "Profile images are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "profile_images_select_authenticated" ON storage.objects;
DROP POLICY IF EXISTS "profile_images_delete_own" ON storage.objects;

CREATE POLICY "profile_images_select_authenticated"
ON storage.objects
FOR SELECT
TO authenticated
USING (bucket_id = 'profile-images');

CREATE POLICY "profile_images_delete_own"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'profile-images'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- -----------------------------------------------------------------------------
-- 4. client-notes
--    旧3本（trainers_read_notes / trainers_upload_notes / trainers_delete_notes）は
--    authenticated 全員が全フォルダを読み書き削除できる重大不備のため全て廃止し、
--    フォルダ規約 {trainerUid}/{clientUid}/… に基づく当事者限定ポリシーへ置換。
--    UPDATE ポリシーは欠落していたため新設。
-- -----------------------------------------------------------------------------
DROP POLICY IF EXISTS "trainers_read_notes" ON storage.objects;
DROP POLICY IF EXISTS "trainers_upload_notes" ON storage.objects;
DROP POLICY IF EXISTS "trainers_delete_notes" ON storage.objects;
DROP POLICY IF EXISTS "client_notes_select_participants" ON storage.objects;
DROP POLICY IF EXISTS "client_notes_insert_own_folder" ON storage.objects;
DROP POLICY IF EXISTS "client_notes_update_own_folder" ON storage.objects;
DROP POLICY IF EXISTS "client_notes_delete_own_folder" ON storage.objects;

CREATE POLICY "client_notes_select_participants"
ON storage.objects
FOR SELECT
TO authenticated
USING (
  bucket_id = 'client-notes'
  AND (
    -- 担当トレーナー（フォルダ1階層目）
    (storage.foldername(name))[1] = auth.uid()::text
    -- 当該クライアント（フォルダ2階層目）
    OR (storage.foldername(name))[2] = auth.uid()::text
  )
);

CREATE POLICY "client_notes_insert_own_folder"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'client-notes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "client_notes_update_own_folder"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'client-notes'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'client-notes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

CREATE POLICY "client_notes_delete_own_folder"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'client-notes'
  AND (storage.foldername(name))[1] = auth.uid()::text
);
