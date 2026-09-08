-- =============================================================================
-- client_notes: session_id 追加 + セッション整合性トリガー
-- （セッション⇔ノート紐づけ / レーンA）
--
-- 仕様出典: docs/tasks/2026-09-06-session-note-link-plan.md「レーンA: Supabase」
--
-- 背景: 顧客が過去のセッションをタップして、そのセッションに紐づくトレーナーの
-- 共有ノートへ遷移できるようにしたい。しかし client_notes には session_id が無く、
-- 存在するのは session_number（トレーナーが手入力する通し番号、nullable）だけで、
-- 本番データでは session_number の入力実績が 0 件のため既存データからの推測紐づけは
-- 不可能。そこで sessions への正式な参照列 session_id を新設する。
--
-- 方針:
--   - ON DELETE SET NULL とする。セッションが削除されてもノート本体は残す
--     （ノートはトレーナーの記録資産であり、予定の取り消しで消える性質のものではない）。
--     workout_assignments.session_id が同じ ON DELETE SET NULL であり流儀も揃う
--   - session_number は撤去しない。両者は役割が異なるため COMMENT で明示する
--     （session_number = 表示用の手入力通し番号 / session_id = 実データへの参照）
--   - 「別クライアント / 別トレーナーのセッションへ紐づけられない」ことを DB 側で担保する。
--     Web の API 層（guards.ts の所有検証）と二重で守る。PostgREST 直叩きでの
--     迂回を防ぐため、DB 側の防御が必須（20260712100000 の enforce_client_limit と同じ判断）
--   - RLS には一切触れない。顧客側は既存の clients_select_shared_notes
--     （is_shared = true AND client_id = auth.uid()）がそのまま効き、
--     未共有ノートの存在は顧客に漏れない
--
-- 整合性の担保に複合 FK も CHECK も使えない理由:
--   - 複合 FK（(session_id, client_id, trainer_id) → sessions）には参照先に
--     UNIQUE (id, client_id, trainer_id) が必要で、sessions 側に冗長な一意制約を
--     追加することになる。さらに ON DELETE SET NULL が client_id / trainer_id まで
--     巻き込んで NULL 化しようとするが、両列は NOT NULL のため削除時に必ず失敗する
--   - CHECK 制約はサブクエリを書けないため、参照先の sessions を見に行けない
--   → 残る手段は BEFORE INSERT OR UPDATE トリガーのみ
--
-- 冪等性: ADD COLUMN IF NOT EXISTS / CREATE INDEX IF NOT EXISTS /
--   FK は pg_constraint の存在チェック付き DO ブロック（20260710010002 パターン）/
--   関数は CREATE OR REPLACE / トリガーは DROP IF EXISTS → CREATE。
--   何度再実行しても最終形に収束する。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. session_id 列
--    FK をインラインで書かず分離するのは冪等性のため。ADD COLUMN IF NOT EXISTS に
--    REFERENCES を含めると、列が既に存在する再実行時に FK 追加ごと丸ごと
--    スキップされてしまい、「列はあるが FK は無い」状態を修復できない。
-- -----------------------------------------------------------------------------

