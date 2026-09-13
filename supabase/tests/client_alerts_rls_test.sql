-- =============================================================================
-- alerts / alert_detection_runs の RLS・権限と、検知関数の EXECUTE 権限テスト
-- （フェーズ9.1 / 20260914000000_client_alerts.sql + 20260914000100_client_activity_snapshot.sql
--   + 20260914000200_client_alert_detection.sql）
--
-- 統合判断（docs/tasks/2026-07-10-integration-decisions.md §RLS の CI テスト）
-- 「新規 RLS ポリシー追加時は anon/authenticated/他人ロールでのアクセス可否を
--  検証するテストを supabase/tests/ に追加する」に基づく自己完結テスト
-- （sessions_rls_test.sql / notification_prefs_logs_rls_test.sql のパターン踏襲）。
--
-- 実行方法（FIT-CONNECT リポジトリルートから。ローカル Supabase スタック起動中）:
--   docker exec -i supabase_db_fit-connect psql -U postgres -d postgres \
--     -v ON_ERROR_STOP=1 -f - < supabase/tests/client_alerts_rls_test.sql
--
-- - 全ケース成功時のみ最終行に「ALL CLIENT ALERTS RLS TESTS PASSED」が出力される
-- - 期待と異なる挙動があれば RAISE EXCEPTION 'FAIL: ...' で即座に異常終了する
-- - 試験データは BEGIN...ROLLBACK 内で作成され、DB には一切残らない。
--   get_alert_detection_status の last_* を確かめるため、冒頭で alert_detection_runs を
--   DELETE する（ROLLBACK で戻る）
-- - alerts の件数は必ず試験用の行（AL1〜AL4）に限定して数える
--
-- 検証ケース（計画書 PR1 レーンA-4）:
--   (a) 担当トレーナー A には自分の顧客のアラートが見える（resolved の行も含む）
--   (b) 他のトレーナー B には A のアラートが 0 行（B は自分の分だけ見える）
--   (c) 担当が A → B に替わった後、前のトレーナー A には 0 行（行の trainer_id は A のまま =
--       本実行で reassigned に閉じる前でも見えない）。新しい担当 B にも見えない
--   (d) 顧客本人には自分についてのアラートも 0 行
--   (e-1) anon（JWT クレーム無し）: SELECT が permission denied（42501）
--   (e-2) anon（JWT クレームにトレーナー A の UUID）: 同じく 42501。さらに、anon にテーブルの
--         SELECT を一時的に GRANT しても 0 行（ポリシーが TO authenticated に限られていることの
--         直接検証。テーブル権限を剥がしているので、GRANT しないと TO 句を外しても差が出ない）
--   (f) authenticated（トレーナー A）の INSERT / UPDATE / DELETE は insufficient_privilege（42501）
--   (g) alert_detection_runs は anon・authenticated とも SELECT / INSERT が 42501
--   (h) EXECUTE: service_role 専用の3関数（client_activity_snapshot / evaluate_client_alerts /
--       run_client_alert_detection）は authenticated と anon（クレーム無し・付き）で 42501。
--       get_alert_detection_status は anon（クレーム無し・付き）で 42501、トレーナーは実行でき、
--       トレーナー B が呼んでも A の顧客は人数に入らない、顧客が呼ぶと 0 行。
--       last_* は alert_detection_runs の最新行、enabled は cron.job の active
--   (i) service_role は alerts に INSERT / UPDATE / DELETE できる
--   (j) メタデータ: ポリシーは SELECT 1本（TO authenticated）でサブクエリの列が
--       alerts.client_id に解決されている（pg_get_expr）/ テーブル・関数の権限
-- =============================================================================

\set ON_ERROR_STOP on

BEGIN;

-- -----------------------------------------------------------------------------
-- 試験データ作成（postgres として実行。RLS バイパス）
--   trainer A : aaaaaaaa-0914-0000-0000-00000000000a
--   trainer B : bbbbbbbb-0914-0000-0000-00000000000b
--   client CA : cccccccc-0914-0000-0000-0000000000c1（A の顧客。3日前に登録・記録なし → 監視対象）
--   client CB : cccccccc-0914-0000-0000-0000000000c2（B の顧客。3日前に登録 → 監視対象）
--   client CR : cccccccc-0914-0000-0000-0000000000c3（A の顧客 → ケース(c) で B に担当替え。2日前に登録）
--   client CN : cccccccc-0914-0000-0000-0000000000c4（A の顧客。auth.users に行が無い → no_account）
--   client CS : cccccccc-0914-0000-0000-0000000000c5（A の顧客。20日前に登録・記録なし → not_started）
--   client CI : cccccccc-0914-0000-0000-0000000000c6（A の顧客。40日前に登録、30日前の体重のみ → inactive）
--   alert AL1 : a1a1a1a1-0914-0000-0000-000000000001（CA / trainer A / record_gap / open）
--   alert AL2 : a1a1a1a1-0914-0000-0000-000000000002（CB / trainer B / weight_change / open）
--   alert AL3 : a1a1a1a1-0914-0000-0000-000000000003（CR / trainer A / record_gap / acknowledged）
--   alert AL4 : a1a1a1a1-0914-0000-0000-000000000004（CA / trainer A / weight_change / resolved）
-- -----------------------------------------------------------------------------
\echo '--- setup: 試験データ作成 (trainer A・B / client CA・CB・CR・CN・CS・CI / alert AL1〜AL4)'

