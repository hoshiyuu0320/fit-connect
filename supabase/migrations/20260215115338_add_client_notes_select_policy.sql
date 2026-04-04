-- Migration: add_client_notes_select_policy
-- Description: クライアントは自分宛てかつ共有済みのノートのみ閲覧可能にするRLSポリシーを追加

-- クライアントは自分宛てかつ共有済みのノートのみ閲覧可能
CREATE POLICY "clients_select_shared_notes" ON client_notes
  FOR SELECT USING (is_shared = true AND client_id = auth.uid());
