-- Migration: add_billing_foundation
-- 目的: Stripe 課金基盤の DB 土台を整備する。
--   1. trainers.subscription_plan の CHECK 制約を ('free','pro') → ('free','pro','business') に拡張
--   2. trainers.trial_ends_at を追加（14日 Pro トライアルの期限。cron 不要のDB管理方式）
--   3. trainer_billing テーブル新設（Stripe 機微情報の分離先。書き込みは service_role のみ）
--   4. trainers のカラムレベル書き込み保護（トレーナー本人による subscription_plan 改ざん防止）
--
-- 背景（セキュリティ）:
--   - trainers の RLS は trainers_select_all USING(true) / trainers_update_own USING(id=auth.uid()) /
--     trainers_insert_own WITH CHECK(id=auth.uid()) であり、update_own にカラム制限がない。
--     さらに 20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により
--     anon / authenticated へ GRANT ALL が付与されるため、トレーナー本人が anon key + 自分の JWT で
--     subscription_plan='pro' に UPDATE できてしまう穴があった → 本 migration の §4 で修正。
--   - trainers_select_all が USING(true) のため、Stripe 顧客IDを trainers に置くと全公開になる
--     → trainer_billing テーブルに分離（§3）。

-- ============================================================
-- 1. subscription_plan CHECK 制約の張り替え
-- ============================================================
-- 既存制約は 20260502120100_add_subscription_plan_to_trainers.sql の
-- インラインカラム CHECK（自動命名: trainers_subscription_plan_check）。
-- pg_constraint ガード付きで冪等に DROP + ADD する（20260710010000〜010002 のパターン踏襲）。

DO $$
BEGIN
  -- 'business' を含まない旧定義のときだけ DROP（再実行時は no-op）
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'trainers_subscription_plan_check'
      AND conrelid = 'public.trainers'::regclass
      AND pg_get_constraintdef(oid) NOT LIKE '%business%'
  ) THEN
    ALTER TABLE public.trainers DROP CONSTRAINT trainers_subscription_plan_check;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'trainers_subscription_plan_check'
      AND conrelid = 'public.trainers'::regclass
  ) THEN
    ALTER TABLE public.trainers
      ADD CONSTRAINT trainers_subscription_plan_check
      CHECK (subscription_plan IN ('free', 'pro', 'business'));
  END IF;
END $$;

-- NOT NULL DEFAULT 'free' は 20260502120100 のまま維持（本 migration では触らない）

COMMENT ON COLUMN public.trainers.subscription_plan IS
  'サブスクリプションプラン（free / pro / business）。Stripe Webhook（service_role）のみが更新する';

-- ============================================================
-- 2. trainers.trial_ends_at（14日 Pro トライアル期限）
-- ============================================================
-- 実効プラン = plan != 'free' ? plan : (trial_ends_at > now() ? 'pro'(トライアル中) : 'free')
-- をアプリ側で計算する方式（cron 不要）。行作成時点から14日のトライアル。
--
-- 注意: DEFAULT 付き ADD COLUMN のため、既存行にも「migration 適用時点 + 14日」で
-- backfill される。既存行は現状テストユーザーのみであり、この挙動はオーナー決定として許容済み。

ALTER TABLE public.trainers
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz DEFAULT (now() + interval '14 days');

COMMENT ON COLUMN public.trainers.trial_ends_at IS
  '14日 Pro トライアルの期限。実効プランはアプリ側で plan!=''free'' ? plan : (trial_ends_at > now() ? pro(trial) : free) と計算する。service_role のみが更新可能';

-- ============================================================
-- 3. trainer_billing テーブル（Stripe 機微情報の分離先）
-- ============================================================
-- trainers は trainers_select_all USING(true) で全公開のため、Stripe 顧客ID等は
-- 本テーブルに分離する。書き込みポリシーは一切作成しない = service_role 専用書き込み。