DELETE FROM public.alert_detection_runs;

INSERT INTO auth.users (
  id, instance_id, aud, role, email, encrypted_password,
  email_confirmed_at, created_at, updated_at,
  raw_app_meta_data, raw_user_meta_data,
  confirmation_token, email_change, email_change_token_new, recovery_token
)
SELECT v.id::uuid, '00000000-0000-0000-0000-000000000000',
       'authenticated', 'authenticated', v.email, 'x',
       now(), now(), now(), '{"provider":"email","providers":["email"]}', '{}', '', '', '', ''
  FROM (VALUES
    ('aaaaaaaa-0914-0000-0000-00000000000a', 'rls-test-alerts-a@example.com'),
    ('bbbbbbbb-0914-0000-0000-00000000000b', 'rls-test-alerts-b@example.com'),
    ('cccccccc-0914-0000-0000-0000000000c1', 'rls-test-alerts-ca@example.com'),
    ('cccccccc-0914-0000-0000-0000000000c2', 'rls-test-alerts-cb@example.com'),
    ('cccccccc-0914-0000-0000-0000000000c3', 'rls-test-alerts-cr@example.com'),
    ('cccccccc-0914-0000-0000-0000000000c5', 'rls-test-alerts-cs@example.com'),
    ('cccccccc-0914-0000-0000-0000000000c6', 'rls-test-alerts-ci@example.com')
  ) AS v(id, email);

-- 顧客数の上限（enforce_client_limit）に掛からないよう business にしておく
INSERT INTO public.trainers (id, name, email, subscription_plan) VALUES
  ('aaaaaaaa-0914-0000-0000-00000000000a', 'RLSテスト アラート トレーナーA',
   'rls-test-alerts-a@example.com', 'business'),
  ('bbbbbbbb-0914-0000-0000-00000000000b', 'RLSテスト アラート トレーナーB',
   'rls-test-alerts-b@example.com', 'business');

INSERT INTO public.clients (client_id, name, trainer_id, created_at) VALUES
  ('cccccccc-0914-0000-0000-0000000000c1', 'RLSテスト顧客CA',
   'aaaaaaaa-0914-0000-0000-00000000000a', now() - interval '3 days'),
  ('cccccccc-0914-0000-0000-0000000000c2', 'RLSテスト顧客CB',
   'bbbbbbbb-0914-0000-0000-00000000000b', now() - interval '3 days'),
  ('cccccccc-0914-0000-0000-0000000000c3', 'RLSテスト顧客CR',
   'aaaaaaaa-0914-0000-0000-00000000000a', now() - interval '2 days'),
  ('cccccccc-0914-0000-0000-0000000000c4', 'RLSテスト顧客CN',
   'aaaaaaaa-0914-0000-0000-00000000000a', now() - interval '3 days'),
  ('cccccccc-0914-0000-0000-0000000000c5', 'RLSテスト顧客CS',
   'aaaaaaaa-0914-0000-0000-00000000000a', now() - interval '20 days'),
  ('cccccccc-0914-0000-0000-0000000000c6', 'RLSテスト顧客CI',
   'aaaaaaaa-0914-0000-0000-00000000000a', now() - interval '40 days');

-- CI は記録がある（not_started ではない）が、最後に届いたのが30日前（inactive）
INSERT INTO public.weight_records (client_id, weight, recorded_at, source, created_at, updated_at) VALUES
  ('cccccccc-0914-0000-0000-0000000000c6', 60.0,
   now() - interval '30 days', 'manual', now() - interval '30 days', now() - interval '30 days');

