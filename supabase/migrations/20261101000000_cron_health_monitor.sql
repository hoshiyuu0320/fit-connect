-- =============================================================================
-- Migration: cron_health_monitor
-- cron 失敗の監視（統合判断7-3 / フェーズ5.3 の残り）の DB 側
--
-- 仕様出典: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §3・§4
--
-- 背景:
--   - HTTP の cron は net.http_post を積んだ時点で succeeded になり、結果の net._http_response は
--     6時間で消える。応答の表には URL もジョブ名も残らず webhook の応答も混ざるので、今は応答と
--     ジョブを結び付けられない（2026-09-13 の cleanup-ai-images の 500 は手で SQL を見て偶然見つけた）
--   - そこで HTTP の4本の command を request_id を記録する形に包み、1日2回の確認
--     （Edge Function check-cron-health → run_cron_health_check）で応答と突き合わせる
--
-- 内容:
--   1. public.cron_http_requests: HTTP の cron の発射記録
--   2. public.cron_health_problems: 見つけた問題（source_key で同じ失敗を2回数えない）
--   3. public.cron_http_result_problem(...): 応答1件の分類（純関数）
--   4. public.run_cron_health_check(): 確認の本体（冪等。未通知の問題を返す）
--   5. HTTP の4本の command の書き換え（今の command を読んで先頭だけを置き換える）
--   6. cron ジョブ 'check-cron-health' の登録（無効。有効化はオーナー。設計書 §8）
--   7. 末尾の検査（違えば migration ごと止める）
--
-- 既存の関数は書き換えないのでドリフトガードは要らない。Web / Mobile に影響は無い。
--
-- 前提（実行時ではなくジョブ実行時に必要）:
--   - Vault に `project_url` / `secret_key` の登録が必要（2026-09-12 登録済み）
--   - 'check-cron-health' の command はこの migration の時点では動かない（無効で登録する）。
--     Edge Function の deploy と secret CRON_ALERT_TRAINER_IDS の設定は設計書 §8 の順序で行う
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. cron_http_requests（HTTP の cron の発射記録）
--
--    request_id に PK も UNIQUE も付けない（重要）: net.http_request_queue_id_seq は UNLOGGED で、
--    DB の異常終了や復元の後は 1 に戻るので、request_id は長期的に一意ではない。一意制約があると
--    cron の INSERT が重複で失敗し、同じトランザクションの net.http_post も巻き戻って、本番の HTTP の
--    cron が飛ばなくなる（設計書 §2・§4.1）。行の識別は id（source_key の req:<id>）で行う
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cron_http_requests (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  request_id bigint NOT NULL,
  jobname text NOT NULL,
  requested_at timestamptz NOT NULL DEFAULT now(),
  checked_at timestamptz
);

COMMENT ON TABLE public.cron_http_requests IS
  'HTTP の cron の発射記録。4本の command が net.http_post の戻り値をここに INSERT し、'
  'run_cron_health_check が net._http_response と突き合わせる。'
  'RLS 有効・ポリシー無し・postgres（所有者）以外の権限無し。'
  '仕様: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §4.1';
COMMENT ON COLUMN public.cron_http_requests.request_id IS
  'net.http_post の戻り値（net._http_response.id）。番号は DB の異常終了や復元の後に 1 に戻るので、'
  '一意制約を付けてはいけない（付けると cron の INSERT が失敗し、同じトランザクションの HTTP も飛ばなくなる）';
COMMENT ON COLUMN public.cron_http_requests.requested_at IS
  '発射した時刻。応答はこの時刻以降のものだけを見る（番号が戻っても古い応答を拾わない）';
COMMENT ON COLUMN public.cron_http_requests.checked_at IS
  '応答を評価した時刻。NULL は未評価';

CREATE INDEX IF NOT EXISTS idx_cron_http_requests_unchecked
  ON public.cron_http_requests (requested_at)
  WHERE checked_at IS NULL;

