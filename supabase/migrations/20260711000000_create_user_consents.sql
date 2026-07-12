-- 利用規約・プライバシーポリシーへの同意記録テーブルを作成する
-- 目的: サインアップ時にユーザー（トレーナー/顧客）がどのバージョンの規約・ポリシーに
--       いつ同意したかを記録する（App Store 審査・法務要件対応）

CREATE TABLE IF NOT EXISTS public.user_consents (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  user_type text NOT NULL CHECK (user_type IN ('trainer', 'client')),
  document text NOT NULL CHECK (document IN ('terms', 'privacy')),
  version text NOT NULL,
  consented_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.user_consents ENABLE ROW LEVEL SECURITY;

-- インデックス
CREATE INDEX IF NOT EXISTS idx_user_consents_user ON public.user_consents(user_id, document);

-- RLSポリシー: 本人のみ INSERT / SELECT 可能
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_consents' AND policyname = 'Users can insert own consents'
  ) THEN
    CREATE POLICY "Users can insert own consents"
      ON public.user_consents FOR INSERT
      WITH CHECK (user_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'user_consents' AND policyname = 'Users can view own consents'
  ) THEN
    CREATE POLICY "Users can view own consents"
      ON public.user_consents FOR SELECT
      USING (user_id = auth.uid());
  END IF;
END $$;