-- 日付の列は JST の今日（d）を基準にする（値そのものは RLS の判定に関係しない）
INSERT INTO public.alerts (
  id, trainer_id, client_id, alert_type, severity, status, payload,
  first_detected_on, surfaced_on, last_detected_on, acknowledged_at, resolved_at, resolved_reason
)
SELECT v.id::uuid, v.trainer_id::uuid, v.client_id::uuid, v.alert_type, v.severity, v.status,
       v.payload::jsonb, t.d - v.days_ago, t.d - v.days_ago, t.d - v.days_ago,
       CASE WHEN v.status = 'acknowledged' THEN now() END,
       CASE WHEN v.status = 'resolved' THEN now() END,
       CASE WHEN v.status = 'resolved' THEN 'expired' END
  FROM (SELECT (now() AT TIME ZONE 'Asia/Tokyo')::date AS d) t
 CROSS JOIN (VALUES
    ('a1a1a1a1-0914-0000-0000-000000000001', 'aaaaaaaa-0914-0000-0000-00000000000a',
     'cccccccc-0914-0000-0000-0000000000c1', 'record_gap', 'medium', 'open',
     '{"v":1,"variant":"not_started"}', 0),
    ('a1a1a1a1-0914-0000-0000-000000000002', 'bbbbbbbb-0914-0000-0000-00000000000b',
     'cccccccc-0914-0000-0000-0000000000c2', 'weight_change', 'high', 'open', '{"v":1}', 0),
    ('a1a1a1a1-0914-0000-0000-000000000003', 'aaaaaaaa-0914-0000-0000-00000000000a',
     'cccccccc-0914-0000-0000-0000000000c3', 'record_gap', 'medium', 'acknowledged',
     '{"v":1,"variant":"no_data"}', 0),
    ('a1a1a1a1-0914-0000-0000-000000000004', 'aaaaaaaa-0914-0000-0000-00000000000a',
     'cccccccc-0914-0000-0000-0000000000c1', 'weight_change', 'high', 'resolved', '{"v":1}', 20)
  ) AS v(id, trainer_id, client_id, alert_type, severity, status, payload, days_ago);

-- get_alert_detection_status の enabled の期待値（cron.job は authenticated から読めないので、
-- postgres のうちにトランザクション内の設定値として控えておく）
DO $$
BEGIN
  PERFORM set_config(
    'alerts_rls_test.expected_enabled',
    coalesce((SELECT bool_or(j.active) FROM cron.job j WHERE j.jobname = 'detect-client-alerts'), false)::text,
    true
  );
END $$;

-- -----------------------------------------------------------------------------
-- ケース(a): 担当トレーナー A には自分の顧客のアラートが見える
--   auth.uid() は request.jwt.claims (JSON) の sub、または旧形式
--   request.jwt.claim.sub から解決されるため両方設定する
-- -----------------------------------------------------------------------------
\echo '--- case a: 担当トレーナー(A) に AL1・AL3・AL4 が見え、AL2 は見えないこと'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
DECLARE
  v_got  uuid[];
BEGIN
  v_got := ARRAY(
    SELECT a.id FROM public.alerts a
     WHERE a.id IN ('a1a1a1a1-0914-0000-0000-000000000001',
                    'a1a1a1a1-0914-0000-0000-000000000002',
                    'a1a1a1a1-0914-0000-0000-000000000003',
                    'a1a1a1a1-0914-0000-0000-000000000004')
     ORDER BY a.id);
  IF v_got IS DISTINCT FROM ARRAY['a1a1a1a1-0914-0000-0000-000000000001',
                                  'a1a1a1a1-0914-0000-0000-000000000003',
                                  'a1a1a1a1-0914-0000-0000-000000000004']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: トレーナー(A) に見えるアラートが %（期待 AL1・AL3・AL4）', v_got;
  END IF;
  RAISE NOTICE 'OK: トレーナー(A) には自分の顧客の AL1・AL3・AL4（resolved を含む）が見え、B の AL2 は見えない';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(b): 他のトレーナー B には A のアラートが 0 行
-- -----------------------------------------------------------------------------
\echo '--- case b: 他のトレーナー(B) に A のアラートが 0 行で、自分の AL2 だけ見えること'

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0914-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0914-0000-0000-00000000000b';

DO $$
DECLARE
  v_got uuid[];
BEGIN
  v_got := ARRAY(
    SELECT a.id FROM public.alerts a
     WHERE a.id IN ('a1a1a1a1-0914-0000-0000-000000000001',
                    'a1a1a1a1-0914-0000-0000-000000000002',
                    'a1a1a1a1-0914-0000-0000-000000000003',
                    'a1a1a1a1-0914-0000-0000-000000000004')
     ORDER BY a.id);
  IF v_got IS DISTINCT FROM ARRAY['a1a1a1a1-0914-0000-0000-000000000002']::uuid[] THEN
    RAISE EXCEPTION 'FAIL: トレーナー(B) に見えるアラートが %（期待 AL2 のみ）', v_got;
  END IF;
  RAISE NOTICE 'OK: トレーナー(B) には A のアラートが 0 行（自分の AL2 だけ見える）';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(c): 担当替えの後、前のトレーナー A には 0 行
--   CR の担当を A → B に替える（postgres として実行）。AL3 の trainer_id は A のまま
--   （本実行の reassigned はまだ走っていない）でも、ポリシーの「今の担当」EXISTS で A から消える。
--   B には trainer_id = A の行なので見えない（新しい担当の分は本実行で作り直される）
-- -----------------------------------------------------------------------------
\echo '--- case c: 担当替え（CR を A → B）の後、A にも B にも AL3 が見えないこと'