-- -----------------------------------------------------------------------------
-- 2. cron_health_problems（見つけた問題）
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.cron_health_problems (
  id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  source_key text NOT NULL UNIQUE,
  jobname text NOT NULL,
  kind text NOT NULL
    CHECK (kind IN ('job_failed', 'missed_run', 'http_error', 'no_response', 'bad_result')),
  occurred_at timestamptz NOT NULL,
  summary text NOT NULL,
  detail text,
  notified_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.cron_health_problems IS
  'cron の監視が見つけた問題。run_cron_health_check が記録し、check-cron-health が通知して notified_at を埋める。'
  'RLS 有効・ポリシー無し。service_role は SELECT と UPDATE (notified_at) だけ。'
  '仕様: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §4.1';
COMMENT ON COLUMN public.cron_health_problems.source_key IS
  '同じ失敗を2回数えないためのキー。run:<cron.job_run_details.runid> / req:<cron_http_requests.id> / '
  'missed:<jobname>:<予定時刻の epoch>。request_id は長期的に一意でないので使わない';
COMMENT ON COLUMN public.cron_health_problems.jobname IS
  'ジョブ名。cron.job から消えたジョブは jobid:<id>';
COMMENT ON COLUMN public.cron_health_problems.kind IS
  'job_failed（cron の失敗・止まった行）/ missed_run（予定時刻に動かなかった）/ http_error（2xx 以外）/ '
  'no_response（タイムアウト・接続失敗・結果不明）/ bad_result（2xx だが中身が失敗）';
COMMENT ON COLUMN public.cron_health_problems.occurred_at IS
  '起きた時刻（cron の実行・発射の時刻、または予定時刻）。実行の時刻が両方 NULL の行は記録した時刻';
COMMENT ON COLUMN public.cron_health_problems.summary IS
  '短い説明。通知の本文に出す（ロック画面に出してよい内容だけ。例: HTTP 500 / 失敗 / 未実行）';
COMMENT ON COLUMN public.cron_health_problems.detail IS
  '詳細（200 文字まで。例外の文言や応答の本文の先頭）。通知にも Edge Function の返り値にも出さない';
COMMENT ON COLUMN public.cron_health_problems.notified_at IS
  '通知が1人以上に届いた時刻。NULL の間は確認のたびに通知し直す';

-- -----------------------------------------------------------------------------
-- 権限（両表）
--   20251230131753_remote_schema.sql の ALTER DEFAULT PRIVILEGES により、表とシーケンスには
--   anon / authenticated / service_role へ GRANT ALL が自動で付くので、いったん全て剥がす。
--   RLS は有効でポリシーは作らない。cron の command は postgres（所有者）で動くので INSERT できる。
--   Edge Function（service_role）が読むのは未通知の問題と notified_at だけ
-- -----------------------------------------------------------------------------
ALTER TABLE public.cron_http_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.cron_health_problems ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON TABLE public.cron_http_requests FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON TABLE public.cron_health_problems FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.cron_http_requests_id_seq FROM PUBLIC, anon, authenticated, service_role;
REVOKE ALL ON SEQUENCE public.cron_health_problems_id_seq FROM PUBLIC, anon, authenticated, service_role;

GRANT SELECT ON TABLE public.cron_health_problems TO service_role;
GRANT UPDATE (notified_at) ON TABLE public.cron_health_problems TO service_role;

-- -----------------------------------------------------------------------------
-- 3. cron_http_result_problem(p_jobname, p_status_code, p_timed_out, p_error_msg, p_content)
--    応答1件を分類する純関数（表を読まないので単体でテストできる）。
--    問題なしなら0行、問題ありなら (kind, summary, detail) の1行を上から順の判定で返す（設計書 §4.2）。
--      timed_out = true か、error_msg が Timeout で始まる → no_response / タイムアウト
--      error_msg あり（接続失敗など）                    → no_response / 接続失敗
--      2xx 以外                                         → http_error  / HTTP <code>
--      status_code が NULL（pg_net は返さないはずの形）  → bad_result  / 応答が不正
--      2xx で content が NULL・JSON でない・オブジェクトでない → bad_result / 応答が不正
--      dryRun か dry_run が true                        → bad_result  / dry run のまま
--      notify-trainer-alerts で detectionReady が false → bad_result  / 自動チェック未完了
--      notify-trainer-alerts で outcome がオブジェクトでない（null は notification_logs を読み直せなかったとき。
--        DB の障害で送信も失敗している場面に出る）       → bad_result  / 送信結果不明
--      notify-trainer-alerts で outcome の failed + pending + missing + skippedBy.vapid ≥ 1
--                                                       → bad_result  / 送信失敗 N件
--    send-session-reminders の outcome.failed は見ない（FCM→APNs の既知の不達で毎回のように出るため。§10）。
--    cleanup-ai-images の failed も見ない（次回の実行に回る設計）。
--    想定外の例外（JSON でない content の ::jsonb、数でない件数）は WHEN others で bad_result / 応答が不正 に
--    する（1件のせいで確認全体を 500 にしない）。
--    pg_net 0.14.0 はタイムアウトでも timed_out を埋めない（status_code も timed_out も NULL で、error_msg が
--    'Timeout of 60000 ms reached. Total time: ...'。接続失敗も timed_out は NULL。実際の応答で確認）。
--    timed_out だけを見るとタイムアウトが 接続失敗 になるので error_msg も見る。
--    format() は STABLE なので使わない（整数の text へのキャストと || は IMMUTABLE）
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.cron_http_result_problem(
  p_jobname text,
  p_status_code integer,
  p_timed_out boolean,
  p_error_msg text,
  p_content text
)
RETURNS TABLE (kind text, summary text, detail text)
LANGUAGE plpgsql
IMMUTABLE
SET search_path = ''
AS $$
DECLARE
  c_detail_max constant integer := 200;
  v_head text := left(p_content, c_detail_max);
  v_body jsonb;
  v_outcome jsonb;
  v_failed bigint;
BEGIN
  IF p_timed_out IS TRUE OR p_error_msg ILIKE 'timeout%' THEN
    RETURN QUERY SELECT 'no_response'::text, 'タイムアウト'::text, left(p_error_msg, c_detail_max);
    RETURN;
  END IF;

  IF p_error_msg IS NOT NULL THEN
    RETURN QUERY SELECT 'no_response'::text, '接続失敗'::text, left(p_error_msg, c_detail_max);
    RETURN;
  END IF;

  IF p_status_code IS NULL THEN
    RETURN QUERY SELECT 'bad_result'::text, '応答が不正'::text, v_head;
    RETURN;
  END IF;

  IF p_status_code NOT BETWEEN 200 AND 299 THEN
    RETURN QUERY SELECT 'http_error'::text, 'HTTP ' || p_status_code::text, v_head;
    RETURN;
  END IF;

  v_body := p_content::jsonb;
  IF jsonb_typeof(v_body) IS DISTINCT FROM 'object' THEN
    RETURN QUERY SELECT 'bad_result'::text, '応答が不正'::text, v_head;
    RETURN;
  END IF;

  IF v_body -> 'dryRun' = 'true'::jsonb OR v_body -> 'dry_run' = 'true'::jsonb THEN
    RETURN QUERY SELECT 'bad_result'::text, 'dry run のまま'::text, v_head;
    RETURN;
  END IF;

  IF p_jobname = 'notify-trainer-alerts' THEN
    IF v_body -> 'detectionReady' = 'false'::jsonb THEN
      RETURN QUERY SELECT 'bad_result'::text, '自動チェック未完了'::text, v_head;
      RETURN;
    END IF;

    v_outcome := v_body -> 'outcome';
    IF jsonb_typeof(v_outcome) IS DISTINCT FROM 'object' THEN
      RETURN QUERY SELECT 'bad_result'::text, '送信結果不明'::text, v_head;
      RETURN;
    END IF;

    v_failed := COALESCE((v_outcome ->> 'failed')::bigint, 0)
              + COALESCE((v_outcome ->> 'pending')::bigint, 0)
              + COALESCE((v_outcome ->> 'missing')::bigint, 0)
              + COALESCE((v_outcome -> 'skippedBy' ->> 'vapid')::bigint, 0);
    IF v_failed >= 1 THEN
      RETURN QUERY SELECT 'bad_result'::text, '送信失敗 ' || v_failed::text || '件', v_head;
      RETURN;
    END IF;
  END IF;
EXCEPTION
  WHEN others THEN
    RETURN QUERY SELECT 'bad_result'::text, '応答が不正'::text, left(COALESCE(p_content, SQLERRM), c_detail_max);
END;
$$;

COMMENT ON FUNCTION public.cron_http_result_problem(text, integer, boolean, text, text) IS
  'net._http_response の1件を分類する純関数。問題なしなら0行、問題ありなら (kind, summary, detail) の1行。'
  '呼ぶのは run_cron_health_check だけ（EXECUTE は postgres のみ）。'
  '仕様: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §4.2';

REVOKE ALL ON FUNCTION public.cron_http_result_problem(text, integer, boolean, text, text)
  FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 4. run_cron_health_check()
--    SECURITY DEFINER（cron.job_run_details / cron.job / net._http_response を読むため）・search_path = ''。
--    引数なし（本実行に時刻を差し込める口を作らない。テストは now() からの相対で行を作る）。
--    冪等で、何度呼んでも source_key で重複しない。dry run の呼び出しでも記録は行う（設計書 §5）。
--
--    手順（設計書 §4.3）:
--      1. SQL・HTTP 共通の失敗（job_failed / run:<runid>）
--      2. 動かなかった毎日のジョブ（missed_run / missed:<jobname>:<epoch>）
--      3. HTTP の応答（req:<cron_http_requests.id>）
--      4. 掃除
--      5. 未通知の問題を返す
--
--    返す並びは id の昇順（記録した順 = 古い順）。occurred_at の順にすると、後から見つかった問題が
--    途中に入っても「最初の id」「最後の id」が変わらず、Edge Function の dedup キーが同じになり、
--    送っていない問題まで通知済みになってしまう（同じ時間内に確認を手で流し直したとき）
--
--    plpgsql の RETURNS TABLE の戻り列名（id・jobname など）が表の列名と重なるので
--    #variable_conflict use_column を付け、そのうえで列はすべて別名で修飾する
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.run_cron_health_check()
RETURNS TABLE (
  id bigint,
  jobname text,
  kind text,
  summary text,
  detail text,
  occurred_at timestamptz
)
LANGUAGE plpgsql
VOLATILE
SECURITY DEFINER
SET search_path = ''
AS $$
#variable_conflict use_column
DECLARE
  -- ===== 定数（閾値はここ1箇所。根拠は設計書 §4.3）=====
  -- 失敗・予定時刻・結果不明を見る窓。そろえておくと、確認が2回続けて落ちても見逃さない
  c_window         constant interval := interval '48 hours';
  -- succeeded 以外のままこの時間を過ぎた行は止まったものとみなす
  c_stuck_after    constant interval := interval '1 hour';
  -- 予定時刻はこの時間より前のものだけを見る（動き始める前の誤検知を避ける）
  c_missed_grace   constant interval := interval '5 minutes';
  -- 予定時刻の前後のこの範囲に実行があれば「動いた」
  c_run_before     constant interval := interval '1 minute';
  c_run_after      constant interval := interval '1 hour';
  -- この間に1回も動いていないジョブは見ない（有効化した直後に誤って出さない。手順2の EXISTS も参照）
  c_recent_run     constant interval := interval '7 days';
  -- 応答が無くてもこの時間までは待つ（次の確認に回す）
  c_response_grace constant interval := interval '15 minutes';
  -- 掃除の保持期間
  c_retention      constant interval := interval '90 days';
  c_detail_max     constant integer  := 200;

  v_tz text := COALESCE(NULLIF(current_setting('cron.timezone', true), ''), 'GMT');
  v_request record;
  v_response record;
BEGIN
  -- ---------------------------------------------------------------------------
  -- 1. SQL・HTTP 共通の失敗
  --    時刻は COALESCE(start_time, end_time) で見る（起動前に失敗した行は start_time が NULL）。
  --    時刻がどちらも NULL の failed（starting のまま DB が再起動した行）は窓で判定できないので常に見る
  --    （source_key で1回だけ。occurred_at は記録した時刻）。
  --    止まった行は時刻があるものだけ（時刻が無い starting は経過時間が分からない。pg_cron が次の起動で
  --    failed にする）
  -- ---------------------------------------------------------------------------
  INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary, detail)
  SELECT
    'run:' || d.runid,
    COALESCE(j.jobname, 'jobid:' || COALESCE(d.jobid::text, '不明')),
    'job_failed',
    COALESCE(d.start_time, d.end_time, now()),
    CASE WHEN d.status = 'failed' THEN '失敗' ELSE '未完了' END,
    left(d.return_message, c_detail_max)
  FROM cron.job_run_details d
  LEFT JOIN cron.job j ON j.jobid = d.jobid
  WHERE (
      d.status = 'failed'
      AND (COALESCE(d.start_time, d.end_time) IS NULL
           OR COALESCE(d.start_time, d.end_time) >= now() - c_window)
    ) OR (
      d.status IS DISTINCT FROM 'failed'
      AND d.status IS DISTINCT FROM 'succeeded'
      AND COALESCE(d.start_time, d.end_time) >= now() - c_window
      AND COALESCE(d.start_time, d.end_time) < now() - c_stuck_after
    )
  ON CONFLICT (source_key) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- 2. 動かなかった毎日のジョブ（DB の再起動などで pg_cron は取り戻さない）
  --    対象は active で schedule が M H * * * の形のジョブ（inactive は人が止めたもの。
  --    監視自身の 40 11,21 * * * などの他の形も見ない）。
  --    予定時刻は cron.timezone の暦日 + M H を cron.timezone で解釈して求める（呼び出したセッションの
  --    TimeZone に左右されない。generate_series に date を渡すと timestamptz になるので使わない）。
  --    jobname が NULL のジョブもありうる（cron.schedule の2引数版）。NOT NULL 違反で確認全体を止めない。
  --    見るのは、この7日に動いていて、かつ「その予定時刻より前に実行がある」ジョブの予定だけ。新設のジョブや
  --    7日以上止めて再開したジョブが今日初めて動くと、まだ動いていなかった昨日の予定時刻（窓の中）を
  --    未実行にしてしまうため
  -- ---------------------------------------------------------------------------
  INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary)
  SELECT
    'missed:' || COALESCE(j.jobname, 'jobid:' || j.jobid) || ':' || extract(epoch FROM s.scheduled_at)::bigint,
    COALESCE(j.jobname, 'jobid:' || j.jobid),
    'missed_run',
    s.scheduled_at,
    '未実行'
  FROM cron.job j
  CROSS JOIN LATERAL regexp_match(
    j.schedule,
    '^\s*([0-5]?[0-9])\s+([01]?[0-9]|2[0-3])\s+\*\s+\*\s+\*\s*$'
  ) AS m(parts)
  CROSS JOIN LATERAL (
    SELECT (((now() AT TIME ZONE v_tz)::date - n) + make_time(m.parts[2]::integer, m.parts[1]::integer, 0))
             AT TIME ZONE v_tz AS scheduled_at
    FROM generate_series(0, 3) AS n
  ) s
  WHERE j.active
    AND m.parts IS NOT NULL
    AND s.scheduled_at >= now() - c_window
    AND s.scheduled_at <= now() - c_missed_grace
    AND EXISTS (
      SELECT 1
      FROM cron.job_run_details d
      WHERE d.jobid = j.jobid
        AND COALESCE(d.start_time, d.end_time) >= now() - c_recent_run
        AND COALESCE(d.start_time, d.end_time) < s.scheduled_at - c_run_before
    )
    AND NOT EXISTS (
      SELECT 1
      FROM cron.job_run_details d
      WHERE d.jobid = j.jobid
        AND COALESCE(d.start_time, d.end_time) >= s.scheduled_at - c_run_before
        AND COALESCE(d.start_time, d.end_time) <= s.scheduled_at + c_run_after
    )
  ON CONFLICT (source_key) DO NOTHING;

  -- ---------------------------------------------------------------------------
  -- 3. HTTP の応答
  --    r.created >= q.requested_at で番号が戻っても古い応答を拾わない。番号が戻った後に同じ番号の応答が
  --    複数あれば、発射の後で最初の応答がこの要求のもの
  -- ---------------------------------------------------------------------------
  FOR v_request IN
    SELECT q.id, q.jobname, q.request_id, q.requested_at
    FROM public.cron_http_requests q
    WHERE q.checked_at IS NULL
    ORDER BY q.id
  LOOP
    SELECT r.status_code, r.timed_out, r.error_msg, r.content
      INTO v_response
    FROM net._http_response r
    WHERE r.id = v_request.request_id
      AND r.created >= v_request.requested_at
    ORDER BY r.created
    LIMIT 1;

    IF FOUND THEN
      INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary, detail)
      SELECT
        'req:' || v_request.id,
        v_request.jobname,
        p.kind,
        v_request.requested_at,
        p.summary,
        p.detail
      FROM public.cron_http_result_problem(
        v_request.jobname,
        v_response.status_code,
        v_response.timed_out,
        v_response.error_msg,
        v_response.content
      ) p
      ON CONFLICT (source_key) DO NOTHING;
    ELSIF v_request.requested_at >= now() - c_response_grace THEN
      -- 応答待ち（次の確認に回す）
      CONTINUE;
    ELSIF v_request.requested_at >= now() - c_window THEN
      -- pg_net の停止か、6時間を過ぎて応答が消えた
      INSERT INTO public.cron_health_problems (source_key, jobname, kind, occurred_at, summary)
      VALUES ('req:' || v_request.id, v_request.jobname, 'no_response', v_request.requested_at, '結果不明')
      ON CONFLICT (source_key) DO NOTHING;
    END IF;
    -- 窓より古い応答なしは問題にしない（監視を止めて再開したときに、実際は正常だったジョブの
    -- 結果不明が山になるのを防ぐ）

    UPDATE public.cron_http_requests q
       SET checked_at = now()
     WHERE q.id = v_request.id;
  END LOOP;

  -- ---------------------------------------------------------------------------
  -- 4. 掃除（どちらも手順 1〜3 の窓より十分古いので、消しても同じ問題が記録し直されない）
  --    例外は時刻がどちらも NULL の failed の問題: 手順 1 の窓で外れないので、cron.job_run_details に
  --    行が残っている間は消さない（消すと記録し直されて、同じ失敗をもう1回通知する）
  -- ---------------------------------------------------------------------------
  DELETE FROM public.cron_http_requests q
   WHERE q.requested_at < now() - c_retention;

  DELETE FROM public.cron_health_problems p
   WHERE p.notified_at < now() - c_retention
     AND NOT EXISTS (
       SELECT 1
       FROM cron.job_run_details d
       WHERE COALESCE(d.start_time, d.end_time) IS NULL
         AND p.source_key = 'run:' || d.runid
     );

  -- ---------------------------------------------------------------------------
  -- 5. 未通知の問題を古い順（id の昇順）に返す
  -- ---------------------------------------------------------------------------
  RETURN QUERY
    SELECT p.id, p.jobname, p.kind, p.summary, p.detail, p.occurred_at
    FROM public.cron_health_problems p
    WHERE p.notified_at IS NULL
    ORDER BY p.id;
