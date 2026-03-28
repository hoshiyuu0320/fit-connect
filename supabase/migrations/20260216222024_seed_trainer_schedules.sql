-- trainer_schedulesテーブルにテストデータを投入
-- 全トレーナーに対して月〜金 9:00-18:00 のスケジュールを設定

INSERT INTO trainer_schedules (trainer_id, day_of_week, start_time, end_time, is_available)
SELECT
  t.id,
  dow.day,
  '09:00'::time,
  '18:00'::time,
  true
FROM trainers t
CROSS JOIN (VALUES (1), (2), (3), (4), (5)) AS dow(day)
ON CONFLICT (trainer_id, day_of_week) DO NOTHING;