UPDATE public.clients
   SET trainer_id = 'bbbbbbbb-0914-0000-0000-00000000000b'
 WHERE client_id = 'cccccccc-0914-0000-0000-0000000000c3';

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.id = 'a1a1a1a1-0914-0000-0000-000000000003';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 担当替えの後も前のトレーナー(A) に AL3 が % 行見えている（期待 0 行。今の担当の EXISTS が効いていない）', cnt;
  END IF;

  -- A の他の顧客（CA）のアラートは引き続き見えること（ポリシーが過剰に絞っていない）
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.id IN ('a1a1a1a1-0914-0000-0000-000000000001',
                  'a1a1a1a1-0914-0000-0000-000000000004');
  IF cnt <> 2 THEN
    RAISE EXCEPTION 'FAIL: 担当替えの後、トレーナー(A) に CA のアラートが % 行（期待 2 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 担当替えの後、前のトレーナー(A) には AL3 が 0 行（CA の分は見える）';
END $$;

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0914-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0914-0000-0000-00000000000b';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.id = 'a1a1a1a1-0914-0000-0000-000000000003';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 新しい担当(B) に前の担当の AL3 が % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 新しい担当(B) にも前の担当の AL3 は見えない（trainer_id = 本人 の条件）';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(d): 顧客本人には 0 行（自分についてのアラートも見えない）
-- -----------------------------------------------------------------------------
\echo '--- case d: 顧客(CA) 本人に自分についてのアラートが 0 行であること'

SET LOCAL request.jwt.claims = '{"sub":"cccccccc-0914-0000-0000-0000000000c1","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-0914-0000-0000-0000000000c1';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.client_id = 'cccccccc-0914-0000-0000-0000000000c1';
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客(CA) 本人に自分のアラートが % 行見えている（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 顧客本人には自分についてのアラートも 0 行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e-1): anon（JWT クレーム無し）は SELECT できない
--   直前のケースのクレームが残っていると auth.uid() が値を返してしまうため、
--   両形式を空にしてからロールを切り替える（auth.uid() は nullif(..., '') で NULL に落ちる）
-- -----------------------------------------------------------------------------
\echo '--- case e-1: anon（クレーム無し）の SELECT が permission denied であること'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM count(*) FROM public.alerts;
  RAISE EXCEPTION 'FAIL: anon（クレーム無し）が alerts を SELECT できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for table alerts%' THEN
      RAISE;
    END IF;
    RAISE NOTICE 'OK: anon（クレーム無し）の SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(e-2): anon ロール + トレーナー A の JWT クレームでも見えない
--   1. テーブル権限（REVOKE ALL FROM anon）で permission denied になること
--   2. anon にテーブルの SELECT を一時的に GRANT しても 0 行であること
--      = ポリシーが TO authenticated に限られていることの直接検証。1 だけだと、
--        ポリシーから TO authenticated を外しても（テーブル権限で弾かれて）通ってしまう。
--        将来 anon に SELECT が付いてしまっても、ポリシーの TO 句が二重に守る
-- -----------------------------------------------------------------------------
\echo '--- case e-2: anon ロール + トレーナー(A) クレームでも見えないこと（テーブル権限 + TO authenticated）'

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';
SET LOCAL ROLE anon;

DO $$
BEGIN
  -- 前提確認: auth.uid() がトレーナー A を返している（クレームが効いている）こと
  IF auth.uid() IS DISTINCT FROM 'aaaaaaaa-0914-0000-0000-00000000000a'::uuid THEN
    RAISE EXCEPTION 'FAIL: 前提崩れ — anon ロールで auth.uid() が %（期待 トレーナーA の UUID）',
      coalesce(auth.uid()::text, 'NULL');
  END IF;

  BEGIN
    PERFORM count(*) FROM public.alerts;
    RAISE EXCEPTION 'FAIL: anon ロール + トレーナー(A) クレームで alerts を SELECT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for table alerts%' THEN
        RAISE;
      END IF;
  END;
  RAISE NOTICE 'OK: anon ロール + トレーナー(A) クレームの SELECT は permission denied (42501)';
END $$;

RESET ROLE;

-- 2. テーブル権限を一時的に付けて、ポリシーの TO 句だけで守られていることを確かめる
GRANT SELECT ON public.alerts TO anon;

SET LOCAL ROLE anon;

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.alerts a
   WHERE a.id IN ('a1a1a1a1-0914-0000-0000-000000000001',
                  'a1a1a1a1-0914-0000-0000-000000000004');
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: anon に SELECT を付けると、トレーナー(A) クレームで A のアラートが % 行見えた（期待 0 行。ポリシーが TO authenticated になっていない）', cnt;
  END IF;
  RAISE NOTICE 'OK: anon にテーブルの SELECT を付けても 0 行（ポリシーは TO authenticated のみ）';
END $$;

RESET ROLE;

REVOKE SELECT ON public.alerts FROM anon;