END;
$$;

COMMENT ON FUNCTION public.run_cron_health_check() IS
  'cron の確認の本体。cron の失敗・動かなかった毎日のジョブ・HTTP の応答を見て cron_health_problems に記録し、'
  '未通知の問題を id の昇順で返す。冪等（source_key で重複しない）。呼ぶのは Edge Function check-cron-health（service_role）。'
  '仕様: docs/superpowers/specs/2026-11-01-cron-failure-monitor-design.md §4.3';

REVOKE ALL ON FUNCTION public.run_cron_health_check() FROM PUBLIC, anon, authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.run_cron_health_check() TO service_role;

-- -----------------------------------------------------------------------------
-- 5. HTTP の4本の command の書き換え
--    書き写さず、今の cron.job.command を読み、先頭の `SELECT net.http_post(` を
--    `INSERT INTO public.cron_http_requests (jobname, request_id) SELECT '<job>', net.http_post(` に
--    置き換えて戻す（url・headers・body・timeout は変えない。send-session-reminders の `+ 1` のような式を
--    写し間違えない）。先頭がこの形でなければ止める。すでに包まれていれば飛ばす。
--    cron.alter_job は command 以外の引数を渡さなければ schedule / active を変えない。
--    cron.job は RLS（username = CURRENT_USER）があり、postgres が全ジョブを見られるのは BYPASSRLS による。
--    見えなければ件数 0 として止まる（黙って通さない）
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_jobname text;
  v_count integer;
  v_jobid bigint;
  v_command text;
