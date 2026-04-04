-- clients テーブルに authenticated ユーザー用の UPDATE ポリシーを追加
-- completeRegistration() で upsert を使用できるよう、認証済みユーザーが自身のレコードを更新可能にする

-- 既存のポリシーがあれば削除
DROP POLICY IF EXISTS "clients_update_own" ON "public"."clients";

-- 認証済みユーザーが自分のクライアントレコードのみ更新できるポリシー
CREATE POLICY "clients_update_own"
ON "public"."clients"
FOR UPDATE
TO authenticated
USING (client_id = auth.uid())
WITH CHECK (client_id = auth.uid());
