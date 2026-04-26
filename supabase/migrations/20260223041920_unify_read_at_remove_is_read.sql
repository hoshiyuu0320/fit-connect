
-- is_readインデックス削除
DROP INDEX IF EXISTS idx_messages_receiver_unread;

-- is_readカラム削除
ALTER TABLE messages DROP COLUMN is_read;

-- read_atベースのインデックス追加（未読メッセージ取得の高速化）
CREATE INDEX idx_messages_receiver_unread 
  ON messages (receiver_id) 
  WHERE read_at IS NULL;
;