-- -----------------------------------------------------------------------------
-- ケース(f): authenticated（トレーナー A）の INSERT / UPDATE / DELETE は拒否
--   テーブル権限が SELECT だけなので、RLS より先に permission denied（42501）になる
-- -----------------------------------------------------------------------------
\echo '--- case f: トレーナー(A) の INSERT / UPDATE / DELETE が insufficient_privilege であること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
BEGIN
  BEGIN
    INSERT INTO public.alerts (
      trainer_id, client_id, alert_type, severity, first_detected_on, surfaced_on, last_detected_on
    ) VALUES (
      'aaaaaaaa-0914-0000-0000-00000000000a', 'cccccccc-0914-0000-0000-0000000000c1',
      'record_gap', 'low', (now() AT TIME ZONE 'Asia/Tokyo')::date, (now() AT TIME ZONE 'Asia/Tokyo')::date, (now() AT TIME ZONE 'Asia/Tokyo')::date
    );
    RAISE EXCEPTION 'FAIL: トレーナー(A) が alerts に INSERT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    UPDATE public.alerts
       SET status = 'acknowledged', acknowledged_at = now()
     WHERE id = 'a1a1a1a1-0914-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL: トレーナー(A) が alerts を UPDATE できてしまった（対応済みは API Route 経由のみ）';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    DELETE FROM public.alerts
     WHERE id = 'a1a1a1a1-0914-0000-0000-000000000001';
    RAISE EXCEPTION 'FAIL: トレーナー(A) が alerts を DELETE できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  RAISE NOTICE 'OK: authenticated の INSERT / UPDATE / DELETE は insufficient_privilege (42501)';
END $$;

-- -----------------------------------------------------------------------------
-- ケース(g): alert_detection_runs は anon・authenticated とも拒否
-- -----------------------------------------------------------------------------
\echo '--- case g: alert_detection_runs を authenticated / anon が SELECT・INSERT できないこと'

DO $$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.alert_detection_runs;
    RAISE EXCEPTION 'FAIL: authenticated が alert_detection_runs を SELECT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats)
    VALUES ((now() AT TIME ZONE 'Asia/Tokyo')::date, now(), now(), now(), '{}');
    RAISE EXCEPTION 'FAIL: authenticated が alert_detection_runs に INSERT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK: authenticated は alert_detection_runs の SELECT / INSERT が 42501';
END $$;

RESET ROLE;

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  BEGIN
    PERFORM count(*) FROM public.alert_detection_runs;
    RAISE EXCEPTION 'FAIL: anon が alert_detection_runs を SELECT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;

  BEGIN
    INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats)
    VALUES ((now() AT TIME ZONE 'Asia/Tokyo')::date, now(), now(), now(), '{}');
    RAISE EXCEPTION 'FAIL: anon が alert_detection_runs に INSERT できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN NULL;
  END;
  RAISE NOTICE 'OK: anon は alert_detection_runs の SELECT / INSERT が 42501';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-1): service_role 専用の3関数は authenticated / anon から実行できない
--   SQLERRM が関数の EXECUTE 拒否であることまで確認する（別の理由の 42501 を PASS にしない）
-- -----------------------------------------------------------------------------
\echo '--- case h-1: snapshot / evaluate / run を authenticated・anon（クレーム無し・付き）が実行できないこと'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.client_activity_snapshot((now() AT TIME ZONE 'Asia/Tokyo')::date, now(), NULL);
    RAISE EXCEPTION 'FAIL: authenticated が client_activity_snapshot を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function client_activity_snapshot%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts();
    RAISE EXCEPTION 'FAIL: authenticated が evaluate_client_alerts を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function evaluate_client_alerts%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);
    RAISE EXCEPTION 'FAIL: authenticated が run_client_alert_detection を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function run_client_alert_detection%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: authenticated は snapshot / evaluate / run の EXECUTE が permission denied (42501)';
END $$;

RESET ROLE;

-- anon はクレーム無し・クレーム付き（トレーナー A）の両方で確かめる
SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.client_activity_snapshot((now() AT TIME ZONE 'Asia/Tokyo')::date, now(), NULL);
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が client_activity_snapshot を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function client_activity_snapshot%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts();
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が evaluate_client_alerts を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function evaluate_client_alerts%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);
    RAISE EXCEPTION 'FAIL: anon（クレーム無し）が run_client_alert_detection を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function run_client_alert_detection%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: anon（クレーム無し）は snapshot / evaluate / run の EXECUTE が 42501';
END $$;

RESET ROLE;

SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';
SET LOCAL ROLE anon;

DO $$
BEGIN
  BEGIN
    PERFORM 1 FROM public.client_activity_snapshot((now() AT TIME ZONE 'Asia/Tokyo')::date, now(), NULL);
    RAISE EXCEPTION 'FAIL: anon（クレーム付き）が client_activity_snapshot を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function client_activity_snapshot%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM 1 FROM public.evaluate_client_alerts();
    RAISE EXCEPTION 'FAIL: anon（クレーム付き）が evaluate_client_alerts を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function evaluate_client_alerts%' THEN RAISE; END IF;
  END;

  BEGIN
    PERFORM public.run_client_alert_detection((now() AT TIME ZONE 'Asia/Tokyo')::date);
    RAISE EXCEPTION 'FAIL: anon（クレーム付き）が run_client_alert_detection を実行できてしまった';
  EXCEPTION
    WHEN insufficient_privilege THEN
      IF SQLERRM NOT LIKE 'permission denied for function run_client_alert_detection%' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'OK: anon（トレーナー A のクレーム付き）も snapshot / evaluate / run の EXECUTE が 42501';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-2): get_alert_detection_status は anon から実行できない（クレーム無し・付き）
