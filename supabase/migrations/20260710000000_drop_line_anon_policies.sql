-- 旧LINE連携（LIFF）用に clients テーブルへ付与されていた anon ロールの
-- 全行開放ポリシーを削除する。LINE連携は廃止済みで、正規経路は
-- authenticated（Mobile）/ service_role（Web Admin）のみのため影響なし。
DROP POLICY IF EXISTS "LINEユーザー登録の許可_INSERT" ON public.clients;
DROP POLICY IF EXISTS "LINEユーザー登録の許可_SELECT" ON public.clients;
DROP POLICY IF EXISTS "LINEユーザー登録の許可_UPDATE" ON public.clients;
