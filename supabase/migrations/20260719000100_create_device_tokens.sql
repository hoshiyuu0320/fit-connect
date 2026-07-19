-- Migration: create_device_tokens
-- 目的: 通知基盤の中核テーブル device_tokens を新設する。
--       統合判断1（docs/tasks/2026-07-10-integration-decisions.md）の確定スキーマ。
--       トレーナーモード（1アプリ2ロール）・PC+スマホ併用を見据え、
--       ユーザー1人につき複数デバイス/複数プラットフォームのトークンを保持する。
--
-- 段階移行（統合判断1）:
--   stage1: 両書き（clients.fcm_token / trainers.fcm_token と device_tokens の両方へ書く）← 現在地
--   stage2: 両読み（送信側が device_tokens を優先読み、fcm_token をフォールバック）
--   stage3: device_tokens 単独（clients.fcm_token / trainers.fcm_token を廃止）
--
-- アクセス経路:
--   - Mobile: RLS 経由で自分のトークンを upsert / delete（authenticated + 本人ポリシー）
--   - Web:    service_role（API Route）経由（RLS バイパス）
--   - anon:   一切アクセス不可（REVOKE ALL）

-- ============================================================
-- 1. テーブル本体
-- ============================================================

CREATE TABLE IF NOT EXISTS public.device_tokens (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_type text NOT NULL CHECK (user_type IN ('client','trainer')),
  platform text NOT NULL CHECK (platform IN ('ios','android','web_push')),
  token text NOT NULL,            -- FCM登録トークン。web_push は endpoint URL
  web_push_p256dh text,           -- web_push のみ
  web_push_auth text,             -- web_push のみ
  last_seen_at timestamptz NOT NULL DEFAULT now(),
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (user_id, token)
);

COMMENT ON TABLE public.device_tokens IS
  'プッシュ通知デバイストークン（ユーザー1人 × 複数デバイス/プラットフォーム）。'
  '段階移行の現在地は stage1（clients.fcm_token / trainers.fcm_token との両書き）。'
  'stage2 で両読み、stage3 で device_tokens 単独となり clients.fcm_token / trainers.fcm_token は廃止予定。'
  'auth.users への FK ON DELETE CASCADE により、アカウント削除時にトークンは自動クリーンアップされる。';

COMMENT ON COLUMN public.device_tokens.token IS
  'FCM 登録トークン。platform=web_push の場合は Push Subscription の endpoint URL';
COMMENT ON COLUMN public.device_tokens.web_push_p256dh IS
  'Web Push 購読の p256dh 公開鍵（platform=web_push のみ。FCM では NULL）';
COMMENT ON COLUMN public.device_tokens.web_push_auth IS
  'Web Push 購読の auth シークレット（platform=web_push のみ。FCM では NULL）';
COMMENT ON COLUMN public.device_tokens.last_seen_at IS
  'トークン最終確認日時。upsert のたびに now() で更新し、stale トークン掃除の判定に使う';

-- ============================================================
-- 2. インデックス
-- ============================================================
-- (user_id, token) は UNIQUE 制約が索引を兼ねる。
-- user_id 単独: 本人のトークン列挙（RLS 評価・ログアウト時削除）
-- (user_type, platform): 送信側ディスパッチャの宛先種別×チャネル絞り込み

CREATE INDEX IF NOT EXISTS idx_device_tokens_user_id
  ON public.device_tokens(user_id);
CREATE INDEX IF NOT EXISTS idx_device_tokens_user_type_platform
  ON public.device_tokens(user_type, platform);

-- ============================================================
-- 3. RLS（本人のみ全操作可）
-- ============================================================
-- Mobile が RLS 経由で自トークンを upsert / delete するため FOR ALL の本人ポリシー1本。
-- Web は service_role 経由（RLS バイパス）なのでポリシー不要。

ALTER TABLE public.device_tokens ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'device_tokens' AND policyname = 'device_tokens_own_all'
  ) THEN
    CREATE POLICY "device_tokens_own_all"
      ON public.device_tokens
      FOR ALL
      TO authenticated
      USING (user_id = auth.uid())
      WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- ============================================================
-- 4. 権限（ALTER DEFAULT PRIVILEGES 対策）
-- ============================================================
-- 20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により
-- anon / authenticated へ GRANT ALL が自動付与されるため、anon から明示的に剥がす
-- （多層防御。20260712000000 の手本踏襲）。
-- authenticated は ALL のまま（行の絞り込みは上記 RLS ポリシーが担う）。
-- service_role は DEFAULT PRIVILEGES で ALL 付与済み（RLS もバイパスする）。

REVOKE ALL ON public.device_tokens FROM anon;
