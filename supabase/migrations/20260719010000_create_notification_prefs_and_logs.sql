-- Migration: create_notification_prefs_and_logs
-- 目的: 通知ディスパッチャ基盤の設定・ログ2テーブルを新設する。
--   - notification_preferences: 通知種別ごとの opt-in/out + quiet hours（ユーザー設定）
--   - notification_logs:        送達ログ + dedup_key による冪等化（service_role 専用書き込み）
--
-- アクセス経路:
--   - notification_preferences:
--       Web/Mobile がクライアントから RLS 経由で直接 upsert / select（authenticated + 本人ポリシー）
--   - notification_logs:
--       書き込みはディスパッチャ（service_role。RLS バイパス）のみ。
--       authenticated は SELECT のみ（将来の通知センター用に自分宛ログを閲覧可能）
--   - anon: 両テーブルとも一切アクセス不可（REVOKE ALL）

-- ============================================================
-- 1. notification_preferences（通知設定）
-- ============================================================
-- オプトアウト方式: 行が存在しない (user_id, kind) は「有効」として扱う。
-- ユーザーが設定を変更したときに初めて行が upsert される。

CREATE TABLE IF NOT EXISTS public.notification_preferences (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  kind text NOT NULL CHECK (kind IN ('message','goal_achievement')),
  enabled boolean NOT NULL DEFAULT true,
  quiet_hours_start time,   -- JST の時刻として解釈。NULL = quiet hours なし
  quiet_hours_end time,     -- JST の時刻として解釈。NULL = quiet hours なし
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, kind)
);

COMMENT ON TABLE public.notification_preferences IS
  '通知設定（種別ごとの opt-in/out + quiet hours）。オプトアウト方式: '
  '行が存在しない kind は有効として扱う（ディスパッチャ実装と対）。'
  'kind の追加は migration で CHECK 制約を拡張すること。'
  'Web/Mobile がクライアントから RLS 経由で直接 upsert する。';

COMMENT ON COLUMN public.notification_preferences.kind IS
  '通知種別。現状 message（メッセージ受信）/ goal_achievement（目標達成）。'
  '種別を増やすときは migration で CHECK を拡張する';
COMMENT ON COLUMN public.notification_preferences.enabled IS
  'false でこの kind の通知を停止。行が無い kind は有効（オプトアウト方式）';
COMMENT ON COLUMN public.notification_preferences.quiet_hours_start IS
  '通知を抑止する時間帯の開始時刻。JST の時刻として解釈する（timestamptz ではなく time）。'
  'NULL = quiet hours なし。start > end の場合は日跨ぎ（例 22:00→07:00）としてディスパッチャが解釈する';
COMMENT ON COLUMN public.notification_preferences.quiet_hours_end IS
  '通知を抑止する時間帯の終了時刻。JST の時刻として解釈する。NULL = quiet hours なし';

-- updated_at 自動更新（既存の public.update_updated_at_column() を再利用。
-- 20251230131753_remote_schema.sql で定義済み・payments 等でも使用中）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_notification_preferences'
  ) THEN
    CREATE TRIGGER set_updated_at_notification_preferences
      BEFORE UPDATE ON public.notification_preferences
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- RLS: 本人のみ全操作可（クライアントから直接 upsert / select するため FOR ALL 1本）
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notification_preferences'
      AND policyname = 'notification_preferences_own_all'
  ) THEN
    CREATE POLICY "notification_preferences_own_all"
      ON public.notification_preferences
      FOR ALL
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- 権限（ALTER DEFAULT PRIVILEGES 対策）:
-- 20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により
-- anon / authenticated へ GRANT ALL が自動付与されるため、anon から明示的に剥がす。
-- authenticated は ALL のまま（行の絞り込みは上記 RLS ポリシーが担う）。
REVOKE ALL ON public.notification_preferences FROM anon;

-- ============================================================
-- 2. notification_logs（送達ログ + 冪等化）
-- ============================================================
-- user_id は意図的に FK なし（アカウント削除後も監査ログとして残す）。

CREATE TABLE IF NOT EXISTS public.notification_logs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  kind text NOT NULL,
  dedup_key text NOT NULL UNIQUE,
  title text,
  body text,
  status text NOT NULL DEFAULT 'pending' CHECK (status IN ('pending','sent','partial','failed','skipped')),
  detail text,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.notification_logs IS
  '通知送達ログ + dedup_key による冪等化。書き込みはディスパッチャ（service_role）のみ。'
  'INSERT ... ON CONFLICT (dedup_key) DO NOTHING の戻り行数で冪等判定する'
  '（0 行 = 送信済み/処理中なのでスキップ、1 行 = 自分が送信担当）。'
  'authenticated は自分宛ログの SELECT のみ可（将来の通知センター用）。';

COMMENT ON COLUMN public.notification_logs.dedup_key IS
  '冪等化キー（UNIQUE）。規約例: ''message:<message_id>''、'
  '''goal_achievement:<client_id>:<goal_id>'' のように「kind:イベント一意識別子」で構成する。'
  '送信前に INSERT ... ON CONFLICT (dedup_key) DO NOTHING し、0 行なら二重送信としてスキップ';
COMMENT ON COLUMN public.notification_logs.status IS
  'pending: 行確保済み・送信前 / sent: 全デバイス送信成功 / partial: 一部失敗 / '
  'failed: 全滅 / skipped: 設定・quiet hours 等で送信せず';
COMMENT ON COLUMN public.notification_logs.detail IS
  '失敗理由・スキップ理由などの補足（自由テキスト）';

-- インデックス: 通知センター（本人の新着順一覧）・RLS 評価用
CREATE INDEX IF NOT EXISTS idx_notification_logs_user_created
  ON public.notification_logs (user_id, created_at DESC);

-- RLS: SELECT のみ本人可。INSERT/UPDATE/DELETE ポリシーは意図的に作らない
-- （= authenticated からの書き込みは全て拒否。書き込みは RLS をバイパスする service_role 専用）
ALTER TABLE public.notification_logs ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'notification_logs'
      AND policyname = 'notification_logs_own_select'
  ) THEN
    CREATE POLICY "notification_logs_own_select"
      ON public.notification_logs
      FOR SELECT
      TO authenticated
      USING (user_id = auth.uid());
  END IF;
END $$;

-- 権限（ALTER DEFAULT PRIVILEGES 対策）: anon から明示的に剥がす
REVOKE ALL ON public.notification_logs FROM anon;
