-- Migration: add_payment_records
-- フェーズ: カタログ cat3 機能2-A「チケット価格設定＋支払記録・未払い管理」
--          （docs/tasks/2026-07-08-solution-catalog.md L601-628）
--
-- 目的:
--   1. ticket_templates / tickets に price_yen を追加（null = 価格未設定で後方互換）
--   2. payments テーブル新設（支払記録・未払い管理。トレーナー本人のみ CRUD）
--   3. issue_recurring_tickets() を改修し、価格付きテンプレートからの月次チケット
--      発行時に payments（unpaid）を自動生成する
--
-- 冪等性: ALTER TABLE ... IF NOT EXISTS / CREATE TABLE IF NOT EXISTS /
--         pg_policies・pg_trigger ガード付き DO ブロック / CREATE OR REPLACE FUNCTION /
--         REVOKE（元々冪等）で構成しており、再実行しても安全。

-- ============================================================
-- 1. ticket_templates.price_yen（テンプレート価格）
-- ============================================================
-- nullable = 価格未設定。既存テンプレートは NULL のままとなり後方互換。
ALTER TABLE public.ticket_templates
  ADD COLUMN IF NOT EXISTS price_yen integer CHECK (price_yen >= 0);

COMMENT ON COLUMN public.ticket_templates.price_yen IS
  'テンプレート価格（円）。NULL = 価格未設定（後方互換）。設定時はチケット発行と同時に payments が自動生成される';

-- ============================================================
-- 2. tickets.price_yen（発行時点のテンプレート価格スナップショット）
-- ============================================================
-- テンプレート価格を後から変更しても、発行済みチケットの価格は変わらない。
ALTER TABLE public.tickets
  ADD COLUMN IF NOT EXISTS price_yen integer CHECK (price_yen >= 0);

COMMENT ON COLUMN public.tickets.price_yen IS
  '発行時点のテンプレート価格スナップショット（円）。NULL = 価格未設定';

-- ============================================================
-- 3. payments テーブル（支払記録）
-- ============================================================
CREATE TABLE IF NOT EXISTS public.payments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES public.trainers(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES public.clients(client_id) ON DELETE CASCADE,
  ticket_id uuid REFERENCES public.tickets(id) ON DELETE SET NULL,
  ticket_subscription_id uuid REFERENCES public.ticket_subscriptions(id) ON DELETE SET NULL,
  amount_yen integer NOT NULL CHECK (amount_yen >= 0),
  -- method は「支払済みにする時」に記録するため nullable
  method text CHECK (method IN ('cash', 'bank_transfer', 'card_external', 'stripe')),
  -- 'overdue' は将来用の値。運用上は due_date と現在日から UI 側で「期限超過」を
  -- 導出する方針とし、overdue へ更新する cron は作らない（cron 増殖の回避）。
  status text NOT NULL DEFAULT 'unpaid' CHECK (status IN ('unpaid', 'paid', 'overdue', 'refunded')),
  due_date date,
  paid_at timestamptz,
  receipt_number text,
  note text,
  -- カタログ cat3 機能2-B（Stripe Connect 決済代行）用の先置きカラム。
  -- 2-A の時点では常に NULL。決済リンク導入時に Checkout Session ID を保存する。
  stripe_checkout_session_id text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.payments IS
  '支払記録（cat3 機能2-A）。チケット/月契約の金額・期日・入金状態をトレーナーが管理する。決済処理自体は外部（現金・振込等）';

-- updated_at 自動更新（既存の public.update_updated_at_column() を再利用。
-- 20251230131753_remote_schema.sql で定義済み・trainer_billing 等でも使用中）
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_trigger WHERE tgname = 'set_updated_at_payments') THEN
    CREATE TRIGGER set_updated_at_payments
      BEFORE UPDATE ON public.payments
      FOR EACH ROW
      EXECUTE FUNCTION public.update_updated_at_column();
  END IF;
END $$;

-- インデックス
CREATE INDEX IF NOT EXISTS idx_payments_trainer_status ON public.payments (trainer_id, status);
CREATE INDEX IF NOT EXISTS idx_payments_client ON public.payments (client_id);
CREATE INDEX IF NOT EXISTS idx_payments_due_date ON public.payments (due_date);

