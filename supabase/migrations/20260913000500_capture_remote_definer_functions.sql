-- =============================================================================
-- Migration: capture_remote_definer_functions
-- SECURITY DEFINER 関数の権限是正の前段: リモートDBで migration を経ずに作成・変更され
-- repo と食い違っていた SECURITY DEFINER 関数 2 本の実定義を追認する（純粋な追認）
--
-- 出典:
--   2026-09-13 にリモートDB（project viribpvnpgtgtmeulcmx）へ読み取り専用で実行した
--   `supabase db dump --linked --schema public`（pg_dump）の出力。
--   本ファイルでは dump の書式（識別子を二重引用符で囲み、本体を $$ で囲む）ではなく、
--   pg_get_functiondef の書式（識別子は引用符なし、本体は $function$ で囲む）で書いている。
--   書式が違うのは本体の外側だけで、下記 2 本の関数本体（$function$ 〜 $function$ の間）は
--   行末空白・空白のみの行も含めてリモートと一文字も違わない（整形・スキーマ修飾・
--   不具合修正は一切しない）。一致は md5(prosrc) で確認済み:
--     mark_messages_as_read      = ade028f7cfe7fce41c9a6bfb9f66dd78
--     calculate_achievement_rate = 63224fa010fdbf63db99888fa44a955c
--
-- 目的:
--   ローカルの migration 履歴だけで、関数本体を含めてリモートの「現状」をそのまま
--   再現できるようにする。権限と search_path の是正は次の
--   20260913000510_harden_definer_functions.sql で行う。追認と是正を別 migration に
--   分けることで、000510 の差分を「是正した内容」だけにする。
--
-- 追認するドリフト（2026-09-13 実測）:
--   1. public.mark_messages_as_read(p_other_user_id uuid) … リモートにのみ存在
--      - 2026-02-08 に Mobile の既読機能のため migration を経ずにリモートへ作成された。
--        repo のどの migration にも定義が無く、supabase_migrations.schema_migrations
--        にも該当する行が無い
--      - Mobile が RPC で呼んでいる（fit-connect-mobile/lib/features/messages/data/
--        message_repository.dart の markConversationAsRead）。空DBからの reset 環境には
--        関数が無いため、この RPC は失敗していた
--      - リモート実属性: RETURNS void / LANGUAGE plpgsql / SECURITY DEFINER /
--        SET search_path TO 'public' / owner postgres / COMMENT なし
--   2. public.calculate_achievement_rate(p_client_id uuid, p_current_weight numeric)
--      … 本体がリモートでのみ変更されていた
--      - repo には 20251230131753_remote_schema.sql の旧本体が残っている。
--        変更点は下記「2.」のセクションコメント参照
--      - リモート実属性: RETURNS numeric / LANGUAGE plpgsql / SECURITY DEFINER /
--        search_path 設定なし / owner postgres /
--        COMMENT '目標達成率を計算（0〜100%）'（repo と同一）
--   ※ 同じ dump で比較した check_goal_achievement / issue_recurring_tickets は
--     ローカルとリモートで定義が同一だったため対象外
--
-- リモートには no-op である理由:
--   - 2 本とも、リモートの実定義と本体・属性が同一の CREATE OR REPLACE のため、
--     適用しても定義は一切変化しない
--   - CREATE OR REPLACE FUNCTION は既存関数の owner と ACL をそのまま保持する
--   - COMMENT ON FUNCTION もリモートと同一の文字列を再設定するだけ
--   - この前提（リモートの本体が 2026-09-13 のまま）は、冒頭の「0. ドリフトガード」が
--     適用時に確かめる。崩れていれば何も変更せずに中止する
--
-- fresh DB（空DBからの reset）での効果:
--   - mark_messages_as_read が新規作成され、Mobile の会話既読化 RPC が動くようになる
--   - calculate_achievement_rate がリモートと同じ本体に置き換わる
--
-- 権限（GRANT / REVOKE をあえて書かない理由）:
--   - リモートの ACL は 2 本とも EXECUTE が PUBLIC / anon / authenticated / service_role
--     （dump に REVOKE ... FROM PUBLIC は無い）
--   - リモートでこれらの EXECUTE を付けたのは migration ではなく、Supabase プラットフォームの
--     既定値である:
--       * PostgreSQL 既定で、関数の作成時に PUBLIC へ付く EXECUTE
--       * public スキーマで role postgres が作る関数向けの default privileges
--         （anon / authenticated / service_role へ付与）
--   - 20251230131753_remote_schema.sql はこれを記録している:
--       * calculate_achievement_rate への明示の GRANT ALL ... TO anon / authenticated /
--         service_role（1153〜1155 行目）
--       * ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public ... ON FUNCTIONS
--         （1262 行目付近）
--     fresh DB ではこれらで同じ ACL が再現される。calculate_achievement_rate は
--     20251230131753 の時点で、mark_messages_as_read は本 migration で postgres が
--     新規作成した時点で、リモートと同じ ACL になる
--   - リモートでは CREATE OR REPLACE が既存の ACL を保持するため、ここでも変化しない
--   - よって本 migration に GRANT / REVOKE は要らない
--   - RLS をバイパスする SECURITY DEFINER 関数を anon を含む全ロールが実行できる状態は
--     過剰であり、次の 20260913000510 で権限を絞る。migration 履歴上この状態が残るのは
--     本 migration と 000510 の間だけ
--
-- タイムスタンプの位置:
--   2026-09-13 夕方の `supabase migration list --linked` で、リモートには
--   20260913000400（PR #86 の migration）まで適用済みで、これがリモートの最新だった。
--   本 migration（000500）と次の 000510 はそれより後ろに並ぶため、`supabase db push` に
--   --include-all は不要。
--   この前提は、20260913000510 より新しい migration が先にリモートへ届かない限り成り立つ。
--   別ブランチ feature/client-alerts にリモート未適用の 20260914000000〜20260914000200 が
--   あり、そちらが先に push された場合は --include-all が必要になる。
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. ドリフトガード（2026-09-13 の追認以降にリモートの本体が変わっていないかの確認）
--    本 migration は 2026-09-13 に取得したリモートの本体で CREATE OR REPLACE する。
--    dump の取得からオーナーの push までの間にリモートで本体が変更されていると、
--    そのまま適用すればその変更を黙って 2026-09-13 時点の本体へ巻き戻してしまう。
--    それを防ぐため、何かを変更する前に現在の本体の md5(prosrc) を確かめ、想定外なら
--    例外（REMOTE_DRIFT_SINCE_CAPTURE）で migration 全体を失敗させる。
--    許容する状態:
--      - calculate_achievement_rate(uuid, numeric): 存在必須。md5(prosrc) が次のどちらか
--          85d36c6b006fbc4fe030acd7860ed3de … 20251230131753 の旧本体（fresh DB）
--          63224fa010fdbf63db99888fa44a955c … 2026-09-13 のリモート本体
--                                               （= 本 migration が書き込む本体）
--      - mark_messages_as_read(uuid): fresh DB には無いので、不在は許容。
--        存在する場合は md5(prosrc) が次に一致すること
--          ade028f7cfe7fce41c9a6bfb9f66dd78 … 2026-09-13 のリモート本体
--                                               （= 本 migration が書き込む本体）
--    md5 はどれも、定義を実際に CREATE したあとの md5(prosrc) を DB で読んだ値。
--    下の 1. / 2. の本体を変えるときは、ここの md5 も合わせて更新すること。
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  c_hint        constant text   := 'リモートの定義が 2026-09-13 の追認以降に変わっている。supabase db dump --linked で取り直し、本 migration の本体を更新してから再適用すること';
  c_car_allowed constant text[] := ARRAY[
    '85d36c6b006fbc4fe030acd7860ed3de',  -- 20251230131753 の旧本体（fresh DB）
    '63224fa010fdbf63db99888fa44a955c'   -- 2026-09-13 のリモート本体
  ];
  c_mmr_allowed constant text   := 'ade028f7cfe7fce41c9a6bfb9f66dd78';  -- 2026-09-13 のリモート本体
  v_md5         text;