-- -----------------------------------------------------------------------------
\echo '--- case h-2: get_alert_detection_status を anon（クレーム無し・付き）が実行できないこと'

SET LOCAL request.jwt.claims = '';
SET LOCAL request.jwt.claim.sub = '';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM 1 FROM public.get_alert_detection_status();
  RAISE EXCEPTION 'FAIL: anon（クレーム無し）が get_alert_detection_status を実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function get_alert_detection_status%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: anon（クレーム無し）の get_alert_detection_status は permission denied (42501)';
END $$;

RESET ROLE;

-- auth.uid() がトレーナー A を返す状態のまま anon で呼び、role 単位の EXECUTE 剥奪で
-- 拒否されることを直接確認する（anon に EXECUTE が残っていれば、この状態では A の人数が返る）
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';
SET LOCAL ROLE anon;

DO $$
BEGIN
  PERFORM 1 FROM public.get_alert_detection_status();
  RAISE EXCEPTION 'FAIL: anon ロール + トレーナー(A) クレームで get_alert_detection_status を実行できてしまった';
EXCEPTION
  WHEN insufficient_privilege THEN
    IF SQLERRM NOT LIKE 'permission denied for function get_alert_detection_status%' THEN RAISE; END IF;
    RAISE NOTICE 'OK: anon ロール + トレーナー(A) クレームでも get_alert_detection_status は 42501';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(h-3): get_alert_detection_status の中身
--   人数は呼び出したトレーナーの担当顧客だけを、表示した時点（JST の今日・now()）で数える。
--   ケース(c) で CR は B の担当になっている:
--     A: 監視 1（CA）/ no_account 1（CN）/ not_started 1（CS）/ inactive 1（CI）
--     B: 監視 2（CB・CR）/ 対象外 0（A の CN・CS・CI は B の人数に入らない）
--   alert_detection_runs は setup で空にしてあるので、最初は last_* が NULL（未実行）
-- -----------------------------------------------------------------------------
\echo '--- case h-3: get_alert_detection_status がトレーナー本人の担当顧客だけを数えること'

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
DECLARE
  cnt   int;
  v_row record;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_alert_detection_status();
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: トレーナー(A) の get_alert_detection_status が % 行（期待 1 行）', cnt;
  END IF;

  SELECT * INTO v_row FROM public.get_alert_detection_status();
  IF v_row.enabled IS DISTINCT FROM current_setting('alerts_rls_test.expected_enabled')::boolean THEN
    RAISE EXCEPTION 'FAIL: enabled が %（期待 cron.job の active = %）',
      v_row.enabled, current_setting('alerts_rls_test.expected_enabled');
  END IF;
  IF v_row.last_succeeded_at IS NOT NULL OR v_row.last_target_date IS NOT NULL THEN
    RAISE EXCEPTION 'FAIL: 本実行が無いのに last_* が % / %（期待 NULL = 未実行）',
      v_row.last_succeeded_at, v_row.last_target_date;
  END IF;
  IF (v_row.monitored_count, v_row.excluded_no_account, v_row.excluded_not_started, v_row.excluded_inactive)
       IS DISTINCT FROM (1, 1, 1, 1) THEN
    RAISE EXCEPTION 'FAIL: トレーナー(A) の人数が 監視 % / no_account % / not_started % / inactive %（期待 1 / 1 / 1 / 1）',
      v_row.monitored_count, v_row.excluded_no_account, v_row.excluded_not_started, v_row.excluded_inactive;
  END IF;
  RAISE NOTICE 'OK: トレーナー(A) は 1 行、監視 1 / no_account 1 / not_started 1 / inactive 1、未実行（last_* NULL）';
END $$;

SET LOCAL request.jwt.claims = '{"sub":"bbbbbbbb-0914-0000-0000-00000000000b","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'bbbbbbbb-0914-0000-0000-00000000000b';

DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.get_alert_detection_status();
  IF (v_row.monitored_count, v_row.excluded_no_account, v_row.excluded_not_started, v_row.excluded_inactive)
       IS DISTINCT FROM (2, 0, 0, 0) THEN
    RAISE EXCEPTION 'FAIL: トレーナー(B) の人数が 監視 % / no_account % / not_started % / inactive %（期待 2 / 0 / 0 / 0。A の顧客が混ざっている疑い）',
      v_row.monitored_count, v_row.excluded_no_account, v_row.excluded_not_started, v_row.excluded_inactive;
  END IF;
  RAISE NOTICE 'OK: トレーナー(B) の人数に A の顧客は入らない（監視 2 / 対象外 0）';
