-- Migration: repair_workout_schema_drift
-- 目的: リモートDBへ直接加えられ migration 管理外となっていた workout 系スキーマ
--       （workout_plans / workout_exercises / workout_assignments / workout_assignment_exercises）
--       を migration に追認し、空DBからの `supabase db reset` でリモートと同一形状を再現する。
--       定義は 2026-07-10 時点のリモート実測（schema-drift-facts.md §1〜4）に基づく。
--
-- リモートには no-op である理由:
--   - CREATE TABLE / CREATE INDEX は IF NOT EXISTS（リモートでは全て存在済み）
--   - ADD COLUMN は IF NOT EXISTS（リモートでは全カラム存在済み）
--   - DROP COLUMN / DROP POLICY / DROP INDEX は IF EXISTS（対象は repo 由来でリモートに存在しない）
--   - SET NOT NULL / DROP NOT NULL はリモートの現状と同値のため no-op
--   - 制約追加は pg_constraint の存在チェック付き DO ブロック（制約名はリモート実名）
--   - CREATE POLICY は pg_policies の存在チェック付き DO ブロック（既存ポリシーには触れない）

-- ============================================================
-- 1. workout_plans（テーブルごと migration 欠落 → 新設）
-- ============================================================

CREATE TABLE IF NOT EXISTS workout_plans (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  title text NOT NULL,
  description text,
  category text NOT NULL DEFAULT 'other',
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  estimated_minutes integer,
  plan_type text NOT NULL DEFAULT 'session',
  CONSTRAINT workout_plans_plan_type_check CHECK (plan_type IN ('self_guided', 'session'))
);

ALTER TABLE workout_plans ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_workout_plans_trainer_id ON workout_plans(trainer_id);

-- workout_plans のポリシー（clients_read_assigned_plans は workout_assignments.plan_id を
-- 参照するため、後段の workout_assignments 修復後に作成する）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_plans' AND policyname = 'Trainers can manage their plans'
  ) THEN
    CREATE POLICY "Trainers can manage their plans"
      ON workout_plans FOR ALL TO authenticated
      USING (trainer_id = auth.uid())
      WITH CHECK (trainer_id = auth.uid());
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_plans' AND policyname = 'trainers_own_workout_plans'
  ) THEN
    CREATE POLICY "trainers_own_workout_plans"
      ON workout_plans FOR ALL
      USING (trainer_id = auth.uid());
  END IF;
END $$;

-- ============================================================
-- 2. workout_exercises（assignment紐付き → plan紐付きの雛形テーブルへ形状変換）
-- ============================================================

-- repo 由来でリモートに存在しない旧ポリシーを除去
-- （assignment_id に依存するため、カラム削除より先に実行する必要がある）
DROP POLICY IF EXISTS "Users can view exercises of accessible assignments" ON workout_exercises;
DROP POLICY IF EXISTS "Users can update exercises of accessible assignments" ON workout_exercises;
DROP POLICY IF EXISTS "Trainers can insert exercises" ON workout_exercises;
DROP POLICY IF EXISTS "Trainers can delete exercises" ON workout_exercises;

-- repo 由来でリモートに存在しない旧カラムを除去
-- （assignment_id の FK は列削除と同時に削除される）
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS assignment_id;
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS target_sets;
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS target_reps;
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS sort_order;
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS is_completed;
ALTER TABLE workout_exercises DROP COLUMN IF EXISTS completed_at;

-- リモート実カラムを追認
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS plan_id uuid;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS sets integer DEFAULT 3;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS reps integer;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS weight numeric;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS duration_seconds integer;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS rest_seconds integer;
ALTER TABLE workout_exercises ADD COLUMN IF NOT EXISTS order_index integer DEFAULT 0;

-- NOT NULL 化（リモートでは既に NOT NULL のため no-op）
ALTER TABLE workout_exercises ALTER COLUMN plan_id SET NOT NULL;
ALTER TABLE workout_exercises ALTER COLUMN sets SET NOT NULL;
ALTER TABLE workout_exercises ALTER COLUMN order_index SET NOT NULL;

