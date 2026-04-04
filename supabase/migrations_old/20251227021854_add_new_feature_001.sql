-- ============================================
-- FIT-CONNECT クライアントアプリ
-- データベースマイグレーション
-- ============================================
-- 作成日: 2025-12-20
-- 目的: メッセージベース記録機能の実装
-- ============================================

-- ============================================
-- 1. clients テーブル - 目標管理機能の追加
-- ============================================

-- 目標管理用カラムの追加
ALTER TABLE clients
ADD COLUMN IF NOT EXISTS initial_weight NUMERIC 
  CHECK (initial_weight > 0 AND initial_weight < 500),
ADD COLUMN IF NOT EXISTS goal_deadline DATE,
ADD COLUMN IF NOT EXISTS goal_set_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS goal_achieved_at TIMESTAMPTZ;

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_clients_goal_deadline 
ON clients(goal_deadline) 
WHERE goal_deadline IS NOT NULL;

-- コメント追加
COMMENT ON COLUMN clients.initial_weight IS '開始時体重 (kg) - トレーナーが初回面談時に設定';
COMMENT ON COLUMN clients.goal_deadline IS '目標達成期日（任意）';
COMMENT ON COLUMN clients.goal_set_at IS '目標設定日時';
COMMENT ON COLUMN clients.goal_achieved_at IS '目標達成日時 - 達成時に自動記録';


-- ============================================
-- 2. messages テーブル - タグ・リプライ機能対応
-- ============================================

-- カラム名変更
DO $$ 
BEGIN
  -- message → content
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'message'
  ) THEN
    ALTER TABLE messages RENAME COLUMN message TO content;
  END IF;
  
  -- timestamp → created_at
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'messages' AND column_name = 'timestamp'
  ) THEN
    ALTER TABLE messages RENAME COLUMN timestamp TO created_at;
  END IF;
END $$;

