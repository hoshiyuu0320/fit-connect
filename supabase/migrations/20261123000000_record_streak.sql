-- =============================================================================
-- Migration: record_streak
-- フェーズ10.3（記録ストリーク表示）: ホームの「今日のまとめ」に出す「記録の連続」の値を返す
-- get_record_streak(p_client_id) を追加する
--
-- 仕様出典: docs/superpowers/specs/2026-11-23-record-streak-design.md §3〜§5
--   オーナー決定（2026-11-23）: 数えるのは自分で付けた記録だけ（ヘルスケアから自動で入った体重・睡眠は
--   数えない）/ 1 日抜けたら 0 から / 今日の分は今日が終わるまで切れない
-- テスト: supabase/tests/record_streak_test.sql
--
-- 返り値（記録が 1 件も無くても必ず 1 行）:
--   as_of_date             DB の今の日本時間の日付 = (now() AT TIME ZONE 'Asia/Tokyo')::date
--   recorded_today         as_of_date が「記録した日」か
--   streak_until_yesterday as_of_date の前日から過去へ、記録した日が途切れずに続く日数（前日が無ければ 0）
--   画面に出す日数（今日記録済みなら +1、まだなら昨日までの日数）は Mobile が決める（§4）
--
-- 「記録した日」（日本時間の日付。次のどれか 1 件でもある日。§3）:
--   体重         source が healthkit でない（manual / message / NULL）  → recorded_at の JST の日付
--                （Android の Health Connect からの取り込みも source = healthkit）
--   食事・運動   すべて                                               → recorded_at の JST の日付
--   睡眠         source = manual か、wakeup_rating が入っている        → recorded_date（起きた日。JST の日付で入っている）
--                （目覚めの評価は必ず本人が付ける。ヘルスケアの行に評価だけを書き足すと source は healthkit のまま）
--   ワークアウト workout_assignments の status = completed・finished_at が入っている・
--                プラン（plan_id → workout_plans.plan_type）が self_guided   → finished_at の JST の日付
--                （完了しても exercise_records は作られない。予定日 assigned_date ではなく完了した日時で数える）
--   数えないもの: ヘルスケアから入った体重、評価の無いヘルスケアの睡眠、トレーナーとのセッション
--   （plan_type = session）の完了、未完了の割り当て（pending / partial / skipped）、as_of_date より後の
--   日付の記録（今日にも連続にも入らない）
--
-- 連続の数え方（§4・§5.1）:
--   記録した日（UNION で重複なし）のうち as_of_date より前のものを新しい順に 1, 2, 3, ... と番号付けし、
--   「n 番目の日 = as_of_date - n」が成り立つ日だけを数える。日付は重複なしで 1 日以上ずつ減っていくので、
--   一度ずれた（抜けた日がある）ら、それより古い日は二度と一致しない = 抜けた日の手前までの日数になる。
--   同じ日の複数の記録は 1 日。今日の記録は streak_until_yesterday に入れない（recorded_today で返す）。
--   比較は「日付 = as_of_date - n」の向きで書く。日付どうしの引き算は ±infinity の日付で例外になるので、
--   本人が書ける recorded_at / recorded_date / finished_at に infinity が入っていても関数を落とさない
--
-- SECURITY INVOKER である理由（§5.2）:
--   - 呼んだ人の RLS がそのまま効く。顧客本人は自分の行だけ、トレーナーは担当する顧客の記録と
--     自分が割り当てたワークアウト・自分のプランだけが見える。他人の client_id を渡しても行が見えないので、
--     (今日, false, 0) になるだけで何も漏れない（関数は引数で絞るだけで、誰が読めるかは RLS が決める）
--   - DEFINER にすると RLS が外れ、client_id を知っていれば誰の連続日数でも読めてしまう
--   - 顧客本人がワークアウトの plan_type を読めるのは workout_plans の clients_read_assigned_plans
--     （自分に割り当てられたプラン）による。読めないと JOIN で落ち、完了がいつまでも数えられない（テストで固定する）
--
-- 時刻を差し込む引数は作らない（§5.1）。テストは now() からの相対でデータを作る。
-- search_path は空文字に固定し、表は public. で修飾する（組み込みの関数・演算子は pg_catalog が暗黙に先に検索される）。
-- SQL 関数だが SET 句があるのでインライン展開されない。
-- 索引: 体重・食事・運動は (client_id, recorded_at DESC)、睡眠は (client_id, recorded_date) の一意、
--   割り当ては (client_id)。どれも client_id で引けるので新しい索引は要らない（§1。1 回の呼び出しで全期間を見る）
--
-- 権限: REVOKE ALL FROM PUBLIC, anon → GRANT EXECUTE TO authenticated。
--   関数を作ると PUBLIC に EXECUTE が付き、Supabase の既定権限（remote_schema の ALTER DEFAULT PRIVILEGES）で
--   anon / authenticated / service_role にも付くので、PUBLIC と anon の両方から明示的に剥がす。
--   記録の表の顧客用 SELECT ポリシーは TO の指定が無く anon にも効くので、anon に EXECUTE が残ると、
--   本人のクレームを持った anon で本人の連続日数が読めてしまう。
--   service_role には既定権限で EXECUTE が残る（RLS を通らないロールで、表をそのまま読めるので新しく読めるものは無い）
--
-- 適用の順序・影響（§8）: 関数を 1 本足すだけで、既存の表・列・関数・ポリシーには触らない。
--   今のアプリは呼ばないので、アプリの更新より先に本番へ適用してよい。新しいアプリは、呼び出しが失敗したとき
--   （適用前・オフラインなど）は行を出さないだけで落ちない。
-- Web: 変更なし。Mobile: lib/features/record_streak/ が rpc('get_record_streak', params: {'p_client_id': ...}) の 1 行目を読む
-- ロールバック: DROP FUNCTION public.get_record_streak(uuid);（新しいアプリは行を出さなくなるだけ）
-- 冪等性: CREATE OR REPLACE と REVOKE / GRANT / COMMENT だけなので、何度実行しても同じ状態になる
-- =============================================================================