-- FK（制約名はリモート実名）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_exercises_plan_id_fkey'
      AND conrelid = 'workout_exercises'::regclass
  ) THEN
    ALTER TABLE workout_exercises
      ADD CONSTRAINT workout_exercises_plan_id_fkey
      FOREIGN KEY (plan_id) REFERENCES workout_plans(id) ON DELETE CASCADE;
  END IF;
END $$;

CREATE INDEX IF NOT EXISTS idx_workout_exercises_plan_id ON workout_exercises(plan_id);

-- workout_exercises のポリシー（リモート実測 2 本）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'Trainers can manage their exercises'
  ) THEN
    CREATE POLICY "Trainers can manage their exercises"
      ON workout_exercises FOR ALL TO authenticated
      USING (plan_id IN (SELECT workout_plans.id FROM workout_plans WHERE workout_plans.trainer_id = auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'trainers_own_workout_exercises'
  ) THEN
    CREATE POLICY "trainers_own_workout_exercises"
      ON workout_exercises FOR ALL
      USING (plan_id IN (SELECT workout_plans.id FROM workout_plans WHERE workout_plans.trainer_id = auth.uid()));
  END IF;
END $$;

-- ============================================================
-- 3. workout_assignments（カラム乖離の追認）
-- ============================================================

-- repo 由来でリモートに存在しない旧インデックス・旧ポリシーを除去
DROP INDEX IF EXISTS idx_workout_assignments_client_date;
DROP POLICY IF EXISTS "Trainers can manage own assignments" ON workout_assignments;

-- repo 由来でリモートに存在しない旧カラムを除去
ALTER TABLE workout_assignments DROP COLUMN IF EXISTS title;
ALTER TABLE workout_assignments DROP COLUMN IF EXISTS description;
ALTER TABLE workout_assignments DROP COLUMN IF EXISTS is_completed;
ALTER TABLE workout_assignments DROP COLUMN IF EXISTS completed_at;

-- リモート実カラムを追認（session_id / calories は既存 migration
-- 20260221152650 / 20260223114558 が担うためここでは扱わない）
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS plan_id uuid;
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS status text DEFAULT 'pending';
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS trainer_note text;
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS client_feedback text;
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS started_at timestamptz;
ALTER TABLE workout_assignments ADD COLUMN IF NOT EXISTS finished_at timestamptz;

-- NOT NULL 化（リモートでは既に NOT NULL のため no-op）
ALTER TABLE workout_assignments ALTER COLUMN plan_id SET NOT NULL;
ALTER TABLE workout_assignments ALTER COLUMN status SET NOT NULL;

-- リモートでは created_at / updated_at は NULL 許容（repo 定義は NOT NULL）→ 追認
-- （リモートでは既に NULL 許容のため no-op）
ALTER TABLE workout_assignments ALTER COLUMN created_at DROP NOT NULL;
ALTER TABLE workout_assignments ALTER COLUMN updated_at DROP NOT NULL;

-- 制約の追認（制約名はリモート実名）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_plan_id_fkey'
      AND conrelid = 'workout_assignments'::regclass
  ) THEN
    ALTER TABLE workout_assignments
      ADD CONSTRAINT workout_assignments_plan_id_fkey
      FOREIGN KEY (plan_id) REFERENCES workout_plans(id) ON DELETE CASCADE;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_status_check'
      AND conrelid = 'workout_assignments'::regclass
  ) THEN
    ALTER TABLE workout_assignments
      ADD CONSTRAINT workout_assignments_status_check
      CHECK (status IN ('pending', 'partial', 'completed', 'skipped'));
  END IF;
END $$;

-- client_id / trainer_id FK の ON DELETE CASCADE 追認
-- repo（20260221000000）は CASCADE なしで作成するが、リモートは CASCADE あり。
-- リモートでは confdeltype = 'c' のため両ブロックとも no-op。
-- 空DB再現パスでのみ CASCADE なし FK を張り替える。
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_client_id_fkey'
      AND conrelid = 'workout_assignments'::regclass
      AND confdeltype <> 'c'
  ) THEN
    ALTER TABLE workout_assignments DROP CONSTRAINT workout_assignments_client_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_client_id_fkey'
      AND conrelid = 'workout_assignments'::regclass
  ) THEN
    ALTER TABLE workout_assignments
      ADD CONSTRAINT workout_assignments_client_id_fkey
      FOREIGN KEY (client_id) REFERENCES clients(client_id) ON DELETE CASCADE;
  END IF;
