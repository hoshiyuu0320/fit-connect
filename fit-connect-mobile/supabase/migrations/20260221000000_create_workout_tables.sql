-- ワークアウトアサインメントテーブルとワークアウトエクササイズテーブルを作成する
-- トレーナーがクライアントにワークアウトを割り当てる機能に使用

-- テーブル1: workout_assignments
CREATE TABLE IF NOT EXISTS workout_assignments (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES trainers(id),
  client_id uuid NOT NULL REFERENCES clients(client_id),
  assigned_date date NOT NULL,
  title text NOT NULL,
  description text,
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE workout_assignments ENABLE ROW LEVEL SECURITY;

-- テーブル2: workout_exercises
CREATE TABLE IF NOT EXISTS workout_exercises (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  assignment_id uuid NOT NULL REFERENCES workout_assignments(id) ON DELETE CASCADE,
  name text NOT NULL,
  target_sets int NOT NULL DEFAULT 3,
  target_reps int NOT NULL DEFAULT 10,
  memo text,
  sort_order int NOT NULL DEFAULT 0,
  is_completed boolean NOT NULL DEFAULT false,
  completed_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE workout_exercises ENABLE ROW LEVEL SECURITY;

-- インデックス
CREATE INDEX IF NOT EXISTS idx_workout_assignments_client_date ON workout_assignments(client_id, assigned_date);

-- RLSポリシー: workout_assignments
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignments' AND policyname = 'Clients can view own assignments'
  ) THEN
    CREATE POLICY "Clients can view own assignments"
      ON workout_assignments FOR SELECT
      USING (client_id IN (
        SELECT client_id FROM clients WHERE client_id = auth.uid()
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignments' AND policyname = 'Clients can update own assignments'
  ) THEN
    CREATE POLICY "Clients can update own assignments"
      ON workout_assignments FOR UPDATE
      USING (client_id IN (
        SELECT client_id FROM clients WHERE client_id = auth.uid()
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_assignments' AND policyname = 'Trainers can manage own assignments'
  ) THEN
    CREATE POLICY "Trainers can manage own assignments"
      ON workout_assignments FOR ALL
      USING (trainer_id = auth.uid());
  END IF;
END $$;

-- RLSポリシー: workout_exercises
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'Users can view exercises of accessible assignments'
  ) THEN
    CREATE POLICY "Users can view exercises of accessible assignments"
      ON workout_exercises FOR SELECT
      USING (assignment_id IN (
        SELECT id FROM workout_assignments
        WHERE client_id = auth.uid() OR trainer_id = auth.uid()
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'Users can update exercises of accessible assignments'
  ) THEN
    CREATE POLICY "Users can update exercises of accessible assignments"
      ON workout_exercises FOR UPDATE
      USING (assignment_id IN (
        SELECT id FROM workout_assignments
        WHERE client_id = auth.uid() OR trainer_id = auth.uid()
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'Trainers can insert exercises'
  ) THEN
    CREATE POLICY "Trainers can insert exercises"
      ON workout_exercises FOR INSERT
      WITH CHECK (assignment_id IN (
        SELECT id FROM workout_assignments
        WHERE trainer_id = auth.uid()
      ));
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'workout_exercises' AND policyname = 'Trainers can delete exercises'
  ) THEN
    CREATE POLICY "Trainers can delete exercises"
      ON workout_exercises FOR DELETE
      USING (assignment_id IN (
        SELECT id FROM workout_assignments
        WHERE trainer_id = auth.uid()
      ));
  END IF;
END $$;
