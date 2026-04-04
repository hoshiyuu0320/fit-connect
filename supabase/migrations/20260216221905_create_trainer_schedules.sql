-- trainer_schedulesテーブル作成
-- トレーナーの稼働スケジュール（曜日・時間帯）を管理

-- trainer_schedules テーブル作成
CREATE TABLE trainer_schedules (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id uuid NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  day_of_week int NOT NULL CHECK (day_of_week >= 0 AND day_of_week <= 6), -- 0=日曜, 6=土曜
  start_time time NOT NULL,
  end_time time NOT NULL,
  is_available boolean NOT NULL DEFAULT true,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now(),
  UNIQUE(trainer_id, day_of_week)
);

-- updated_at自動更新トリガー
CREATE OR REPLACE FUNCTION update_trainer_schedules_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_update_trainer_schedules_updated_at
  BEFORE UPDATE ON trainer_schedules
  FOR EACH ROW
  EXECUTE FUNCTION update_trainer_schedules_updated_at();

-- RLS有効化
ALTER TABLE trainer_schedules ENABLE ROW LEVEL SECURITY;

-- RLSポリシー: クライアントが自分のトレーナーのスケジュールを読める
CREATE POLICY "Clients can view their trainer's schedules"
  ON trainer_schedules
  FOR SELECT
  USING (
    trainer_id IN (
      SELECT trainer_id FROM clients WHERE client_id = auth.uid()
    )
  );

-- RLSポリシー: トレーナーが自分のスケジュールを読める
CREATE POLICY "Trainers can view own schedules"
  ON trainer_schedules
  FOR SELECT
  USING (
    trainer_id = auth.uid()
  );

-- RLSポリシー: トレーナーが自分のスケジュールを作成できる
CREATE POLICY "Trainers can insert own schedules"
  ON trainer_schedules
  FOR INSERT
  WITH CHECK (
    trainer_id = auth.uid()
  );

-- RLSポリシー: トレーナーが自分のスケジュールを更新できる
CREATE POLICY "Trainers can update own schedules"
  ON trainer_schedules
  FOR UPDATE
  USING (
    trainer_id = auth.uid()
  );

-- RLSポリシー: トレーナーが自分のスケジュールを削除できる
CREATE POLICY "Trainers can delete own schedules"
  ON trainer_schedules
  FOR DELETE
  USING (
    trainer_id = auth.uid()
  );
