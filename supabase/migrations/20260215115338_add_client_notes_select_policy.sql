-- Migration: add_client_notes_select_policy
-- Description: クライアントは自分宛てかつ共有済みのノートのみ閲覧可能にするRLSポリシーを追加
--
-- 2026-07-10 スキーマドリフト修復のため加筆。
-- client_notes テーブル本体を作成する migration が欠落しており、空DBからの
-- `supabase db reset` では本ファイルが必ず失敗していた。そのため冒頭に
-- CREATE TABLE IF NOT EXISTS + ENABLE ROW LEVEL SECURITY を追加し、
-- CREATE POLICY を IF NOT EXISTS ガード付き DO ブロックで包んだ。
-- リモートDBでは本 migration は適用済みとして履歴に記録されているため再実行されない
-- （= リモートには一切影響しない）。空DBでの db reset を通すための修復である。
-- テーブル定義は 2026-07-10 時点のリモート実測（schema-drift-facts.md §5）に基づく。

CREATE TABLE IF NOT EXISTS client_notes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id uuid NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,
  trainer_id uuid NOT NULL REFERENCES trainers(id) ON DELETE CASCADE,
  title text NOT NULL,
  content text NOT NULL DEFAULT '',
  file_urls text[] DEFAULT '{}',
  is_shared boolean DEFAULT false,
  shared_at timestamptz,
  session_number integer,
  created_at timestamptz DEFAULT now(),
  updated_at timestamptz DEFAULT now()
);

ALTER TABLE client_notes ENABLE ROW LEVEL SECURITY;

-- クライアントは自分宛てかつ共有済みのノートのみ閲覧可能
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE tablename = 'client_notes' AND policyname = 'clients_select_shared_notes'
  ) THEN
    CREATE POLICY "clients_select_shared_notes" ON client_notes
      FOR SELECT USING (is_shared = true AND client_id = auth.uid());
  END IF;
END $$;
