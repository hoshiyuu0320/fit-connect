-- =============================================================================
-- Migration: create_app_config
-- フェーズ8.2: 強制アップデート機構用の app_config 単一行テーブルを新設する
--
-- 仕様出典: docs/tasks/2026-08-29-storage-private-plan.md 設計判断4
--   - 単一行テーブル（CHECK (id = 1)）。Mobile が起動時に SELECT し、
--     現在バージョン < min_supported_version なら強制アップデートダイアログを表示
--   - 取得失敗・オフライン時は fail-open（通常起動）なので、
--     本テーブルが読めなくてもアプリは止まらない
--
-- アクセス経路:
--   - anon / authenticated: SELECT のみ（未ログイン起動時にも読むため anon を含める）
--   - 書き込み: ポリシーなし = RLS で全拒否。運用者が service_role
--     （SQL エディタ / ダッシュボード）で直接 UPDATE する
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.app_config (
  id integer PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  min_supported_version text NOT NULL DEFAULT '1.0.0',
  latest_version text,
  ios_store_url text,
  android_store_url text,
  update_message text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.app_config IS
  'アプリ全体設定（単一行、id=1 固定）。強制アップデート判定用。'
  '書き込みポリシーは意図的に無し（更新は service_role = 運用者のみ）。'
  'Mobile は起動時に SELECT し、min_supported_version 未満なら強制アップデート。'
  '取得失敗時は fail-open（通常起動）。';

COMMENT ON COLUMN public.app_config.min_supported_version IS
  'サポートする最小アプリバージョン（semver: major.minor.patch）。'
  'これ未満のアプリは強制アップデートダイアログを表示する';
COMMENT ON COLUMN public.app_config.latest_version IS
  '最新リリースバージョン（表示用・任意）';
COMMENT ON COLUMN public.app_config.ios_store_url IS
  'App Store の URL。NULL の場合ダイアログは文言のみ表示（ボタン無し）';
COMMENT ON COLUMN public.app_config.android_store_url IS
  'Google Play の URL。NULL の場合ダイアログは文言のみ表示（ボタン無し）';
COMMENT ON COLUMN public.app_config.update_message IS
  '強制アップデートダイアログに表示する任意メッセージ。NULL ならデフォルト文言';

-- updated_at 自動更新（既存の public.update_updated_at_column() を再利用。
-- 20251230131753_remote_schema.sql で定義済み・payments 等でも使用中）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_app_config'
  ) THEN
    CREATE TRIGGER set_updated_at_app_config
      BEFORE UPDATE ON public.app_config
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- RLS: SELECT のみ anon + authenticated に許可。
-- INSERT/UPDATE/DELETE ポリシーは意図的に作らない
-- （= クライアントからの書き込みは全て拒否。更新は RLS をバイパスする service_role のみ）
ALTER TABLE public.app_config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'app_config'
      AND policyname = 'app_config_select_all'
  ) THEN
    CREATE POLICY "app_config_select_all"
      ON public.app_config
      FOR SELECT
      TO anon, authenticated
      USING (true);
  END IF;
END $$;

-- 権限（ALTER DEFAULT PRIVILEGES 対策）:
-- 20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により
-- anon / authenticated へ GRANT ALL が自動付与されるため、SELECT のみに絞る。
-- （書き込みは RLS でも拒否されるが、テーブル権限でも二重に封鎖する）
REVOKE ALL ON public.app_config FROM anon;
REVOKE ALL ON public.app_config FROM authenticated;
GRANT SELECT ON public.app_config TO anon;
GRANT SELECT ON public.app_config TO authenticated;

-- seed 行（id=1 固定。既に存在すれば何もしない = 冪等）
INSERT INTO public.app_config (id) VALUES (1)
ON CONFLICT (id) DO NOTHING;
