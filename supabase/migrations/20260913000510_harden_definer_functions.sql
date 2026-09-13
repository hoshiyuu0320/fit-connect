-- =============================================================================
-- Migration: harden_definer_functions
-- SECURITY DEFINER 関数 4 本の権限是正（フェーズ5.6）: 公開 anon キーだけで PostgREST から
-- 定義者（postgres）権限で実行できていた 4 本の EXECUTE を呼び出し経路ごとの最小権限に絞り、
-- search_path を空文字に固定する。authenticated に開く calculate_achievement_rate には
-- 本文に呼び出し元チェックを追加する
--
-- 仕様出典: docs/tasks/IMPLEMENTATION_TASKS.md フェーズ5 5.6 / docs/tasks/lessons.md（2026-09-13）
-- テスト:   supabase/tests/definer_functions_privileges_test.sql
--
-- 対象:
--   1. public.calculate_achievement_rate(p_client_id uuid, p_current_weight numeric)
--   2. public.check_goal_achievement(p_client_id uuid, p_current_weight numeric)
--   3. public.issue_recurring_tickets()
--   4. public.mark_messages_as_read(p_other_user_id uuid)
--
-- 背景（2026-09-13 発見）:
--   - リモート（project viribpvnpgtgtmeulcmx）への読み取り専用のカタログ照会と
--     `supabase db dump --linked` で確認した。4 本とも SECURITY DEFINER（owner postgres の
--     ため RLS をバイパスする）で、EXECUTE が PUBLIC / anon / authenticated / service_role に
--     付いていた
--   - リモートでの付与元は Supabase プラットフォームの既定:
--       - PUBLIC: PostgreSQL が関数の作成時に付ける既定の EXECUTE
--       - anon / authenticated / service_role: public スキーマに対する role postgres の
--         default privileges（postgres が関数を作ると 3 ロールへ EXECUTE が付く）
--     20251230131753_remote_schema.sql は、リモートから取り込んだときにこの状態を記録した
--     もの（calculate_achievement_rate は 1153〜1155 行、check_goal_achievement は
--     1165〜1167 行の明示的な GRANT ALL と、ALTER DEFAULT PRIVILEGES）で、リモートの付与の
--     原因ではない（fresh DB でも同じ ACL になる）
--   - search_path は 3 本が未設定、mark_messages_as_read だけ search_path=public
--   - アプリに同梱している公開 anon キーがあれば、誰でも PostgREST の
--     /rest/v1/rpc/<関数名> から呼べた。具体的には:
--       - calculate_achievement_rate: 任意の顧客 UUID を指定して p_current_weight を振ると、
--         その顧客の clients.initial_weight / target_weight（健康データ）を anon が推定できた。
--         weight_records を読むのは initial_weight が NULL のときだけで、その顧客では
--         開始体重として使われる最古の体重記録 1 行の体重が推定できた
--       - check_goal_achievement: 読むのは clients だけ。同様に p_current_weight を振ると、
--         その顧客の target_weight と減量 / 増量の別を anon が推定できた
--       - issue_recurring_tickets: anon が任意のタイミングでチケット発行と payments 行の
--         作成（書込み）を起こせた。処理対象は期日到来済み（status = 'active' かつ
--         next_issue_date <= CURRENT_DATE）のサブスクリプションだけなので、1 回の呼び出しで
--         起きるのは cron が行う発行の前倒しにとどまる。ただしループは行ロックを取らないため、
--         並行して呼ばれると（cron と anon、anon 同士）同じサブスクリプションに tickets と
--         payments が二重発行されうる（tickets / payments には重複を防ぐ一意制約も無い）。
--         これも是正を急ぐ理由の一つ。行ロック（FOR UPDATE SKIP LOCKED）の追加は本 migration
--         では行わず、フォローアップとする
--       - mark_messages_as_read: anon では auth.uid() が NULL で 1 行も一致しないため
--         実害は無いが、anon に公開しておく理由が無い
--
-- 前段の 20260913000500 と分けている理由:
--   - 20260913000500_capture_remote_definer_functions.sql は、リモートで migration を経ずに
--     作成・変更されていた mark_messages_as_read / calculate_achievement_rate の実定義を
--     一文字も変えずに追認する（リモートには no-op）
--   - 本 migration はその上に是正だけを載せる。1 本にまとめると「リモートの現状の追認」と
--     「今回の是正」が同じ差分に混ざり、何を変えたのかをレビューで切り分けられないため
--   - check_goal_achievement（20251230131753）と issue_recurring_tickets（20260712120000 §4）は
--     repo の最新定義がリモートと同一（000500 と同じ dump で比較済み）なので、それを起点にする。
--     同一と確かめたのは dump 時点なので、その後リモートで変わっていないことは適用時に
--     セクション 0 のガードで確かめる
--
-- 方針（呼び出し元の全数調査に基づく最小権限）:
--   呼び出し元は fit-connect/src・fit-connect-mobile/lib・supabase/functions・SQL の関数 /
--   トリガー / ポリシー・cron.job を全数 grep して特定した。4 本を参照する他の SQL 関数・
--   トリガー・ポリシー・ビューは無い。
--
--   関数                        呼び出し元                              是正後の EXECUTE
--   calculate_achievement_rate  Mobile（常に自分の client_id）/           authenticated / service_role
--                               Edge Function parse-message-tags         （+ 本文の呼び出し元チェック）
--   check_goal_achievement      Edge Function parse-message-tags のみ    service_role のみ
--   issue_recurring_tickets     pg_cron 'issue-recurring-tickets' のみ   なし（オーナー postgres のみ）
--   mark_messages_as_read       Mobile（自分宛ての既読化）                authenticated のみ
--   （呼び出し元の詳細は各セクションのコメント参照）
--
--   4 本共通:
--     - SECURITY DEFINER / owner postgres は維持する（実行権限のモデルは変えず、誰が呼べるかと
--       search_path だけを是正する）
--     - SET search_path = '' に固定し、テーブルは public.xxx で完全修飾する（search_path
--       ハイジャック対策。auth.uid() / auth.jwt() は元から修飾済み。組み込みの関数・演算子・
--       型は pg_catalog が暗黙に先頭検索されるため修飾不要）
--     - 署名・戻り値・言語（plpgsql）・揮発性（既定の VOLATILE）は変えない。本文のロジックと
--       コメントもスキーマ修飾以外は変えない（calculate_achievement_rate の呼び出し元チェック
--       追加を除く。行末空白は落としている）
--     - PostgreSQL 既定の PUBLIC への EXECUTE を REVOKE で明示的に剥がし、必要なロールにだけ
--       GRANT する（CREATE OR REPLACE は既存の ACL を保持するため、REVOKE を書かないと
--       権限は何も変わらない）
--     - Supabase Advisor: 0028_anon_security_definer_function_executable は 4 本とも、
--       0011_function_search_path_mutable は search_path 未設定だった 3 本とも解消する。
--       0029_authenticated_security_definer_function_executable（WARN）は authenticated に開く
--       calculate_achievement_rate / mark_messages_as_read で意図どおり残る
--
-- 適用順:
--   - 2026-09-13 夕方の時点で、リモートは 20260913000400（PR #86）まで適用済み（000400 の
--     適用保留は解除された）。000500 と本 migration はその後ろに並び、1 回の
--     `supabase db push` でまとめて適用する（000500 はリモートには no-op で、本 migration が
--     続けて権限を絞る）
--   - リモートに 000510 より新しい版が無い限り --include-all は不要。feature/client-alerts の
--     未適用 migration（20260914000000〜000200）が先にリモートへ適用された場合は、000500 /
--     000510 がリモート最新より前に並ぶため --include-all が必要になる
--   - push 前のオーナー確認: `supabase migration list --linked` と
--     `supabase db push --dry-run` の両方で、未適用が 20260913000500 と 20260913000510 の
--     2 本ちょうどであること。それ以外の版が未適用に並ぶとき、またはリモートにしか無い版が
--     あるとき（PR #86 の 000200〜000400 を取り込んでいないブランチから実行した場合など。
--     `supabase db push` は Remote migration versions not found で止まる）は push しない
--   - push 後の確認: 次の 00:00 UTC の実行後に、cron.job_run_details で
--     issue-recurring-tickets の直近の実行が succeeded になっていること
--     （cron.job_run_details には jobname 列が無いため cron.job と jobid で結合する）:
--       SELECT d.status, d.return_message, d.start_time
--       FROM cron.job_run_details d
--       JOIN cron.job j ON j.jobid = d.jobid
--       WHERE j.jobname = 'issue-recurring-tickets'
--       ORDER BY d.start_time DESC
--       LIMIT 1;
--   - アプリのリリースは不要（既存の呼び出し元はすべてそのまま動く）:
--       - Mobile は calculate_achievement_rate を自分の client_id でだけ呼び、
--         mark_messages_as_read は authenticated として呼ぶ
--       - Edge Function parse-message-tags は service_role キーで呼ぶ
--       - cron は postgres（= 関数オーナー）で実行される
--
-- 影響範囲（2026-09-13 実測。トリガーはローカル DB とリモートの dump の両方で確認）:
--   - Web（fit-connect/src）には 4 本の呼び出し元が無い。トレーナーの既読化は RPC ではなく
--     messages への直接 UPDATE（fit-connect/src/lib/supabase/markMessagesAsRead.ts）なので影響なし
--   - Mobile で新たにエラー（42501 → PostgREST 403）になりうるのは calculate_achievement_rate に
--     他人の client_id を渡した場合だけで、アプリはそれを送らない。check_goal_achievement の
--     Mobile 側呼び出しコードは UI から使われていない（セクション 2 参照）
--   - 関数内で発火するトリガーは search_path = '' のままでも安全（ローカル DB の pg_trigger と、
--     リモートの 2026-09-13 の dump のトリガー定義を照合した。両者は一致している）:
--       - public.messages（mark_messages_as_read の UPDATE）: BEFORE UPDATE の set_updated_at →
--         update_updated_at_column() は両環境とも NOW() しか使わない。on_message_insert
--         （AFTER INSERT）と on_message_update（AFTER UPDATE OF content）は
--         call_parse_message_tags() を呼ぶが、read_at だけの UPDATE ではどちらも発火しない
--       - public.payments（issue_recurring_tickets の INSERT）: トリガーは
--         set_updated_at_payments（BEFORE UPDATE → update_updated_at_column()）だけで、
--         INSERT では発火しない
--       - public.tickets / public.ticket_subscriptions（issue_recurring_tickets の INSERT /
--         UPDATE）: 両環境ともトリガーが無い
--       - 関数の SET search_path は、実行中に発火するトリガー関数にも引き継がれる。
--         これらのテーブルにトリガーを足すときは search_path = '' で動くかを確認すること
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 事前ガード: 2026-09-13 の dump 以降のリモートのドリフト検知
--    本 migration は 4 本を CREATE OR REPLACE で作り直す。そのうち check_goal_achievement と
--    issue_recurring_tickets は repo の定義（20251230131753 / 20260712120000 §4）を起点に
--    しているが、それがリモートと同一だと確かめたのは 2026-09-13 の dump 時点でしかない。
--    push までにリモートで（migration を経ずに）本体が変更されていると、本 migration は
--    その変更を黙って元に戻してしまう。そうならないよう、作り直す前に 4 本の本体
--    （pg_proc.prosrc）の md5 を dump 時点の値と比べ、一致しなければ例外
--    （REMOTE_DRIFT_SINCE_CAPTURE）で migration 全体を失敗させる。関数が存在しない場合も
--    同じ例外で止める。
--
--    期待値（2026-09-13 のリモートの dump から計算）:
--      - check_goal_achievement / issue_recurring_tickets: 本ガードの本題。repo の
--        migration だけで作った DB（fresh DB）の本体とも一致することを確認済み
--      - calculate_achievement_rate / mark_messages_as_read: 直前の 000500 が書いたばかりの
--        本体なので一致するはずで、000500 と本 migration の食い違い（片方だけ編集された等）を
--        捕まえる安価な健全性確認。この 2 本はリモートで変更されていても 000500 が dump の
--        本体で上書きしてしまうため、ここではドリフトを検出できない
--    - 比較するのは本体（prosrc）だけ。SECURITY DEFINER / search_path / ACL は本 migration が
--      明示的に上書きする対象なので比べない
--    - 是正済みの DB（本 migration を適用した後）に本ファイルを流し直すと、本体が変わっている
--      ため必ずこのガードで止まる。migration は 1 回しか適用されないので問題ない
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_fn  record;
  v_oid oid;
  v_md5 text;