BEGIN
  -- calculate_achievement_rate(uuid, numeric): 存在必須
  --   関数が無ければ to_regprocedure が NULL を返して行が取れず、SELECT INTO は v_md5 を NULL にする
  SELECT md5(p.prosrc)
    INTO v_md5
    FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.calculate_achievement_rate(uuid, numeric)');

  IF v_md5 IS NULL OR NOT (v_md5 = ANY (c_car_allowed)) THEN
    RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'function=%s current_md5=%s allowed_md5=%s',
              'public.calculate_achievement_rate(uuid, numeric)',
              coalesce(v_md5, '(function not found)'),
              array_to_string(c_car_allowed, ' or ')
            ),
            HINT    = c_hint;
  END IF;

  -- mark_messages_as_read(uuid): 不在（fresh DB）は許容。存在すればリモート本体と一致すること
  SELECT md5(p.prosrc)
    INTO v_md5
    FROM pg_proc p
   WHERE p.oid = to_regprocedure('public.mark_messages_as_read(uuid)');

  IF v_md5 IS NOT NULL AND v_md5 <> c_mmr_allowed THEN
    RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'function=%s current_md5=%s allowed_md5=%s',
              'public.mark_messages_as_read(uuid)',
              v_md5,
              c_mmr_allowed
            ),
            HINT    = c_hint;
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. mark_messages_as_read(uuid) の追認
--    Mobile の既読機能（2026-02-08）でリモートDBに直接作成されていた関数。
--    自分宛て（receiver_id = auth.uid()）で相手（p_other_user_id）から届いた
--    未読メッセージの read_at を now() で埋める。
--    2026-09-13 リモート実測の実定義を一言一句そのまま収録
--    （リモートでは同一定義への CREATE OR REPLACE のため実質 no-op。
--      fresh DB では新規作成となる）。リモートに COMMENT は無いため付けない。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_other_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  UPDATE messages
  SET read_at = now()
  WHERE receiver_id = auth.uid()
    AND sender_id = p_other_user_id
    AND read_at IS NULL;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. calculate_achievement_rate(uuid, numeric) の追認
