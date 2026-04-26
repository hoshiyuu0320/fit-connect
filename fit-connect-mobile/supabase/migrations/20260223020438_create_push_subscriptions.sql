
CREATE TABLE push_subscriptions (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  trainer_id UUID NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  endpoint TEXT NOT NULL UNIQUE,
  p256dh TEXT NOT NULL,
  auth TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE push_subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "trainers_own_subscriptions_select" ON push_subscriptions
  FOR SELECT USING (trainer_id = auth.uid());

CREATE POLICY "trainers_own_subscriptions_insert" ON push_subscriptions
  FOR INSERT WITH CHECK (trainer_id = auth.uid());

CREATE POLICY "trainers_own_subscriptions_update" ON push_subscriptions
  FOR UPDATE USING (trainer_id = auth.uid());

CREATE POLICY "trainers_own_subscriptions_delete" ON push_subscriptions
  FOR DELETE USING (trainer_id = auth.uid());

CREATE INDEX idx_push_subscriptions_trainer_id ON push_subscriptions(trainer_id);
;