-- RLS: トレーナー本人のみ CRUD。
-- 顧客（Mobile）からの SELECT ポリシーは 2-B（Stripe Connect / 顧客に金額を見せる段階）
-- で「自分宛のみ」として追加する。2-A では顧客アクセスなし。
ALTER TABLE public.payments ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'payments' AND policyname = 'payments_trainer_all'
  ) THEN
    CREATE POLICY "payments_trainer_all"
      ON public.payments
      FOR ALL
      TO authenticated
      USING (trainer_id = auth.uid())
      WITH CHECK (trainer_id = auth.uid());
  END IF;
END $$;

-- ALTER DEFAULT PRIVILEGES（20251230131753）により anon / authenticated へ GRANT ALL が
-- 自動付与されるため、anon からは明示的に剥がす（多層防御。RLS だけに頼らない。
-- 20260712000000_add_billing_foundation.sql の trainer_billing と同じパターン）。
-- authenticated は GRANT ALL を維持し、行の絞り込みは上記 RLS ポリシーが担う。
REVOKE ALL ON public.payments FROM anon;
-- service_role は DEFAULT PRIVILEGES で ALL 付与済み（RLS もバイパスする）

-- ============================================================
-- 4. issue_recurring_tickets() の改修
-- ============================================================
-- ベース: 20260710020000_codify_cron_jobs.sql（リモート実測定義の追認版）。
-- 改修理由（cat3 機能2-A）:
--   - tickets INSERT に price_yen（発行時点のテンプレート価格スナップショット）を追加
--   - テンプレートに価格が設定されている場合、支払記録 payments（status='unpaid',
--     due_date=チケット有効開始日）を自動生成し、「いくら請求すべきか」を
--     トレーナーが手動管理しなくて済むようにする
-- 既存動作（対象抽出条件・next_issue_date の翌月更新・SECURITY DEFINER）は不変。
-- price_yen が NULL のテンプレートでは payments を生成しない（後方互換）。
CREATE OR REPLACE FUNCTION public.issue_recurring_tickets()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
DECLARE
  sub RECORD;
  new_valid_from DATE;
  new_valid_until DATE;
  new_ticket_id UUID;
BEGIN
  FOR sub IN
    SELECT ts.*, tt.trainer_id, tt.template_name, tt.ticket_type, tt.total_sessions, tt.valid_months, tt.price_yen
    FROM ticket_subscriptions ts
    JOIN ticket_templates tt ON ts.template_id = tt.id
    WHERE ts.status = 'active'
      AND ts.next_issue_date <= CURRENT_DATE
  LOOP
    new_valid_from := sub.next_issue_date;
    new_valid_until := sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL;

    -- チケット発行（price_yen = 発行時点のテンプレート価格スナップショット）
    INSERT INTO tickets (client_id, ticket_name, ticket_type, total_sessions, remaining_sessions, valid_from, valid_until, price_yen)
    VALUES (
      sub.client_id,
      sub.template_name,
      sub.ticket_type,
      sub.total_sessions,
      sub.total_sessions,
      new_valid_from,
      new_valid_until,
      sub.price_yen
    )
    RETURNING id INTO new_ticket_id;

    -- 価格付きテンプレートの場合のみ支払記録（未払い）を自動生成
    IF sub.price_yen IS NOT NULL THEN
      INSERT INTO payments (trainer_id, client_id, ticket_id, ticket_subscription_id, amount_yen, status, due_date)
      VALUES (
        sub.trainer_id,
        sub.client_id,
        new_ticket_id,
        sub.id,
        sub.price_yen,
        'unpaid',
        new_valid_from
      );
    END IF;

    -- 次回発行日を翌月に更新
    UPDATE ticket_subscriptions
    SET next_issue_date = sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL
    WHERE id = sub.id;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.issue_recurring_tickets() IS
  '月契約（ticket_subscriptions）の定期チケット発行。pg_cron ジョブ issue-recurring-tickets が毎日 00:00 UTC に実行。20260712120000 で price_yen スナップショットと payments（unpaid）自動生成を追加';