END $$;

-- 顧客が呼ぶと 0 行
SET LOCAL request.jwt.claims = '{"sub":"cccccccc-0914-0000-0000-0000000000c1","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'cccccccc-0914-0000-0000-0000000000c1';

DO $$
DECLARE cnt int;
BEGIN
  SELECT count(*) INTO cnt FROM public.get_alert_detection_status();
  IF cnt <> 0 THEN
    RAISE EXCEPTION 'FAIL: 顧客(CA) の get_alert_detection_status が % 行（期待 0 行）', cnt;
  END IF;
  RAISE NOTICE 'OK: 顧客が呼ぶと 0 行';
END $$;

RESET ROLE;

-- 本実行の記録を2行入れると、last_* は finished_at が新しい方になる
INSERT INTO public.alert_detection_runs (target_date, as_of, started_at, finished_at, stats) VALUES
  ((now() AT TIME ZONE 'Asia/Tokyo')::date - 1, now() - interval '25 hours', now() - interval '25 hours', now() - interval '25 hours', '{}'),
  ((now() AT TIME ZONE 'Asia/Tokyo')::date,     now() - interval '1 hour',   now() - interval '1 hour',   now() - interval '1 hour',   '{}');

SET LOCAL ROLE authenticated;
SET LOCAL request.jwt.claims = '{"sub":"aaaaaaaa-0914-0000-0000-00000000000a","role":"authenticated"}';
SET LOCAL request.jwt.claim.sub = 'aaaaaaaa-0914-0000-0000-00000000000a';

DO $$
DECLARE v_row record;
BEGIN
  SELECT * INTO v_row FROM public.get_alert_detection_status();
  IF v_row.last_succeeded_at IS DISTINCT FROM now() - interval '1 hour'
     OR v_row.last_target_date IS DISTINCT FROM (now() AT TIME ZONE 'Asia/Tokyo')::date THEN
    RAISE EXCEPTION 'FAIL: last_* が % / %（期待 最新行 = 1時間前 / %）',
      v_row.last_succeeded_at, v_row.last_target_date, (now() AT TIME ZONE 'Asia/Tokyo')::date;
  END IF;
  RAISE NOTICE 'OK: last_succeeded_at / last_target_date は alert_detection_runs の最新行';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(i): service_role は alerts に書き込める（API Route の supabaseAdmin 相当）
-- -----------------------------------------------------------------------------
\echo '--- case i: service_role が alerts を INSERT / UPDATE / DELETE できること'

SET LOCAL ROLE service_role;

DO $$
DECLARE n int;
BEGIN
  INSERT INTO public.alerts (
    id, trainer_id, client_id, alert_type, severity, first_detected_on, surfaced_on, last_detected_on
  ) VALUES (
    'a1a1a1a1-0914-0000-0000-000000000005',
    'bbbbbbbb-0914-0000-0000-00000000000b', 'cccccccc-0914-0000-0000-0000000000c2',
    'record_gap', 'medium', (now() AT TIME ZONE 'Asia/Tokyo')::date, (now() AT TIME ZONE 'Asia/Tokyo')::date, (now() AT TIME ZONE 'Asia/Tokyo')::date
  );

  -- 対応済み（API の条件付き UPDATE と同じ形）
  UPDATE public.alerts
     SET status = 'acknowledged', acknowledged_at = now()
   WHERE id = 'a1a1a1a1-0914-0000-0000-000000000005'
     AND status = 'open';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の条件付き UPDATE が % 行（期待 1 行）', n;
  END IF;

  DELETE FROM public.alerts WHERE id = 'a1a1a1a1-0914-0000-0000-000000000005';
  GET DIAGNOSTICS n = ROW_COUNT;
  IF n <> 1 THEN
    RAISE EXCEPTION 'FAIL: service_role の DELETE が % 行（期待 1 行）', n;
  END IF;
  RAISE NOTICE 'OK: service_role は INSERT / UPDATE / DELETE 可';
END $$;

RESET ROLE;

-- -----------------------------------------------------------------------------
-- ケース(j): メタデータ（postgres として実行）
--   - alerts のポリシーは SELECT 1本（alerts_trainer_select / TO authenticated）
--   - サブクエリの列が外側の alerts.client_id に解決されている（無修飾だと clients の列に
--     解決される。lessons「storage.objects ポリシーのサブクエリ内で…」）
--   - テーブル権限: authenticated は SELECT だけ、anon は無し。alert_detection_runs は両方無し
--   - 関数の EXECUTE: PUBLIC への付与が残っていない
-- -----------------------------------------------------------------------------
\echo '--- case j: ポリシー構成・pg_get_expr の解決先・テーブルと関数の権限'

DO $$
DECLARE
  v_pol   record;
  v_expr  text;
  cnt     int;
  v_fn    regprocedure;
