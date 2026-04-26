ALTER TABLE workout_assignments 
ADD COLUMN session_id UUID REFERENCES sessions(id) ON DELETE SET NULL DEFAULT NULL;;
