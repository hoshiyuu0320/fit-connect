-- Schedule Feature Migration SQL

-- 1. Add ticket_id column to sessions table (for SCH-04 Ticket Consumption)
-- This allows linking a session to a specific ticket usage.
ALTER TABLE sessions 
ADD COLUMN IF NOT EXISTS ticket_id UUID REFERENCES tickets(id);

-- 2. Enable RLS on sessions table (if not already enabled)
ALTER TABLE sessions ENABLE ROW LEVEL SECURITY;

-- 3. Drop existing policies to avoid conflicts (optional, but good for idempotency)
DROP POLICY IF EXISTS "Trainers can view their own sessions" ON sessions;
DROP POLICY IF EXISTS "Trainers can insert their own sessions" ON sessions;
DROP POLICY IF EXISTS "Trainers can update their own sessions" ON sessions;
DROP POLICY IF EXISTS "Trainers can delete their own sessions" ON sessions;

-- 4. Create RLS Policies for sessions table

-- Policy: Trainers can view sessions where they are the trainer
CREATE POLICY "Trainers can view their own sessions"
ON sessions
FOR SELECT
USING (auth.uid() = trainer_id);

-- Policy: Trainers can insert sessions where they are the trainer
CREATE POLICY "Trainers can insert their own sessions"
ON sessions
FOR INSERT
WITH CHECK (auth.uid() = trainer_id);

-- Policy: Trainers can update sessions where they are the trainer
CREATE POLICY "Trainers can update their own sessions"
ON sessions
FOR UPDATE
USING (auth.uid() = trainer_id);

-- Policy: Trainers can delete sessions where they are the trainer
CREATE POLICY "Trainers can delete their own sessions"
ON sessions
FOR DELETE
USING (auth.uid() = trainer_id);

-- 5. Add Indexes for performance (as recommended in db-design.md)
CREATE INDEX IF NOT EXISTS idx_sessions_trainer_id ON sessions(trainer_id);
CREATE INDEX IF NOT EXISTS idx_sessions_client_id ON sessions(client_id);
CREATE INDEX IF NOT EXISTS idx_sessions_session_date ON sessions(session_date);
CREATE INDEX IF NOT EXISTS idx_sessions_status ON sessions(status);