BEGIN
  SELECT count(*) INTO cnt FROM pg_policy p WHERE p.polrelid = 'public.alerts'::regclass;
  IF cnt <> 1 THEN
    RAISE EXCEPTION 'FAIL: alerts のポリシーが % 本（期待 1 本 = alerts_trainer_select）', cnt;
  END IF;

  SELECT p.polname, p.polcmd, p.polpermissive,
         ARRAY(SELECT r::regrole::text FROM unnest(p.polroles) r) AS roles,
         pg_get_expr(p.polqual, p.polrelid) AS qual
    INTO v_pol
    FROM pg_policy p
   WHERE p.polrelid = 'public.alerts'::regclass;

  IF v_pol.polname <> 'alerts_trainer_select' OR v_pol.polcmd <> 'r' OR NOT v_pol.polpermissive THEN
    RAISE EXCEPTION 'FAIL: alerts のポリシーが % / cmd=% / permissive=%（期待 alerts_trainer_select / SELECT）',
      v_pol.polname, v_pol.polcmd, v_pol.polpermissive;
  END IF;
  IF v_pol.roles IS DISTINCT FROM ARRAY['authenticated'] THEN
    RAISE EXCEPTION 'FAIL: alerts_trainer_select の対象ロールが %（期待 {authenticated}）', v_pol.roles;
  END IF;

  v_expr := v_pol.qual;
  IF position('c.client_id = alerts.client_id' IN v_expr) = 0 THEN
    RAISE EXCEPTION 'FAIL: ポリシーのサブクエリが外側の alerts.client_id を参照していない（%）', v_expr;
  END IF;
  IF position('c.trainer_id = ( SELECT auth.uid()' IN v_expr) = 0 THEN
    RAISE EXCEPTION 'FAIL: ポリシーのサブクエリが今の担当（c.trainer_id = auth.uid()）を見ていない（%）', v_expr;
  END IF;
  RAISE NOTICE 'OK: ポリシーの式 = %', v_expr;

  IF NOT has_table_privilege('authenticated', 'public.alerts', 'SELECT')
     OR has_table_privilege('authenticated', 'public.alerts', 'INSERT')
     OR has_table_privilege('authenticated', 'public.alerts', 'UPDATE')
     OR has_table_privilege('authenticated', 'public.alerts', 'DELETE')
     OR has_table_privilege('anon', 'public.alerts', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: alerts のテーブル権限が期待と異なる（authenticated は SELECT のみ、anon は無し）';
  END IF;
  IF has_table_privilege('authenticated', 'public.alert_detection_runs', 'SELECT')
     OR has_table_privilege('anon', 'public.alert_detection_runs', 'SELECT') THEN
    RAISE EXCEPTION 'FAIL: alert_detection_runs に anon / authenticated の SELECT 権限がある';
  END IF;
  IF NOT (SELECT c.relrowsecurity FROM pg_class c WHERE c.oid = 'public.alert_detection_runs'::regclass) THEN
    RAISE EXCEPTION 'FAIL: alert_detection_runs の RLS が無効';
  END IF;

  FOREACH v_fn IN ARRAY ARRAY[
    'public.client_activity_snapshot(date, timestamptz, uuid)'::regprocedure,
    'public.evaluate_client_alerts(date, timestamptz)'::regprocedure,
    'public.run_client_alert_detection(date)'::regprocedure,
    'public.get_alert_detection_status()'::regprocedure
  ] LOOP
    -- proacl が NULL（未変更）なら既定の PUBLIC EXECUTE が生きているため acldefault で補う
    IF EXISTS (
      SELECT 1
        FROM pg_proc p,
             aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) AS a
       WHERE p.oid = v_fn
         AND a.grantee = 0  -- 0 = PUBLIC
    ) THEN
      RAISE EXCEPTION 'FAIL: % の EXECUTE が PUBLIC に付与されたまま', v_fn;
    END IF;
  END LOOP;

  IF has_function_privilege('authenticated', 'public.client_activity_snapshot(date, timestamptz, uuid)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.evaluate_client_alerts(date, timestamptz)', 'EXECUTE')
     OR has_function_privilege('authenticated', 'public.run_client_alert_detection(date)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.client_activity_snapshot(date, timestamptz, uuid)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.evaluate_client_alerts(date, timestamptz)', 'EXECUTE')
     OR NOT has_function_privilege('service_role', 'public.run_client_alert_detection(date)', 'EXECUTE')
     OR NOT has_function_privilege('authenticated', 'public.get_alert_detection_status()', 'EXECUTE')
     OR has_function_privilege('anon', 'public.get_alert_detection_status()', 'EXECUTE') THEN
    RAISE EXCEPTION 'FAIL: 検知関数の EXECUTE 権限が期待と異なる';
  END IF;

  RAISE NOTICE 'OK: ポリシーは SELECT 1本（TO authenticated）/ テーブル・関数の権限は期待どおり';
END $$;

ROLLBACK;

\echo ''
\echo 'ALL CLIENT ALERTS RLS TESTS PASSED'
