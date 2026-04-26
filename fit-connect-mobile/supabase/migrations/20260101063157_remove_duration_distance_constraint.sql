-- exercise_recordsテーブルのduration/distance必須制約を削除
-- 両方NULLでも登録可能にする（記録の継続性を優先）

ALTER TABLE exercise_records
DROP CONSTRAINT IF EXISTS check_duration_or_distance;
