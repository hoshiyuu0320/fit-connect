-- トレーナーのオンライン/オフライン Presence 機能用カラム追加
ALTER TABLE trainers ADD COLUMN is_online boolean NOT NULL DEFAULT false;
ALTER TABLE trainers ADD COLUMN last_seen_at timestamptz;

-- Realtime でトレーナーの状態変更をクライアントに通知するために publication に追加
ALTER PUBLICATION supabase_realtime ADD TABLE trainers;;
