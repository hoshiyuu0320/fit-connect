-- clients テーブルに authenticated ユーザー用の INSERT ポリシーを追加
-- 新規登録フローで認証済みユーザーが自分のクライアントレコードを作成できるようにする

-- 既存のポリシーがあれば削除
DROP POLICY IF EXISTS "clients_insert_own" ON "public"."clients";

-- 認証済みユーザーが自分のクライアントレコードを作成できるポリシー
CREATE POLICY "clients_insert_own"
ON "public"."clients"
FOR INSERT
TO authenticated
WITH CHECK (client_id = auth.uid());

-- コメント: このポリシーにより、認証済みユーザーは自分のclient_idでのみレコードを作成できます
