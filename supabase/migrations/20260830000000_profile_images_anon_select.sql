-- =============================================================================
-- profile-images: anon SELECT ポリシー追加（フェーズ8.2 フォローアップ）
--
-- 背景: 登録フロー（QR → TrainerConfirmScreen）はログイン前に到達するため、
-- anon ロールで profile-images の createSignedUrl（storage.objects の SELECT）が
-- 必要。20260829000000 の private 化で SELECT を authenticated 限定にした結果、
-- ログイン前のトレーナーアバター表示が回帰していた。
-- 旧 public 状態でも全世界読み取り可だった実質公開情報のため、anon に SELECT を
-- 許可して回帰を解消する（client-avatars 等の他バケットは authenticated 限定のまま）。
-- 既存の profile_images_select_authenticated はそのまま維持する。
-- =============================================================================

DROP POLICY IF EXISTS "profile_images_select_anon" ON storage.objects;

CREATE POLICY "profile_images_select_anon"
ON storage.objects
FOR SELECT
TO anon
USING (bucket_id = 'profile-images');
