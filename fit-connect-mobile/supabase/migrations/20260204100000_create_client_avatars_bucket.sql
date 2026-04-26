-- client-avatars バケットを作成（プロフィール画像用）
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'client-avatars',
  'client-avatars',
  true,
  5242880,  -- 5MB
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/heic']
)
ON CONFLICT (id) DO NOTHING;

-- RLSポリシー: 認証済みユーザーは自分のフォルダにのみアップロード可能
CREATE POLICY "Users can upload own avatar"
ON storage.objects
FOR INSERT
TO authenticated
WITH CHECK (
  bucket_id = 'client-avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- RLSポリシー: 認証済みユーザーは自分のアバターのみ更新可能
CREATE POLICY "Users can update own avatar"
ON storage.objects
FOR UPDATE
TO authenticated
USING (
  bucket_id = 'client-avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
)
WITH CHECK (
  bucket_id = 'client-avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- RLSポリシー: 認証済みユーザーは自分のアバターのみ削除可能
CREATE POLICY "Users can delete own avatar"
ON storage.objects
FOR DELETE
TO authenticated
USING (
  bucket_id = 'client-avatars'
  AND (storage.foldername(name))[1] = auth.uid()::text
);

-- RLSポリシー: 公開読み取り可能
CREATE POLICY "Public avatar access"
ON storage.objects
FOR SELECT
TO public
USING (bucket_id = 'client-avatars');