-- 新規カラム追加
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS image_urls TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS tags TEXT[] DEFAULT '{}',
ADD COLUMN IF NOT EXISTS reply_to_message_id UUID REFERENCES messages(id),
ADD COLUMN IF NOT EXISTS read_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS edited_at TIMESTAMPTZ,
ADD COLUMN IF NOT EXISTS is_edited BOOLEAN DEFAULT false,
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_messages_sender_created 
ON messages(sender_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_receiver_created 
ON messages(receiver_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_messages_reply_to 
ON messages(reply_to_message_id)
WHERE reply_to_message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_messages_tags 
ON messages USING GIN(tags);

-- コメント追加
COMMENT ON COLUMN messages.content IS 'メッセージ本文';
COMMENT ON COLUMN messages.image_urls IS '画像URL配列（最大3枚） - Supabase Storageのパス';
COMMENT ON COLUMN messages.tags IS 'タグ配列（例: ["#食事:昼食"]）';
COMMENT ON COLUMN messages.reply_to_message_id IS 'リプライ先メッセージID - トレーナーからのコメント機能';
COMMENT ON COLUMN messages.edited_at IS '編集時刻 - 5分以内の編集が可能';


-- ============================================
-- 3. meal_records テーブル - メッセージ連携
-- ============================================

-- カラム名変更
DO $$ 
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'meal_records' AND column_name = 'description'
  ) THEN
    ALTER TABLE meal_records RENAME COLUMN description TO notes;
  END IF;
END $$;

-- 新規カラム追加
ALTER TABLE meal_records
ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual'
  CHECK (source IN ('manual', 'message')),
ADD COLUMN IF NOT EXISTS message_id UUID REFERENCES messages(id),
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_meal_records_message 
ON meal_records(message_id)
WHERE message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_meal_records_client_date 
ON meal_records(client_id, recorded_at DESC);

-- コメント追加
COMMENT ON COLUMN meal_records.notes IS 'メモ・説明（タグを除いたテキスト）';
COMMENT ON COLUMN meal_records.source IS '記録元（manual: 手動入力, message: メッセージから自動作成）';
COMMENT ON COLUMN meal_records.message_id IS '元メッセージID - メッセージから作成された記録の場合に設定';


-- ============================================
-- 4. weight_records テーブル - メッセージ連携
-- ============================================

-- 新規カラム追加
ALTER TABLE weight_records
ADD COLUMN IF NOT EXISTS notes TEXT,
ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual'
  CHECK (source IN ('manual', 'message')),
ADD COLUMN IF NOT EXISTS message_id UUID REFERENCES messages(id),
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_weight_records_message 
ON weight_records(message_id)
WHERE message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_weight_records_client_date 
ON weight_records(client_id, recorded_at DESC);

-- コメント追加
COMMENT ON COLUMN weight_records.notes IS 'メモ（タグを除いたテキスト）';
COMMENT ON COLUMN weight_records.source IS '記録元（manual: 手動入力, message: メッセージから自動作成）';
COMMENT ON COLUMN weight_records.message_id IS '元メッセージID - メッセージから作成された記録の場合に設定';


-- ============================================
-- 5. exercise_records テーブル - メッセージ連携
-- ============================================

-- exercise_type に 'cardio' を追加
DO $$ 
BEGIN
  -- 既存の制約を削除
  ALTER TABLE exercise_records
  DROP CONSTRAINT IF EXISTS exercise_records_exercise_type_check;
  
  -- 新しい制約を追加
  ALTER TABLE exercise_records
  ADD CONSTRAINT exercise_records_exercise_type_check
  CHECK (exercise_type = ANY (ARRAY[
    'walking'::text, 
    'running'::text, 
    'strength_training'::text, 
    'cardio'::text,
    'cycling'::text, 
    'swimming'::text, 
    'yoga'::text, 
    'pilates'::text, 
    'other'::text
  ]));
END $$;

-- 新規カラム追加
ALTER TABLE exercise_records
ADD COLUMN IF NOT EXISTS source TEXT DEFAULT 'manual'
  CHECK (source IN ('manual', 'message')),
ADD COLUMN IF NOT EXISTS message_id UUID REFERENCES messages(id),
ADD COLUMN IF NOT EXISTS images TEXT[],
ADD COLUMN IF NOT EXISTS created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス追加
CREATE INDEX IF NOT EXISTS idx_exercise_records_message 
ON exercise_records(message_id)
WHERE message_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_exercise_records_client_date 
ON exercise_records(client_id, recorded_at DESC);

-- コメント追加
COMMENT ON COLUMN exercise_records.exercise_type IS '運動種目（cardioは有酸素運動全般）';
COMMENT ON COLUMN exercise_records.source IS '記録元（manual: 手動入力, message: メッセージから自動作成）';
COMMENT ON COLUMN exercise_records.message_id IS '元メッセージID - メッセージから作成された記録の場合に設定';
COMMENT ON COLUMN exercise_records.images IS '画像URL配列（最大3枚） - Supabase Storageのパス';


-- ============================================
-- 6. RLS（Row Level Security）ポリシー
-- ============================================

-- messages テーブルのRLS有効化
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 既存のポリシーを削除（冪等性のため）
DROP POLICY IF EXISTS "Users can view their messages" ON messages;
DROP POLICY IF EXISTS "Users can send messages" ON messages;
DROP POLICY IF EXISTS "Users can edit own messages within 5 minutes" ON messages;

-- 閲覧: 送信者または受信者のみ
CREATE POLICY "Users can view their messages"
ON messages FOR SELECT
USING (
  sender_id = auth.uid() OR 
  receiver_id = auth.uid()
);

-- 作成: 送信者として自分のIDを設定できる
CREATE POLICY "Users can send messages"
ON messages FOR INSERT
WITH CHECK (sender_id = auth.uid());

-- 更新: 送信者のみ、かつ5分以内
CREATE POLICY "Users can edit own messages within 5 minutes"
ON messages FOR UPDATE
USING (
  sender_id = auth.uid() 
  AND (NOW() - created_at) < INTERVAL '5 minutes'
)
WITH CHECK (sender_id = auth.uid());


-- ============================================
-- 7. 関数: メッセージ編集可能チェック
-- ============================================

CREATE OR REPLACE FUNCTION can_edit_message(message_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
  msg_created_at TIMESTAMPTZ;
BEGIN
  SELECT created_at INTO msg_created_at 
  FROM messages 
  WHERE id = message_id;
  
  IF msg_created_at IS NULL THEN
    RETURN false;
  END IF;
  
  RETURN (NOW() - msg_created_at) < INTERVAL '5 minutes';
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION can_edit_message IS 'メッセージが編集可能か（5分以内）を判定';


-- ============================================
-- 8. 関数: 目標達成判定
-- ============================================

CREATE OR REPLACE FUNCTION check_goal_achievement(
  p_client_id UUID,
  p_current_weight NUMERIC
)
RETURNS BOOLEAN AS $$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_is_achieved BOOLEAN;
BEGIN
  -- クライアント情報取得
  SELECT initial_weight, target_weight 
  INTO v_initial_weight, v_target_weight
  FROM clients
  WHERE client_id = p_client_id;
  
  -- 目標が設定されていない場合
  IF v_initial_weight IS NULL OR v_target_weight IS NULL THEN
    RETURN false;
  END IF;
  
  -- 減量目標の場合
  IF v_initial_weight > v_target_weight THEN
    v_is_achieved := p_current_weight <= v_target_weight;
  -- 増量目標の場合
  ELSE
    v_is_achieved := p_current_weight >= v_target_weight;
  END IF;
  
  RETURN v_is_achieved;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION check_goal_achievement IS '目標達成判定（減量・増量両対応）';


-- ============================================
-- 9. 関数: 達成率計算
-- ============================================

CREATE OR REPLACE FUNCTION calculate_achievement_rate(
  p_client_id UUID,
  p_current_weight NUMERIC
)
RETURNS NUMERIC AS $$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_rate NUMERIC;
BEGIN
  -- クライアント情報取得
  SELECT initial_weight, target_weight 
  INTO v_initial_weight, v_target_weight
  FROM clients
  WHERE client_id = p_client_id;
  
  -- 目標が設定されていない場合
  IF v_initial_weight IS NULL OR v_target_weight IS NULL THEN
    RETURN 0;
  END IF;
  
  -- 開始時と目標が同じ場合
  IF v_initial_weight = v_target_weight THEN
    RETURN 0;
  END IF;
  
  -- 達成率計算
  v_rate := (v_initial_weight - p_current_weight) / 
            (v_initial_weight - v_target_weight) * 100;
  
  -- 0%〜100%の範囲に制限
  v_rate := GREATEST(0, LEAST(100, v_rate));
  
  RETURN ROUND(v_rate, 1);
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

COMMENT ON FUNCTION calculate_achievement_rate IS '目標達成率を計算（0〜100%）';


-- ============================================
-- 10. updated_at 自動更新トリガー
-- ============================================

-- トリガー関数
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- messages テーブル
DROP TRIGGER IF EXISTS set_updated_at ON messages;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON messages
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- meal_records テーブル
DROP TRIGGER IF EXISTS set_updated_at ON meal_records;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON meal_records
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- weight_records テーブル
DROP TRIGGER IF EXISTS set_updated_at ON weight_records;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON weight_records
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- exercise_records テーブル
DROP TRIGGER IF EXISTS set_updated_at ON exercise_records;
CREATE TRIGGER set_updated_at
  BEFORE UPDATE ON exercise_records
  FOR EACH ROW
  EXECUTE FUNCTION update_updated_at_column();

-- ============================================
-- 完了
-- ============================================

-- マイグレーション完了を確認
DO $$
BEGIN
  RAISE NOTICE 'マイグレーション完了: FIT-CONNECT クライアントアプリ機能';
  RAISE NOTICE '- clients: 目標管理カラム追加';
  RAISE NOTICE '- messages: タグ・リプライ対応';
  RAISE NOTICE '- meal_records: メッセージ連携';
  RAISE NOTICE '- weight_records: メッセージ連携';
  RAISE NOTICE '- exercise_records: メッセージ連携 + cardio追加';
  RAISE NOTICE '- RLSポリシー設定完了';
  RAISE NOTICE '- ヘルパー関数追加完了';
END $$;