END $$;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_trainer_id_fkey'
      AND conrelid = 'workout_assignments'::regclass
      AND confdeltype <> 'c'
  ) THEN
    ALTER TABLE workout_assignments DROP CONSTRAINT workout_assignments_trainer_id_fkey;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'workout_assignments_trainer_id_fkey'
      AND conrelid = 'workout_assignments'::regclass
  ) THEN
    ALTER TABLE workout_assignments
      ADD CONSTRAINT workout_assignments_trainer_id_fkey
      FOREIGN KEY (trainer_id) REFERENCES trainers(id) ON DELETE CASCADE;
  END IF;
END $$;

-- リモート実在のインデックス3本を追認
CREATE INDEX IF NOT EXISTS idx_workout_assignments_trainer_id ON workout_assignments(trainer_id);
CREATE INDEX IF NOT EXISTS idx_workout_assignments_client_id ON workout_assignments(client_id);
CREATE INDEX IF NOT EXISTS idx_workout_assignments_assigned_date ON workout_assignments(assigned_date);

-- workout_assignments のポリシー
-- （"Clients can view own assignments" / "Clients can update own assignments" は
--   repo の 20260221000000 が同名で作成済みのため温存。ここでは触れない）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignments' AND policyname = 'Trainers can manage their assignments'
  ) THEN
    CREATE POLICY "Trainers can manage their assignments"
      ON workout_assignments FOR ALL TO authenticated
      USING (trainer_id = auth.uid())
      WITH CHECK (trainer_id = auth.uid());
  END IF;
END $$;

-- workout_plans の残りポリシー（workout_assignments.plan_id が存在するようになったため作成可能）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_plans' AND policyname = 'clients_read_assigned_plans'
  ) THEN
    CREATE POLICY "clients_read_assigned_plans"
      ON workout_plans FOR SELECT
      USING (id IN (SELECT workout_assignments.plan_id FROM workout_assignments WHERE workout_assignments.client_id = auth.uid()));
  END IF;
END $$;

-- ============================================================
-- 4. workout_assignment_exercises（テーブルごと migration 欠落 → 新設）
-- ============================================================

CREATE TABLE IF NOT EXISTS workout_assignment_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES workout_assignments(id) ON DELETE CASCADE,
  exercise_name text NOT NULL,
  target_sets integer NOT NULL DEFAULT 3,
  target_reps integer NOT NULL DEFAULT 10,
  target_weight numeric,
  order_index integer NOT NULL DEFAULT 0,
  actual_sets jsonb,
  is_completed boolean NOT NULL DEFAULT false,
  memo text,
  linked_exercise_id uuid REFERENCES workout_assignment_exercises(id),
  created_at timestamptz DEFAULT now(),
  completed_at timestamptz
);

ALTER TABLE workout_assignment_exercises ENABLE ROW LEVEL SECURITY;

CREATE INDEX IF NOT EXISTS idx_wae_assignment_id ON workout_assignment_exercises(assignment_id);

-- workout_assignment_exercises のポリシー（リモート実測 3 本）
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignment_exercises' AND policyname = 'Clients can view own assignment exercises'
  ) THEN
    CREATE POLICY "Clients can view own assignment exercises"
      ON workout_assignment_exercises FOR SELECT
      USING (assignment_id IN (SELECT workout_assignments.id FROM workout_assignments WHERE workout_assignments.client_id = auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignment_exercises' AND policyname = 'Clients can update own assignment exercises'
  ) THEN
    CREATE POLICY "Clients can update own assignment exercises"
      ON workout_assignment_exercises FOR UPDATE
      USING (assignment_id IN (SELECT workout_assignments.id FROM workout_assignments WHERE workout_assignments.client_id = auth.uid()));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignment_exercises' AND policyname = 'Trainers can manage assignment exercises'
  ) THEN
    CREATE POLICY "Trainers can manage assignment exercises"
      ON workout_assignment_exercises FOR ALL TO authenticated
      USING (assignment_id IN (SELECT workout_assignments.id FROM workout_assignments WHERE workout_assignments.trainer_id = auth.uid()));
  END IF;
END $$;
