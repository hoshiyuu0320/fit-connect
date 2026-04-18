
-- 受信者が read_at を更新できるポリシーを追加
CREATE POLICY "Receivers can mark messages as read"
  ON messages
  FOR UPDATE
  USING (receiver_id = auth.uid())
  WITH CHECK (receiver_id = auth.uid());
;