CREATE OR REPLACE FUNCTION public.get_record_streak(p_client_id uuid)
RETURNS TABLE (
  as_of_date date,
  recorded_today boolean,
  streak_until_yesterday integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  WITH today AS (
    -- DB の今の日本時間の日付（now() はトランザクションの開始時刻）
    SELECT (now() AT TIME ZONE 'Asia/Tokyo')::date AS d
  ),
  recorded_days AS (
    -- 体重: ヘルスケアからの取り込み（healthkit）は数えない。source が NULL の行は数える
    SELECT (w.recorded_at AT TIME ZONE 'Asia/Tokyo')::date AS day
      FROM public.weight_records w
     WHERE w.client_id = p_client_id
       AND w.source IS DISTINCT FROM 'healthkit'
    UNION
    -- 食事: すべて
    SELECT (m.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
      FROM public.meal_records m
     WHERE m.client_id = p_client_id
    UNION
    -- 運動: すべて
    SELECT (e.recorded_at AT TIME ZONE 'Asia/Tokyo')::date
      FROM public.exercise_records e
     WHERE e.client_id = p_client_id
    UNION
    -- 睡眠: 手入力か、本人が目覚めの評価を付けた日（recorded_date は起きた日の JST の日付）
    SELECT s.recorded_date
      FROM public.sleep_records s
     WHERE s.client_id = p_client_id
       AND (s.source = 'manual' OR s.wakeup_rating IS NOT NULL)
    UNION
    -- ワークアウト: セルフガイドのプランを完了した日（完了した日時で数える。予定日ではない）
    SELECT (a.finished_at AT TIME ZONE 'Asia/Tokyo')::date
      FROM public.workout_assignments a
      JOIN public.workout_plans p ON p.id = a.plan_id
     WHERE a.client_id = p_client_id
       AND a.status = 'completed'
       AND a.finished_at IS NOT NULL
       AND p.plan_type = 'self_guided'
  ),
  past_days AS (
    -- 今日より前の記録した日を、新しい順に 1, 2, 3, ... と番号付けする（今日より後の日付は入らない）
    SELECT r.day, row_number() OVER (ORDER BY r.day DESC) AS n
      FROM recorded_days r
     CROSS JOIN today t
     WHERE r.day < t.d
  )
  SELECT
    t.d AS as_of_date,
    EXISTS (SELECT 1 FROM recorded_days r WHERE r.day = t.d) AS recorded_today,
    -- n 番目の日が「今日の n 日前」に等しい日だけを数える（一度ずれたら、それより古い日は一致しない）
    (SELECT count(*) FROM past_days p WHERE p.day = t.d - p.n::integer)::integer AS streak_until_yesterday
  FROM today t;
$$;

COMMENT ON FUNCTION public.get_record_streak(uuid) IS
  '記録の連続（フェーズ10.3。ホームの「今日のまとめ」）。記録が無くても必ず 1 行 (as_of_date, recorded_today, streak_until_yesterday) を返す。'
  'as_of_date = DB の今の日本時間の日付。recorded_today = その日に記録したか。'
  'streak_until_yesterday = 前日から過去へ、記録した日が途切れずに続く日数（前日が無ければ 0。画面の日数は今日記録済みなら +1）。'
  '記録した日（JST の日付）: 体重（source が healthkit でない。NULL は数える）・食事・運動の recorded_at、'
  '睡眠（source = manual か wakeup_rating あり）の recorded_date、'
  'ワークアウト（status = completed・finished_at あり・プランが self_guided）の finished_at。'
  'as_of_date より後の日付は数えない。同じ日の複数の記録は 1 日。'
  'SECURITY INVOKER: 呼んだ人の RLS で見える行だけを数える（本人は自分の行、トレーナーは担当顧客の記録と自分が割り当てたワークアウト。'
  '見えない client_id では (今日, false, 0)）。'
  '仕様: docs/superpowers/specs/2026-11-23-record-streak-design.md §3〜§5';

-- EXECUTE を authenticated のみに限定
-- （関数の既定の PUBLIC と、Supabase の既定権限で付く anon の EXECUTE を明示的に剥がす）
REVOKE ALL ON FUNCTION public.get_record_streak(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_record_streak(uuid) TO authenticated;