--    目標達成率（0〜100%）を返す関数。Mobile（goals/data/goal_repository.dart）と
--    Edge Function parse-message-tags が RPC で呼ぶ。
--    20251230131753 の旧本体からの変更点（リモートで migration を経ずに変更）:
--      - 目標体重が未設定なら 0（旧本体と同じ）
--      - clients.initial_weight が NULL のとき、旧本体は 0 を返していたが、
--        weight_records の最古の記録（recorded_at 昇順の先頭）を開始体重として使う
--      - 開始体重が得られない場合（体重記録も無い）と、開始体重と目標体重が
--        同じ場合は、現在体重が目標体重と一致すれば 100、それ以外は 0 を返す
--        （旧本体はどちらも 0 固定）
--    2026-09-13 リモート実測の実定義を一言一句そのまま収録
--    （同一定義への CREATE OR REPLACE のため実質 no-op）。
--    本体の行末空白・空白のみの行もリモートどおりなので、整形で消さないこと。
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_achievement_rate(p_client_id uuid, p_current_weight numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
AS $function$
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
  IF v_target_weight IS NULL THEN
    RETURN 0;
  END IF;
  
  -- initial_weightがNULLの場合、最も古い体重記録を使用
  IF v_initial_weight IS NULL THEN
    SELECT weight INTO v_initial_weight
    FROM weight_records
    WHERE client_id = p_client_id
    ORDER BY recorded_at ASC
    LIMIT 1;
    
    -- 体重記録もない場合
    IF v_initial_weight IS NULL THEN
      IF p_current_weight = v_target_weight THEN
        RETURN 100;
      ELSE
        RETURN 0;
      END IF;
    END IF;
  END IF;
  
  -- 開始時と目標が同じ場合（ゼロ除算防止）
  IF v_initial_weight = v_target_weight THEN
    IF p_current_weight = v_target_weight THEN
      RETURN 100;
    ELSE
      RETURN 0;
    END IF;
  END IF;
  
  -- 達成率計算
  v_rate := (v_initial_weight - p_current_weight) / 
            (v_initial_weight - v_target_weight) * 100;
  
  -- 0%〜100%の範囲に制限
  v_rate := GREATEST(0, LEAST(100, v_rate));
  
  RETURN ROUND(v_rate, 1);
END;
$function$;

-- COMMENT もリモート（= 20251230131753）と同一の文字列を再設定する（実質 no-op）
COMMENT ON FUNCTION public.calculate_achievement_rate(uuid, numeric) IS '目標達成率を計算（0〜100%）';