BEGIN
  FOREACH v_jobname IN ARRAY ARRAY[
    'auto-skip-workouts', 'cleanup-ai-images', 'send-session-reminders', 'notify-trainer-alerts'
  ] LOOP
    SELECT count(*), min(j.jobid), min(j.command)
      INTO v_count, v_jobid, v_command
    FROM cron.job j
    WHERE j.jobname = v_jobname;

    IF v_count <> 1 THEN
      RAISE EXCEPTION 'CRON_HEALTH_MONITOR_UNEXPECTED_COMMAND'
        USING ERRCODE = 'P0001',
              DETAIL  = format('cron job %s: %s row(s) (expected 1)', v_jobname, v_count);
    END IF;

    IF position('public.cron_http_requests' IN v_command) > 0 THEN
      CONTINUE;
    END IF;

    IF v_command !~ '^\s*SELECT\s+net\.http_post\(' THEN
      RAISE EXCEPTION 'CRON_HEALTH_MONITOR_UNEXPECTED_COMMAND'
        USING ERRCODE = 'P0001',
              DETAIL  = format('cron job %s: command does not start with SELECT net.http_post( (%s)',
                               v_jobname, left(v_command, 80));
    END IF;

    PERFORM cron.alter_job(
      v_jobid,
      command := regexp_replace(
        v_command,
        '^(\s*)SELECT\s+net\.http_post\(',
        '\1INSERT INTO public.cron_http_requests (jobname, request_id) SELECT '
          || quote_literal(v_jobname) || ', net.http_post('
      )
    );
  END LOOP;
