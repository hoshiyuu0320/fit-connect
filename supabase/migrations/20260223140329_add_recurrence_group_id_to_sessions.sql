ALTER TABLE sessions ADD COLUMN recurrence_group_id UUID DEFAULT NULL;
CREATE INDEX idx_sessions_recurrence_group_id ON sessions(recurrence_group_id);;