BEGIN
  FOR v_fn IN
    SELECT t.signature, t.expected_md5
    FROM (VALUES
      (1, 'public.check_goal_achievement(uuid, numeric)',     'a137a886da3e4fb6fdb377568978fe1e'),
      (2, 'public.issue_recurring_tickets()',                 '7dde1da85d706a8654bccba06dfc10c7'),
      (3, 'public.calculate_achievement_rate(uuid, numeric)', '63224fa010fdbf63db99888fa44a955c'),
      (4, 'public.mark_messages_as_read(uuid)',               'ade028f7cfe7fce41c9a6bfb9f66dd78')
    ) AS t(ord, signature, expected_md5)
    ORDER BY t.ord
  LOOP
    v_oid := to_regprocedure(v_fn.signature);

    IF v_oid IS NULL THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s does not exist (expected md5(prosrc)=%s as of the 2026-09-13 remote dump)',
                v_fn.signature, v_fn.expected_md5
              ),
              HINT    = '2026-09-13 の dump 時点で存在した関数がありません。リモートの現状を確認し、それを追認する migration を先に置いてから再適用してください。';
    END IF;

    SELECT md5(p.prosrc)
    INTO v_md5
    FROM pg_catalog.pg_proc p
    WHERE p.oid = v_oid;

    IF v_md5 IS DISTINCT FROM v_fn.expected_md5 THEN
      RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'function %s has md5(prosrc)=%s, expected %s (2026-09-13 remote dump)',
                v_fn.signature, v_md5, v_fn.expected_md5
              ),
              HINT    = '関数本体が 2026-09-13 の dump 以降に変わっています。このまま適用すると CREATE OR REPLACE がその変更を元に戻すため中止しました。現定義を追認する migration を先に置き、本 migration の本体と期待 md5 をそれに合わせてから再適用してください。';
    END IF;
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 1. calculate_achievement_rate(uuid, numeric)
--    目標達成率（0〜100%）を返す。本体は 20260913000500 で追認したリモート実定義に、
--    冒頭の呼び出し元チェックを足したもの（それ以外の変更はスキーマ修飾のみ）。
--
--    呼び出し元:
--      - Mobile: fit-connect-mobile/lib/features/goals/data/goal_repository.dart の
--        calculateAchievementRate。ホーム画面・体重画面の achievementRateProvider から、
--        常に自分の client_id（= auth.uid()）で呼ぶ
--      - Edge Function parse-message-tags: service_role キーで呼び、達成率をログに出すだけ
--      → EXECUTE は authenticated / service_role
--
--    SECURITY DEFINER の理由（維持）:
--      定義者（postgres = テーブルオーナー）権限で clients / weight_records を RLS を跨いで
--      読む。そのため「誰の達成率を計算してよいか」は RLS ではなく本文冒頭の呼び出し元
--      チェックが決める。authenticated に対してはこれが唯一の防御なので、データを読む前に
--      置く。search_path は空文字に固定し、テーブルは完全修飾（public.clients /
--      public.weight_records）で書く。
--      Advisor の 0029_authenticated_security_definer_function_executable（WARN）は
--      この関数では意図どおり（ログインユーザー全員に開くが、計算できるのは本人と
--      担当顧客の分だけ）
--
--    呼び出し元チェック（auth.uid() / auth.jwt() は変数に 1 回だけ評価する）:
--      - auth.uid() あり（ログインユーザー）: 本人（auth.uid() = p_client_id）か、その顧客の
--        担当トレーナー（public.clients.trainer_id = auth.uid()）のみ許可する
--      - auth.uid() なし: role クレームが service_role（Edge Function）か、JWT クレーム自体が
--        無い（auth.jwt() IS NULL）場合のみ許可する。それ以外（例: role が authenticated /
--        anon なのに sub の無いクレーム）は拒否する
--      - 拒否は RAISE EXCEPTION 'ACHIEVEMENT_RATE_FORBIDDEN'（ERRCODE 42501 =
--        insufficient_privilege。PostgREST は 403 で返す）。DETAIL には拒否の理由だけを入れ、
--        指定された顧客が存在するかどうかは区別しない（他人の client_id の存在確認に使わせない）
--      - role の判定には旧来の auth.role() ではなく auth.jwt() ->> 'role' を使う
--
--    「クレーム無し」を許可してよい理由:
--      - 本 migration 後に EXECUTE を持つのは authenticated / service_role とオーナー
--        postgres だけ
--      - PostgREST は JWT の role クレームを見て DB ロールを切り替えるので、PostgREST 経由で
--        authenticated / service_role として実行される呼び出しには必ず role を含むクレーム
--        （request.jwt.claims）が付いている。したがって「クレーム無し」になりうるのは
--        特権ロールの直接 DB 接続（postgres の SQL エディタ・保守作業・cron）だけ
--      - postgres / service_role はそもそも RLS をバイパスして clients / weight_records を
--        直接読めるので、ここで許可しても新たに読めるものは無い（RLS と同じ扱い）
--      - 許容している既知の抜け: ロールが authenticated で JWT クレームが無い DB セッション
--        （直接 DB 接続で SET ROLE authenticated しただけのもの）は本文チェックを通る。
--        PostgREST 経由では作れず（authenticated / service_role のリクエストには必ず
--        request.jwt.claims が設定される）、作るには直接 DB 接続の資格情報が要り、それを
--        持つ者は元々特権を持っている。current_setting('role') でロールを見て塞ぐことは
--        あえてしない（判定を auth.uid() / auth.jwt() という標準の auth.* ヘルパーだけに
--        寄せておくため）
--
--    anon は GRANT 層と本文の 2 層で止める:
--      - 第 1 の防壁は GRANT 層（anon の EXECUTE 剥奪）
--      - 実際の anon キー / publishable キーのリクエストは sub の無い {"role":"anon"} の
--        クレームを持つので、本文の ELSIF 分岐でも拒否される（本文は第 2 の層）
--      - ただし合成されたセッションに対しては GRANT 層が唯一の防壁になる。クレームが
--        まったく無い anon は本文上「クレーム無し」として許可側に入り、顧客のクレーム
--        （sub = 顧客 UUID）を持つ anon は本人扱いになる（テストの (a) / (b) で固定）。
--        そのため anon の EXECUTE は剥がしたままにすること（戻すとこの 2 つが素通しになる）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.calculate_achievement_rate(p_client_id uuid, p_current_weight numeric)
 RETURNS numeric
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_rate NUMERIC;
  -- 呼び出し元の判定材料（ここで 1 回だけ評価する）
  v_caller_uid uuid := auth.uid();
  v_jwt jsonb := auth.jwt();