END $$;

-- -----------------------------------------------------------------------------
-- 6. cron ジョブ 'check-cron-health' の新規登録（無効状態）
--    毎日 11:40 / 21:40 UTC（JST 20:40 / 06:40）に Edge Function `check-cron-health` を呼ぶ。
--      06:40 は 03:00〜06:10 の4本を6時間以内に読め、朝のうちに検知を流し直せる。
--      20:40 は 09:00 と 20:00 の2本を読め、その晩のうちにリマインダーを手で送り直せる。
--    url の組み立て（関数名を除く）・headers・timeout は他の HTTP の cron と同じ（20261004000000）。
--    自身は cron_http_requests に記録しない（応答が次の確認まで残らず、自分の失敗を自分では通知できないため）。
--    同名のジョブが無いときだけ登録し、登録直後に無効にする（有効化はオーナー。設計書 §8）。
--
--    ※ DO ブロック自体の $$ と衝突しないよう、command 文字列は名前付きドル引用 $cmd$ で書く
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM cron.job WHERE jobname = 'check-cron-health') THEN
    PERFORM cron.schedule(
      'check-cron-health',
      '40 11,21 * * *',
      $cmd$
      SELECT net.http_post(
        url := (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'project_url') || '/functions/v1/check-cron-health',
        headers := jsonb_build_object(
          'Content-Type', 'application/json',
          'apikey', (SELECT decrypted_secret FROM vault.decrypted_secrets WHERE name = 'secret_key')
        ),
        body := '{"dry_run": false}'::jsonb,
        timeout_milliseconds := 60000
      );
      $cmd$
    );

    -- 作成直後に無効化（有効化はオーナー判断）
    PERFORM cron.alter_job(
      (SELECT jobid FROM cron.job WHERE jobname = 'check-cron-health'),
      active := false
    );
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 7. 最終形の検査（違えば migration ごと止める）
--    - 4本の command: public.cron_http_requests を含み、先頭が記録の INSERT で、url のジョブ名と
--      timeout_milliseconds := 60000 が残っている
--    - send-session-reminders: `+ 1` の式が残っている
--    - check-cron-health: 1件・無効・schedule 40 11,21 * * *・記録しない
--    - 権限（REVOKE は自分が付与した権限しか剥がさないので最終形を見る）と関数の属性・RLS
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  c_columns constant text[] := ARRAY[
    'id', 'source_key', 'jobname', 'kind', 'occurred_at', 'summary', 'detail', 'created_at'
  ];
  c_run constant regprocedure := 'public.run_cron_health_check()'::regprocedure;
  c_classify constant regprocedure :=
    'public.cron_http_result_problem(text, integer, boolean, text, text)'::regprocedure;
  v_jobname text;
  v_role text;
  v_column text;
  v_command text;
  v_count integer;
  v_schedule text;
  v_active boolean;
  -- 最初に見つけた違い（最後の RAISE の DETAIL になる）
  v_problem text;
