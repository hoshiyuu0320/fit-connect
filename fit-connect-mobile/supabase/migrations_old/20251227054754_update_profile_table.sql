-- 既存のポリシーがあれば削除
DROP POLICY IF EXISTS "ユーザー自身のプロフィール作成を許可" ON public.profiles;

-- ポリシーを作成
CREATE POLICY "ユーザー自身のプロフィール作成を許可"
ON public.profiles
FOR INSERT
WITH CHECK ( auth.uid() = id );

-- mail_addressカラム追加
ALTER TABLE public.profiles 
ADD COLUMN email TEXT;

-- Add comment to document the column
COMMENT ON COLUMN public.profiles.email IS 'Email address of the user';