BEGIN
  -- 呼び出し元チェック（データを読む前に行う。許可条件の理由は migration の
  -- 20260913000510_harden_definer_functions.sql セクション 1 のコメント参照）
  IF v_caller_uid IS NOT NULL THEN
    -- ログインユーザー: 本人か、その顧客の担当トレーナーのみ。
    -- <> ではなく IS DISTINCT FROM にしているのは、p_client_id が NULL のとき
    -- 条件全体が NULL になって IF を素通り（= 許可）しないようにするため
    IF v_caller_uid IS DISTINCT FROM p_client_id
       AND NOT EXISTS (
         SELECT 1
         FROM public.clients c
         WHERE c.client_id = p_client_id
           AND c.trainer_id = v_caller_uid
       ) THEN
      -- メッセージ文字列 'ACHIEVEMENT_RATE_FORBIDDEN' は固定（呼び出し側の識別用）
      RAISE EXCEPTION 'ACHIEVEMENT_RATE_FORBIDDEN'
        USING ERRCODE = 'insufficient_privilege',
              DETAIL  = format(
                'client_id=%s is neither the caller (uid=%s) nor a client of the caller',
                coalesce(p_client_id::text, 'NULL'), v_caller_uid
              ),
              HINT    = '達成率を計算できるのは、顧客本人とその担当トレーナーだけです。';
    END IF;
  ELSIF v_jwt IS NOT NULL
        AND (v_jwt ->> 'role') IS DISTINCT FROM 'service_role' THEN
    -- sub の無い呼び出しで許可するのは、role クレームが service_role（Edge Function）か、
    -- JWT クレーム自体が無い直接 DB セッション（postgres・cron。auth.jwt() は空文字も
    -- NULL に揃える）だけ。ここに来るのはそれ以外のクレーム（sub の無い authenticated /
    -- anon 等）。role クレームが無いとき ->> は NULL を返すので、= ではなく
    -- IS DISTINCT FROM で比較して拒否側に倒す
    RAISE EXCEPTION 'ACHIEVEMENT_RATE_FORBIDDEN'
      USING ERRCODE = 'insufficient_privilege',
            DETAIL  = format(
              'JWT role=%s without sub is not allowed (only service_role or no JWT claims)',
              coalesce(v_jwt ->> 'role', 'NULL')
            ),
            HINT    = 'sub の無い呼び出しは service_role キー（Edge Function）か直接 DB 接続に限られます。';
  END IF;

  -- クライアント情報取得
  SELECT initial_weight, target_weight
  INTO v_initial_weight, v_target_weight
  FROM public.clients
  WHERE client_id = p_client_id;

  -- 目標が設定されていない場合
  IF v_target_weight IS NULL THEN
    RETURN 0;
  END IF;

  -- initial_weightがNULLの場合、最も古い体重記録を使用
  IF v_initial_weight IS NULL THEN
    SELECT weight INTO v_initial_weight
    FROM public.weight_records
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