CREATE TABLE IF NOT EXISTS public.trainer_billing (
  trainer_id uuid PRIMARY KEY REFERENCES public.trainers(id) ON DELETE CASCADE,
  stripe_customer_id text UNIQUE,
  stripe_subscription_id text,
  subscription_status text,
  price_id text,
  current_period_end timestamptz,
  cancel_at_period_end boolean NOT NULL DEFAULT false,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.trainer_billing IS
  'Stripe 課金情報（トレーナー単位）。書き込みは service_role（Stripe Webhook / API Route）のみ。本人は SELECT のみ可';

ALTER TABLE public.trainer_billing ENABLE ROW LEVEL SECURITY;

-- updated_at 自動更新（既存の public.update_updated_at_column() を再利用。
-- 20251230131753_remote_schema.sql で定義済み・trainers 等でも使用中）
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_trainer_billing') THEN
    CREATE TRIGGER set_updated_at_trainer_billing
      BEFORE UPDATE ON public.trainer_billing
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- RLS ポリシー: 本人 SELECT のみ（INSERT/UPDATE/DELETE ポリシー無し = service_role のみ書き込み可）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'trainer_billing' AND policyname = 'trainer_billing_select_own'
  ) THEN
    CREATE POLICY "trainer_billing_select_own"
      ON public.trainer_billing
      FOR SELECT
      TO authenticated
      USING (trainer_id = auth.uid());
  END IF;
END $$;

-- ALTER DEFAULT PRIVILEGES（20251230131753）により anon / authenticated へ GRANT ALL が
-- 自動付与されるため、明示的に剥がす（多層防御。RLS だけに頼らない）。
-- authenticated には SELECT のみ残す（行の絞り込みは上記 RLS ポリシーが担う）。
REVOKE ALL ON public.trainer_billing FROM anon;
REVOKE ALL ON public.trainer_billing FROM authenticated;
GRANT SELECT ON public.trainer_billing TO authenticated;
-- service_role は DEFAULT PRIVILEGES で ALL 付与済み（RLS もバイパスする）

-- ============================================================
-- 4. trainers のカラムレベル書き込み保護
-- ============================================================
-- テーブル全体の INSERT/UPDATE 権限を剥がし、クライアントが実際に書くカラムのみ
-- カラムレベル GRANT で許可し直す。subscription_plan / trial_ends_at は絶対に含めない。
--
-- 非 service_role クライアントからの trainers 書き込み箇所（2026-07-12 grep 全数調査）:
--   [UPDATE]
--   - fit-connect-mobile/lib/services/notification_service.dart
--       L220: .from('trainers').update({'fcm_token': token}).eq('id', userId)     … FCMトークン登録
--       L244: .from('trainers').update({'fcm_token': null}).eq('id', userId)      … ログアウト時削除
--       L310: .from('trainers').update({'fcm_token': newToken}).eq('id', ...)     … トークンリフレッシュ
--     → fcm_token が現行コードで唯一のクライアント UPDATE カラム
--   - is_online / last_seen_at（20260307122114 のプレゼンスカラム）:
--     現行コードに PostgREST 経由の書き込みは未検出（mobile は読み取り + Realtime 購読のみ）だが、
--     トレーナー本人のプレゼンス更新用に設計されたカラムであり機微情報でもないため UPDATE を許可する
--   - name / email / profile_image_url（本人プロフィール）:
--     現行のクライアント書き込みは Web updateTrainer.ts（service_role）経由のみだが、
--     trainers_update_own ポリシー（本人行の更新を想定）との互換維持のため UPDATE を許可する。
--     いずれも trainers_select_all で全公開済みのカラムであり機微情報ではない
--   [INSERT]
--   - fit-connect/src/lib/supabase/createTrainer.ts
--       L7-8: .from('trainers').insert([{ id, name, email }])  … browser client（ANON_KEY）
--     → 現在どこからも import されていない死にコードだが、trainers_insert_own ポリシーとの
--       互換維持のため id / name / email / profile_image_url の INSERT を許可しておく
--   [対象外（service_role 経由のため本 GRANT の影響を受けない）]
--   - fit-connect/src/lib/supabase/updateTrainer.ts（supabaseAdmin: name/email/profile_image_url）
--   - fit-connect/src/app/auth/callback/route.ts（supabaseAdmin: upsert id/name/email/profile_image_url）
--   - fit-connect/src/app/api/trainers/create/route.ts（supabaseAdmin: insert id/name/email）

REVOKE INSERT, UPDATE ON public.trainers FROM anon, authenticated;

GRANT UPDATE (name, email, profile_image_url, fcm_token, is_online, last_seen_at)
  ON public.trainers TO authenticated;
GRANT INSERT (id, name, email, profile_image_url) ON public.trainers TO authenticated;

-- SELECT 権限は既存のまま（trainers_select_all による全件読み取りは QR コード連携フローで必要）。
-- anon には INSERT/UPDATE を一切戻さない。
