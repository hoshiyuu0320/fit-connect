
-- is_readカラム追加（既存レコードは全てtrue = 既読）
ALTER TABLE messages ADD COLUMN is_read BOOLEAN NOT NULL DEFAULT true;

-- 今後の新規メッセージはデフォルトfalse（未読）にする
ALTER TABLE messages ALTER COLUMN is_read SET DEFAULT false;

-- インデックス追加（未読メッセージ取得の高速化）
CREATE INDEX idx_messages_receiver_unread 
  ON messages (receiver_id, is_read) 
  WHERE is_read = false;
;