COMMENT ON FUNCTION public.calculate_achievement_rate(uuid, numeric) IS
  '目標達成率を計算（0〜100%）。'
  '呼び出しは Mobile の顧客本人（authenticated）と Edge Function parse-message-tags（service_role）。'
  'EXECUTE は authenticated / service_role のみ。本文で呼び出し元を確認し、ログインユーザーは'
  '本人（client_id = auth.uid()）か担当トレーナーだけ、sub の無い呼び出しは role = service_role か'
  'JWT クレーム無し（直接 DB 接続）だけを許可する。それ以外は ACHIEVEMENT_RATE_FORBIDDEN（42501）。'
  '仕様: docs/tasks/IMPLEMENTATION_TASKS.md 5.6 / supabase/migrations/20260913000510_harden_definer_functions.sql';

-- EXECUTE を authenticated / service_role のみに限定
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon への
--   EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.calculate_achievement_rate(uuid, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.calculate_achievement_rate(uuid, numeric) FROM anon;
GRANT EXECUTE ON FUNCTION public.calculate_achievement_rate(uuid, numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.calculate_achievement_rate(uuid, numeric) TO service_role;

-- -----------------------------------------------------------------------------
-- 2. check_goal_achievement(uuid, numeric)
--    目標達成判定（減量・増量両対応）。本体は 20251230131753 の定義（2026-09-13 の dump で
--    リモートと同一。適用時はセクション 0 のガードで再確認する）で、変更は public.clients の
--    修飾のみ。
--
--    呼び出し元:
--      - Edge Function parse-message-tags のみ（service_role キー。体重記録の作成後に達成を
--        判定し、達成なら目標達成通知を送る）
--      - Mobile の GoalRepository.checkGoalAchievement / isGoalAchievedProvider は定義だけで、
--        UI から使われたことは無い（git 履歴で確認）。今後つなぐと 42501（PostgREST 403）に
--        なる。つなぐときは calculate_achievement_rate と同じ呼び出し元チェックを本文に入れて
--        から authenticated に開き直すこと
--      → EXECUTE は service_role のみ
--
--    SECURITY DEFINER の理由（維持）:
--      定義者権限で clients を読む。呼び出せるのは service_role（元々 RLS をバイパスする）と
--      オーナーだけになるため、本文に呼び出し元チェックは置かない。
--      search_path は空文字に固定し、テーブルは完全修飾（public.clients）で書く
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.check_goal_achievement(p_client_id uuid, p_current_weight numeric)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  v_initial_weight NUMERIC;
  v_target_weight NUMERIC;
  v_is_achieved BOOLEAN;
BEGIN
  -- クライアント情報取得
  SELECT initial_weight, target_weight
  INTO v_initial_weight, v_target_weight
  FROM public.clients
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
$function$;

COMMENT ON FUNCTION public.check_goal_achievement(uuid, numeric) IS
  '目標達成判定（減量・増量両対応）。'
  '呼び出しは Edge Function parse-message-tags（service_role）のみで、EXECUTE も service_role のみ。'
  '本文に呼び出し元チェックが無いため、authenticated に開くときは calculate_achievement_rate と同じチェックを先に入れること。'
  '仕様: docs/tasks/IMPLEMENTATION_TASKS.md 5.6 / supabase/migrations/20260913000510_harden_definer_functions.sql';

-- EXECUTE を service_role のみに限定
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon /
--   authenticated への EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.check_goal_achievement(uuid, numeric) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.check_goal_achievement(uuid, numeric) FROM anon;
REVOKE ALL ON FUNCTION public.check_goal_achievement(uuid, numeric) FROM authenticated;
GRANT EXECUTE ON FUNCTION public.check_goal_achievement(uuid, numeric) TO service_role;

-- -----------------------------------------------------------------------------
-- 3. issue_recurring_tickets()
--    月契約（ticket_subscriptions）の定期チケット発行。本体は 20260712120000 §4 の定義
--    （2026-09-13 の dump でリモートと同一。適用時はセクション 0 のガードで再確認する）で、
--    変更は public.ticket_subscriptions / public.ticket_templates / public.tickets /
--    public.payments の修飾のみ。
--
--    呼び出し元:
--      - pg_cron ジョブ 'issue-recurring-tickets'（毎日 00:00 UTC。command は
--        `SELECT issue_recurring_tickets()`、cron.job.username = postgres = 関数オーナー）のみ
--      → anon / authenticated / service_role の EXECUTE をすべて剥がし、GRANT はしない。
--        オーナー postgres は所有者として EXECUTE を持ち続けるので、cron はそのまま動く
--
--    cron.job の command（スキーマ修飾なし）には触れない:
--      関数名は cron セッションの search_path で解決される。関数に付ける SET search_path は
--      関数の実行中にだけ効き、関数名そのものの解決には影響しない
--
--    SECURITY DEFINER の理由（維持）:
--      現行定義どおり。EXECUTE をオーナーだけに絞るため呼び出し者 = 定義者となり、
--      定義者権限で動くこと自体による権限昇格の経路は無くなる。
--      search_path は空文字に固定し、テーブルは完全修飾で書く
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.issue_recurring_tickets()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  sub RECORD;
  new_valid_from DATE;
  new_valid_until DATE;
  new_ticket_id UUID;
BEGIN
  FOR sub IN
    SELECT ts.*, tt.trainer_id, tt.template_name, tt.ticket_type, tt.total_sessions, tt.valid_months, tt.price_yen
    FROM public.ticket_subscriptions ts
    JOIN public.ticket_templates tt ON ts.template_id = tt.id
    WHERE ts.status = 'active'
      AND ts.next_issue_date <= CURRENT_DATE
  LOOP
    new_valid_from := sub.next_issue_date;
    new_valid_until := sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL;

    -- チケット発行（price_yen = 発行時点のテンプレート価格スナップショット）
    INSERT INTO public.tickets (client_id, ticket_name, ticket_type, total_sessions, remaining_sessions, valid_from, valid_until, price_yen)
    VALUES (
      sub.client_id,
      sub.template_name,
      sub.ticket_type,
      sub.total_sessions,
      sub.total_sessions,
      new_valid_from,
      new_valid_until,
      sub.price_yen
    )
    RETURNING id INTO new_ticket_id;

    -- 価格付きテンプレートの場合のみ支払記録（未払い）を自動生成
    IF sub.price_yen IS NOT NULL THEN
      INSERT INTO public.payments (trainer_id, client_id, ticket_id, ticket_subscription_id, amount_yen, status, due_date)
      VALUES (
        sub.trainer_id,
        sub.client_id,
        new_ticket_id,
        sub.id,
        sub.price_yen,
        'unpaid',
        new_valid_from
      );
    END IF;

    -- 次回発行日を翌月に更新
    UPDATE public.ticket_subscriptions
    SET next_issue_date = sub.next_issue_date + (sub.valid_months || ' months')::INTERVAL
    WHERE id = sub.id;
  END LOOP;
END;
$function$;

COMMENT ON FUNCTION public.issue_recurring_tickets() IS
  '月契約（ticket_subscriptions）の定期チケット発行。pg_cron ジョブ issue-recurring-tickets が毎日 00:00 UTC に実行。'
  '20260712120000 で price_yen スナップショットと payments（unpaid）自動生成を追加。'
  'EXECUTE はオーナー postgres（cron ジョブの実行ユーザー）のみで、anon / authenticated / service_role には与えない。'
  '仕様: docs/tasks/IMPLEMENTATION_TASKS.md 5.6 / supabase/migrations/20260913000510_harden_definer_functions.sql';

-- EXECUTE をオーナー（postgres）のみに限定。GRANT は書かない
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon /
--   authenticated / service_role への EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.issue_recurring_tickets() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.issue_recurring_tickets() FROM anon;
REVOKE ALL ON FUNCTION public.issue_recurring_tickets() FROM authenticated;
REVOKE ALL ON FUNCTION public.issue_recurring_tickets() FROM service_role;

-- cron ジョブの実行ユーザーが EXECUTE を失っていないことの確認（ガード）
--   cron.job.username がオーナー以外のロール（例: 別ロールで登録し直された）だった場合、
--   上の REVOKE で毎日のチケット発行が permission denied で止まり、しかも cron の失敗は
--   cron.job_run_details に残るだけで気付けない。そうなる前に例外
--   （CRON_ROLE_LOSES_EXECUTE）で migration 全体を失敗させる。
--   ジョブ行が見つからない場合は WARNING を出して続行する。cron.job には RLS
--   （cron_job_policy: username = CURRENT_USER）があり、postgres が全ジョブを見られるのは
--   BYPASSRLS を持つからにすぎない。行が無いのは「ジョブが本当に無い」のか「適用したロール
--   から見えていない」のかを区別できないため、黙って飛ばさずに手動確認を促す
--   （ジョブが本当に無いなら今回の REVOKE で壊れるものも無いので、是正自体は止めない）。
--   cron.job の一意制約は (jobname, username) で、別ユーザーの同名ジョブがありうるため
--   1 行に決め打ちせず全行を確認する
DO $$
DECLARE
  v_job   record;
  v_found boolean := false;
BEGIN
  FOR v_job IN
    SELECT j.jobid, j.username
    FROM cron.job j
    WHERE j.jobname = 'issue-recurring-tickets'
  LOOP
    v_found := true;
    IF NOT has_function_privilege(v_job.username, 'public.issue_recurring_tickets()', 'EXECUTE') THEN
      RAISE EXCEPTION 'CRON_ROLE_LOSES_EXECUTE'
        USING ERRCODE = 'P0001',
              DETAIL  = format(
                'cron job issue-recurring-tickets (jobid=%s) runs as role %s, which would lose EXECUTE on public.issue_recurring_tickets()',
                v_job.jobid, v_job.username
              ),
              HINT    = 'cron ジョブの実行ユーザーを関数オーナー（postgres）に戻すか、そのロールへの GRANT EXECUTE をこの migration に追加してから再適用してください。';
    END IF;
  END LOOP;

  IF NOT v_found THEN
    RAISE WARNING 'CRON_JOB_NOT_VISIBLE: cron.job に issue-recurring-tickets が見つからないため、実行ユーザーの EXECUTE を確認できなかった'
      USING DETAIL = format(
              'current_user=%s。cron.job は RLS（username = CURRENT_USER）で絞られており、BYPASSRLS の無いロールには他ユーザーのジョブが見えない',
              current_user
            ),
            HINT   = 'postgres で SELECT jobname, username FROM cron.job WHERE jobname = ''issue-recurring-tickets''; を実行し、ジョブの有無と、username が public.issue_recurring_tickets() を EXECUTE できるかを手動で確認してください。';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 4. mark_messages_as_read(uuid)
--    呼び出したユーザー本人宛て（receiver_id = auth.uid()）で、相手（p_other_user_id）から
--    届いた未読メッセージの read_at を now() で埋める。本体は 20260913000500 で追認した
--    リモート実定義で、変更は public.messages の修飾と、SET search_path TO 'public' を
--    SET search_path = '' に置き換えたことのみ。
--
--    呼び出し元:
--      - Mobile: fit-connect-mobile/lib/features/messages/data/message_repository.dart の
--        markConversationAsRead（トーク画面を開いたとき）
--      - Web のトレーナーは RPC ではなく messages への直接 UPDATE
--        （fit-connect/src/lib/supabase/markMessagesAsRead.ts）で既読化するため呼ばない
--      → EXECUTE は authenticated のみ（anon・service_role からも剥がす）
--
--    SECURITY DEFINER の理由（維持）と、呼び出し元チェックを足さない理由:
--      定義者権限で RLS を跨いで UPDATE するが、WHERE receiver_id = auth.uid() が対象を
--      呼び出し者本人の受信箱に固定しており、他人宛てのメッセージには届かない。
--      sub の無い呼び出しでは auth.uid() が NULL となり 1 行も一致しない。
--      search_path は空文字に固定し、テーブルは完全修飾（public.messages）で書く。
--      Advisor の 0029_authenticated_security_definer_function_executable（WARN）は
--      この関数でも意図どおり（ログインユーザー全員に開くが、更新できるのは自分宛ての行だけ）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_other_user_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
BEGIN
  UPDATE public.messages
  SET read_at = now()
  WHERE receiver_id = auth.uid()
    AND sender_id = p_other_user_id
    AND read_at IS NULL;
END;
$function$;

COMMENT ON FUNCTION public.mark_messages_as_read(uuid) IS
  '呼び出したユーザー本人宛て（receiver_id = auth.uid()）で p_other_user_id から届いた未読メッセージを既読（read_at = now()）にする。'
  '呼び出しは Mobile の会話既読化（message_repository.dart の markConversationAsRead）。EXECUTE は authenticated のみ。'
  '仕様: docs/tasks/IMPLEMENTATION_TASKS.md 5.6 / supabase/migrations/20260913000510_harden_definer_functions.sql';

-- EXECUTE を authenticated のみに限定
-- （PUBLIC への既定の EXECUTE と、role postgres の default privileges による anon /
--   service_role への EXECUTE を明示的に剥がす。付与元はヘッダーの「背景」参照）
REVOKE ALL ON FUNCTION public.mark_messages_as_read(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_messages_as_read(uuid) FROM anon;
REVOKE ALL ON FUNCTION public.mark_messages_as_read(uuid) FROM service_role;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(uuid) TO authenticated;
