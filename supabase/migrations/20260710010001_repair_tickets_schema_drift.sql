-- Migration: repair_tickets_schema_drift
-- 目的: リモートDBへ直接加えられ migration 管理外となっていた ticket_templates /
--       ticket_subscriptions を migration に追認し、空DBからの `supabase db reset` で
--       リモートと同一形状を再現する。
--       定義は 2026-07-10 時点のリモート実測（schema-drift-facts.md §6）に基づく。
--
-- リモートには no-op である理由:
--   - CREATE TABLE / CREATE INDEX は IF NOT EXISTS（リモートでは全て存在済み）
--   - CREATE POLICY は pg_policies の存在チェック付き DO ブロック（既存ポリシーには触れない）
--   - ENABLE ROW LEVEL SECURITY は冪等

-- ============================================================
-- 1. ticket_templates
-- ============================================================

CREATE TABLE IF NOT EXISTS ticket_templates (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  template_name text NOT NULL,
  ticket_type text NOT NULL CHECK (ticket_type IN ('personal', 'group', 'online', 'other')),
  total_sessions integer NOT NULL CHECK (total_sessions > 0),
  valid_months integer NOT NULL DEFAULT 1 CHECK (valid_months > 0),
  is_recurring boolean NOT NULL DEFAULT false,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE ticket_templates ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ticket_templates_trainer ON ticket_templates(trainer_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'ticket_templates' AND policyname = 'Trainers can manage own templates'
  ) THEN
    CREATE POLICY "Trainers can manage own templates"
      ON ticket_templates FOR ALL
      USING (trainer_id = auth.uid())
      WITH CHECK (trainer_id = auth.uid());
  END IF;
END $$;

-- ============================================================
-- 2. ticket_subscriptions
-- ============================================================

CREATE TABLE IF NOT EXISTS ticket_subscriptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  template_id uuid NOT NULL REFERENCES ticket_templates(id) ON DELETE CASCADE,
  client_id uuid NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
  status text NOT NULL DEFAULT 'active' CHECK (status IN ('active', 'paused', 'cancelled')),
  start_date date NOT NULL,
  next_issue_date date NOT NULL,
  created_at timestamptz DEFAULT now(),
  UNIQUE (template_id, client_id)
);

ALTER TABLE ticket_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_ticket_subscriptions_status ON ticket_subscriptions(status, next_issue_date);
CREATE INDEX IF NOT EXISTS idx_ticket_subscriptions_client ON ticket_subscriptions(client_id);

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'ticket_subscriptions' AND policyname = 'Trainers can manage subscriptions of own clients'
  ) THEN
    CREATE POLICY "Trainers can manage subscriptions of own clients"
      ON ticket_subscriptions FOR ALL
      USING (client_id IN (SELECT clients.client_id FROM clients WHERE clients.trainer_id = auth.uid()))
      WITH CHECK (client_id IN (SELECT clients.client_id FROM clients WHERE clients.trainer_id = auth.uid()));
  END IF;
END $$;