ALTER TABLE public.client_notes ADD COLUMN IF NOT EXISTS session_id uuid;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_constraint
    WHERE conname = 'client_notes_session_id_fkey'
      AND conrelid = 'public.client_notes'::regclass
  ) THEN
    ALTER TABLE public.client_notes
      ADD CONSTRAINT client_notes_session_id_fkey
      FOREIGN KEY (session_id) REFERENCES public.sessions(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 用途: セッション一覧から「そのセッションのノート」を引く（Mobile の embed 取得）。
-- 既存の idx_client_notes_client_id / idx_client_notes_trainer_id と同じ流儀。
CREATE INDEX IF NOT EXISTS idx_client_notes_session_id
  ON public.client_notes(session_id);

COMMENT ON COLUMN public.client_notes.session_id IS
  '紐づくセッション（sessions.id）への参照。任意。セッション削除時は NULL になりノート本体は残る。トレーナーが手入力する表示用の通し番号 session_number とは別物で、こちらが実データへの正式な参照。';

COMMENT ON COLUMN public.client_notes.session_number IS
  'トレーナーが手入力する表示用の通し番号（「第3回」等）。sessions への参照ではなく、値の正しさは検証されない。実データとの紐づけは session_id を使うこと。';

-- -----------------------------------------------------------------------------
-- 2. トリガー関数 enforce_client_note_session_consistency()
--
-- SECURITY DEFINER の理由:
--   実行者はトレーナー本人（authenticated）で、sessions の SELECT ポリシーは
--   「auth.uid() = trainer_id」に絞られている。呼び出し者権限のままだと
--   「他トレーナーのセッションを指定した」ケースで参照先 sessions が 0 行になり、
--   NOT FOUND として素通ししてしまう（= 本トリガーの主目的である他人セッションへの
--   紐づけを取りこぼす）。定義者（postgres = テーブルオーナー）権限で RLS を跨いで
--   参照先を必ず見つけるために必要。
--   search_path 固定（public, pg_temp）で search_path ハイジャックを防ぐ。
-- -----------------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public.enforce_client_note_session_consistency()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_session_client_id  uuid;
  v_session_trainer_id uuid;
BEGIN
  -- 紐づけ無しのノートは従来どおり（session_id は任意）。
  -- セッション削除時の ON DELETE SET NULL による UPDATE もここで素通しになる
  IF NEW.session_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT s.client_id, s.trainer_id
    INTO v_session_client_id, v_session_trainer_id
    FROM public.sessions s
   WHERE s.id = NEW.session_id;

  -- 存在しない session_id は FK（client_notes_session_id_fkey）が 23503 で拒否する。
  -- ここで独自に例外を投げると標準的な FK 違反エラーを潰すため、判定材料が無い場合は
  -- FK に委ねて素通しする
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  IF v_session_client_id IS DISTINCT FROM NEW.client_id
     OR v_session_trainer_id IS DISTINCT FROM NEW.trainer_id THEN
    -- メッセージ文字列 'NOTE_SESSION_MISMATCH' は固定。
    -- クライアント側（Web の API Route）はこの文字列でエラーマッチする。変更禁止。
    RAISE EXCEPTION 'NOTE_SESSION_MISMATCH'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'note(client_id=%s trainer_id=%s) vs session(id=%s client_id=%s trainer_id=%s)',
              NEW.client_id, NEW.trainer_id, NEW.session_id,
              v_session_client_id, v_session_trainer_id
            ),
            HINT    = 'ノートは、同じ顧客・同じトレーナーのセッションにのみ紐づけられます。';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_client_note_session_consistency() IS
  'client_notes.session_id が指す sessions の client_id / trainer_id がノート自身のそれと一致することを BEFORE トリガーで強制する。不一致時は NOTE_SESSION_MISMATCH（P0001）。仕様: docs/tasks/2026-09-06-session-note-link-plan.md';

-- -----------------------------------------------------------------------------
-- 3. トリガー enforce_client_note_session_consistency_trigger
--
-- client_notes の既存トリガーは無し（2026-09-06 時点のローカル実測 \d で確認）。
-- UPDATE OF <列名> による絞り込みはしない。session_id を据え置いたまま
-- client_id / trainer_id だけを付け替える UPDATE でも整合性は壊れるため、
-- 全 UPDATE を対象にする。session_id IS NULL の行は関数冒頭で即 RETURN するため、
-- 実質コストは「session_id 付きの行に対する主キー1件引き」だけで済む。
-- -----------------------------------------------------------------------------

DROP TRIGGER IF EXISTS enforce_client_note_session_consistency_trigger
  ON public.client_notes;

CREATE TRIGGER enforce_client_note_session_consistency_trigger
  BEFORE INSERT OR UPDATE ON public.client_notes
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_client_note_session_consistency();