BEGIN
  -- 4本の command
  FOREACH v_jobname IN ARRAY ARRAY[
    'auto-skip-workouts', 'cleanup-ai-images', 'send-session-reminders', 'notify-trainer-alerts'
  ] LOOP
    SELECT count(*), min(j.command) INTO v_count, v_command
    FROM cron.job j
    WHERE j.jobname = v_jobname;

    IF v_count <> 1 THEN
      v_problem := format('cron job %s: %s row(s) (expected 1)', v_jobname, v_count);
    ELSIF v_command !~ ('^\s*INSERT INTO public\.cron_http_requests \(jobname, request_id\) SELECT '''
                        || v_jobname || ''', net\.http_post\(') THEN
      v_problem := format('cron job %s: command does not record to public.cron_http_requests (%s)',
                          v_jobname, left(v_command, 120));
    ELSIF position('/functions/v1/' || v_jobname IN v_command) = 0 THEN
      v_problem := format('cron job %s: url lost the job name', v_jobname);
    ELSIF v_command !~ 'timeout_milliseconds\s*:=\s*60000\M' THEN
      v_problem := format('cron job %s: timeout_milliseconds := 60000 is missing', v_jobname);
    END IF;
    EXIT WHEN v_problem IS NOT NULL;
  END LOOP;

  -- send-session-reminders の + 1 の式
  IF v_problem IS NULL THEN
    SELECT j.command INTO v_command FROM cron.job j WHERE j.jobname = 'send-session-reminders';
    IF v_command !~ '::date\s*\+\s*1\M' THEN
      v_problem := 'cron job send-session-reminders: target_date lost the + 1';
    END IF;
  END IF;

  -- check-cron-health
  IF v_problem IS NULL THEN
    SELECT count(*), min(j.schedule), bool_and(j.active), min(j.command)
      INTO v_count, v_schedule, v_active, v_command
    FROM cron.job j
    WHERE j.jobname = 'check-cron-health';

    IF v_count <> 1 THEN
      v_problem := format('cron job check-cron-health: %s row(s) (expected 1)', v_count);
    ELSIF v_schedule IS DISTINCT FROM '40 11,21 * * *' OR v_active IS DISTINCT FROM false THEN
      v_problem := format('cron job check-cron-health: schedule=%s active=%s (expected ''40 11,21 * * *'' / false)',
                          v_schedule, v_active);
    ELSIF position('cron_http_requests' IN v_command) > 0 THEN
      v_problem := 'cron job check-cron-health: must not record to cron_http_requests';
    END IF;
  END IF;

  -- 権限: anon / authenticated / service_role
  IF v_problem IS NULL THEN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated', 'service_role'] LOOP
      IF has_table_privilege(v_role, 'public.cron_http_requests', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
         OR has_any_column_privilege(v_role, 'public.cron_http_requests', 'SELECT, INSERT, UPDATE, REFERENCES')
         OR has_sequence_privilege(v_role, 'public.cron_http_requests_id_seq', 'USAGE, SELECT, UPDATE')
         OR has_sequence_privilege(v_role, 'public.cron_health_problems_id_seq', 'USAGE, SELECT, UPDATE')
         OR has_function_privilege(v_role, c_classify, 'EXECUTE') THEN
        v_problem := format('%s has a privilege on cron_http_requests, a sequence or cron_http_result_problem', v_role);
      END IF;
      EXIT WHEN v_problem IS NOT NULL;
    END LOOP;
  END IF;

  IF v_problem IS NULL THEN
    FOREACH v_role IN ARRAY ARRAY['anon', 'authenticated'] LOOP
      IF has_table_privilege(v_role, 'public.cron_health_problems', 'SELECT, INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
         OR has_any_column_privilege(v_role, 'public.cron_health_problems', 'SELECT, INSERT, UPDATE, REFERENCES')
         OR has_function_privilege(v_role, c_run, 'EXECUTE') THEN
        v_problem := format('%s has a privilege on cron_health_problems or run_cron_health_check', v_role);
      END IF;
      EXIT WHEN v_problem IS NOT NULL;
    END LOOP;
  END IF;

  IF v_problem IS NULL THEN
    IF NOT has_table_privilege('service_role', 'public.cron_health_problems', 'SELECT')
       OR has_table_privilege('service_role', 'public.cron_health_problems', 'INSERT, UPDATE, DELETE, TRUNCATE, REFERENCES, TRIGGER')
       OR NOT has_column_privilege('service_role', 'public.cron_health_problems', 'notified_at', 'UPDATE')
       OR NOT has_function_privilege('service_role', c_run, 'EXECUTE') THEN
      v_problem := 'service_role privileges are not SELECT + UPDATE (notified_at) on cron_health_problems + EXECUTE on run_cron_health_check';
    END IF;
    FOREACH v_column IN ARRAY c_columns LOOP
      IF has_column_privilege('service_role', 'public.cron_health_problems', v_column, 'UPDATE') THEN
        v_problem := format('service_role can UPDATE cron_health_problems.%s', v_column);
      END IF;
    END LOOP;
  END IF;

  -- 権限: PUBLIC（proacl / relacl の grantee = 0）
  IF v_problem IS NULL AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    CROSS JOIN LATERAL aclexplode(COALESCE(p.proacl, acldefault('f', p.proowner))) a
    WHERE p.oid IN (c_run, c_classify) AND a.grantee = 0
  ) THEN
    v_problem := 'PUBLIC has EXECUTE on a function';
  END IF;

  IF v_problem IS NULL AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    CROSS JOIN LATERAL aclexplode(c.relacl) a
    WHERE c.oid IN ('public.cron_http_requests'::regclass, 'public.cron_health_problems'::regclass,
                    'public.cron_http_requests_id_seq'::regclass, 'public.cron_health_problems_id_seq'::regclass)
      AND a.grantee = 0
  ) THEN
    v_problem := 'PUBLIC has a privilege on a table or sequence';
  END IF;

  -- 関数の属性（search_path は proconfig::text で比べると失敗する）・RLS
  IF v_problem IS NULL AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    WHERE p.oid = c_run AND p.prosecdef AND p.provolatile = 'v' AND 'search_path=""' = ANY (p.proconfig)
  ) THEN
    v_problem := 'run_cron_health_check is not SECURITY DEFINER / VOLATILE / search_path = ''''';
  END IF;

  IF v_problem IS NULL AND NOT EXISTS (
    SELECT 1
    FROM pg_catalog.pg_proc p
    WHERE p.oid = c_classify AND NOT p.prosecdef AND p.provolatile = 'i' AND 'search_path=""' = ANY (p.proconfig)
  ) THEN
    v_problem := 'cron_http_result_problem is not SECURITY INVOKER / IMMUTABLE / search_path = ''''';
  END IF;

  IF v_problem IS NULL AND EXISTS (
    SELECT 1
    FROM pg_catalog.pg_class c
    WHERE c.oid IN ('public.cron_http_requests'::regclass, 'public.cron_health_problems'::regclass)
      AND NOT c.relrowsecurity
  ) THEN
    v_problem := 'row level security is not enabled';
  END IF;

  IF v_problem IS NOT NULL THEN
    RAISE EXCEPTION 'CRON_HEALTH_MONITOR_POSTCHECK_FAILED'
      USING ERRCODE = 'P0001',
            DETAIL  = v_problem;
  END IF;
END $$;
