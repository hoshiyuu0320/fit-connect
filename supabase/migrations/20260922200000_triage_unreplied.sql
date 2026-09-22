-- =============================================================================
-- Migration: triage_unreplied
-- フェーズ9.2（デイリートリアージ MVP）: ダッシュボード「今日の対応」に合流させる
-- 「未返信の顧客」を返す get_unreplied_clients_for_trainer() を追加する
--
-- 仕様出典: docs/tasks/2026-09-13-trainer-intervention-plan.md
--   「設計判断」14・15 /「PR 分割 > PR2」/「契約 > RPC get_unreplied_clients_for_trainer()（PR2）」/
--   「タスク分割 > PR2 > レーンA」/「オーナー決定」4
--
-- 背景:
--   - カタログ 2-A の get_daily_triage(p_trainer_id) は SECURITY DEFINER で、他人のトレーナー ID を
--     渡すと読める穴になる。計画では引数なし・SECURITY INVOKER の本関数に読み替え、未返信だけを
--     返す。優先度スコア（triageScore）とアラートとの合流は Web の純関数で行う（重みを migration
--     なしで調整でき、vitest で固定できる。顧客は最大30名なので Web でまとめて足りる）
--   - 既読（read_at）は画面を開いただけで付くので、既読 ≠ 返信。サイドバーの「メッセージ」の数
--     （未読）とは別に、「最後のメッセージが顧客からで、まだ返信していない」顧客を返す
--   - 顧客→トレーナーのメッセージの約半数はタグ付きの記録投稿（#体重 など。ワークアウト達成も
--     #運動:完了 付き）。記録は返信を求めていないので除く。判定は tags だけで行う（旧形式の
--     タグ無し記録13件は 2026-02〜03 のもので7日の窓に入らない。SQL と TS に同じ定義を二重に持たない）
--
-- 方針:
--   1. 未返信の定義（計画書「契約」。関数の COMMENT にも同じものを書く）
--      - 今の担当顧客（clients.trainer_id = auth.uid() かつ client_id <> auth.uid()）から
--        自分宛て（receiver_id = auth.uid()、sender_type = 'client'、sender_id = その顧客）に届いた
--        タグ無し（coalesce(cardinality(tags), 0) = 0。tags が NULL もタグ無し）のメッセージ
--      - そのうち、トレーナーがその顧客に最後に送ったメッセージ（タグの有無は問わない）より後のもの。
--        返信はトレーナーとして送ったもの（sender_type = 'trainer'）だけを数える。兼務で互いに担当し合う
--        2人では、自分が相手の顧客として送った記録投稿（sender_type = 'client'）を返信とみなさないため
--        （lessons「兼務アカウントの痕跡は sender_type / receiver_type で分けないと混ざる」。
--        Web の送信 API は常に sender_type = 'trainer' で送るので、通常の返信の数え方は変わらない）
--      - 最新の未返信が7日以内の顧客だけ（unreplied_since / unreplied_count は7日より前の未返信も含む）
--      - 自分宛て（sender = receiver）は client_id <> auth.uid() で除く。削除済みの顧客
--        （clients に行が無い）とのメッセージは clients との JOIN で落ちる
--   2. SECURITY INVOKER + auth.uid() 固定（計画書「カタログからの読み替え」）
--      - 呼び出したトレーナー本人の権限で読むので、messages（sender_id / receiver_id = auth.uid()）と
--        clients（trainer_id = auth.uid()）の RLS がそのまま効く。関数の条件と RLS の二重で守る
--        （担当替えの後の前トレーナー・他のトレーナーの顧客は、どちらか片方が外れても出ない）
--      - 引数でトレーナー ID を受け取らない。戻り列は RETURNS TABLE の許可リストで固定する
--        （client_id, client_name, profile_image_url, unreplied_since, latest_unreplied_at, unreplied_count）
--      - DEFINER にしない理由: 読むのは本人が RLS で読める行だけで、定義者権限は要らない。
--        DEFINER にすると RLS が外れ、関数の条件だけが守りになる
--   3. 利用者が書ける値への備え（lessons「行単位 RLS の WITH CHECK は他の列を守らない」）
--      - messages の INSERT ポリシーは sender_id しか見ないので、顧客は自分のメッセージの
--        created_at を未来・±infinity にできる。そのままでは、トレーナーが返信しても
--        （返信の created_at は now() なので後にならない）未返信が消えず、非有限の日時は Web の
--        時間計算を NaN にして一覧の並びを崩す。顧客のメッセージは isfinite(created_at) かつ
--        created_at <= now() のものだけを数える（未来の日時のものは、その時刻が来てから数える）
--      - 受信者の UPDATE ポリシー（"Receivers can mark messages as read"）は receiver_id しか見ないので、
--        顧客はトレーナーから届いたメッセージの created_at なども書き換えられる。影響はその顧客自身の
--        行が出る・出ないだけで（顧客が自分でメッセージを送る・送らないのと同じ）、他の顧客の行や
--        他のトレーナーには及ばない。ポリシー自体の修正は別タスク
--      - INSERT のポリシーは sender_id = 本人しか通さず、受信者の UPDATE で sender_id を書き換えられるのは
--        自分宛てのメッセージだけ（トレーナー宛てのメッセージを書き換えられるのはトレーナー本人）。
--        担当関係の無い第三者が、担当顧客の sender_id を装って未返信を作ることはできない
--      - ただし「今の担当顧客」の根拠の clients.trainer_id は、顧客本人が書ける
--        （clients_insert_own / clients_update_own は client_id = auth.uid() しか見ない。trainers は誰でも読める）。
--        任意の利用者が自分を任意のトレーナーの顧客にして、未返信の一覧とバッジに出ることはできる
--        （上限は enforce_client_limit のプランの顧客数だけ）。顧客一覧・メッセージ画面も同じ前提で
--        clients.trainer_id を信頼しており、この migration の前からある穴。trainer_id の書き込みを
--        制限するのは RLS の別タスク（messages のポリシーの修正と同じタスク）
--   4. 索引: 顧客ごとに、最後の返信は (receiver_id, created_at DESC)、未返信は
--      (sender_id, created_at DESC) の範囲走査で引く。新しい索引は要らない
--      （トレーナー単位で最大30顧客。EXPLAIN で確認。書き方の注意は関数の上の注記）
--   5. 権限: REVOKE ALL FROM PUBLIC, anon → GRANT EXECUTE TO authenticated。messages / clients の
--      ポリシーの多くは TO public（anon を含む）なので、anon に EXECUTE が残ると、クレーム付きの
--      anon で本人の行が読めてしまう。service_role には既定権限で EXECUTE が残るが、sub の無い
--      呼び出しでは auth.uid() が NULL となり 0 行
--
-- 消し込み（triage_actions / 返信不要にする）は作らない（オーナー決定4。拡張1）。
--   返信不要のメッセージは、最新の未返信から最長7日並ぶ
-- 通知: sendNotification は呼ばず、通知種別（kind）も足さない（VAPID 設定後の後続タスク）
-- Mobile: 変更なし（関数を足すだけで、テーブル・列は変えない）
-- ロールバック: Web を revert して本番に出してから
--   DROP FUNCTION public.get_unreplied_clients_for_trainer();
-- 冪等性: CREATE OR REPLACE と REVOKE / GRANT / COMMENT だけなので、何度実行しても同じ状態になる
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. get_unreplied_clients_for_trainer()
--    呼び出したトレーナー（auth.uid()）の今の担当顧客のうち、未返信の顧客を1行ずつ返す。
--      unreplied_since     : 未返信のうち最も古いメッセージの created_at（7日より前のこともある）
--      latest_unreplied_at : 未返信のうち最も新しいメッセージの created_at（7日以内）
--      unreplied_count     : 未返信のメッセージの件数
--    並び順は unreplied_since の古い順（同じなら client_id）。表示の並び（スコア順）は Web で決める。
--    トレーナーでない利用者（顧客）が呼んでも担当顧客がいないので 0 行。
--
--    SQL 関数だが SET 句があるのでインライン展開されない（呼び出し側の order / limit は結果に掛かる）。
--    search_path は空文字に固定し、テーブル・関数は完全修飾する（組み込みの型・演算子・関数は
--    pg_catalog が暗黙に先頭検索されるため修飾不要）
--
--    索引を効かせるための書き方（2026-09-22 ローカルの EXPLAIN。合成データ 約33万件・トレーナー1名あたり
--    受信 約2.2万件 / 送信 約1.1万件 / 顧客30名、authenticated + トレーナーの JWT クレームで実行）:
--    - auth.uid() を (SELECT auth.uid()) で包まない。包むと InitPlan のパラメータになり、計画時に値が
--      分からないので、送受信の多いトレーナー ID の行数を平均で見積もる。その結果、顧客ごとに
--      トレーナーの受信箱・送信済み全体を走査する計画になった（関数の呼び出しで 155ms）。包まなければ
--      計画時に値を推定に使え、最後の返信は (receiver_id, created_at DESC) の逆順走査 + LIMIT 1、未返信は
--      (sender_id, created_at DESC) の範囲走査（sender_id = 顧客 AND created_at > 最後の返信）になる（1.3ms。結果は同一）。
--      auth.uid() は索引条件として走査ごとに1回評価され、残りは数行の Filter で評価されるだけ
--    - 返信が無いときの -infinity は lr の中で coalesce しておき、未返信側は列どうしの比較にする。
--      比較側に coalesce を書くと、RLS の掛かったテーブルでは索引条件にならず Filter に回った
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_unreplied_clients_for_trainer()
RETURNS TABLE (
  client_id uuid,
  client_name text,
  profile_image_url text,
  unreplied_since timestamptz,
  latest_unreplied_at timestamptz,
  unreplied_count integer
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
  SELECT
    c.client_id,
    c.name,
    c.profile_image_url,
    u.unreplied_since,
    u.latest_unreplied_at,
    u.unreplied_count
  FROM public.clients c
  -- トレーナーがその顧客にトレーナーとして最後に送ったメッセージ（タグの有無は問わない）。
  -- 返信が一度も無ければ -infinity（= その顧客からのメッセージはすべて返信より後）
  CROSS JOIN LATERAL (
    SELECT coalesce(max(r.created_at), '-infinity'::timestamptz) AS replied_at
      FROM public.messages r
     WHERE r.sender_id = auth.uid()
       AND r.receiver_id = c.client_id
       -- 兼務で相手の顧客として送った投稿は返信ではない（方針1）
       AND r.sender_type = 'trainer'
  ) lr
  -- それより後に顧客から自分宛てに届いたタグ無しのメッセージ
  CROSS JOIN LATERAL (
    SELECT
      min(m.created_at)    AS unreplied_since,
      max(m.created_at)    AS latest_unreplied_at,
      count(*)::integer    AS unreplied_count
      FROM public.messages m
     WHERE m.sender_id = c.client_id
       AND m.receiver_id = auth.uid()
       AND m.sender_type = 'client'
       AND coalesce(cardinality(m.tags), 0) = 0
       -- 顧客が書ける created_at の未来・非有限の値は数えない（方針3）
       AND isfinite(m.created_at)
       AND m.created_at <= now()
       -- 列どうしの比較にしておく（索引条件になる。関数上の注記を参照）
       AND m.created_at > lr.replied_at
  ) u
  WHERE c.trainer_id = auth.uid()
    AND c.client_id <> auth.uid()
    -- 集約は未返信が無くても1行（count = 0）を返すので、未返信のある顧客に絞る
    AND u.unreplied_count > 0
    -- 最新の未返信が7日以内の顧客だけ
    AND u.latest_unreplied_at >= now() - interval '7 days'
  ORDER BY u.unreplied_since, c.client_id;
$$;

COMMENT ON FUNCTION public.get_unreplied_clients_for_trainer() IS
  '呼び出したトレーナー（auth.uid()）の今の担当顧客のうち、未返信の顧客を返す（フェーズ9.2 デイリートリアージ）。'
  '未返信 = 担当顧客（clients.trainer_id = auth.uid()、client_id <> auth.uid()）から自分宛て'
  '（receiver_id = auth.uid()、sender_type = client）に届いたタグ無し（tags が空または NULL）のメッセージのうち、'
  'トレーナーがその顧客にトレーナーとして（sender_type = trainer）最後に送ったメッセージ（タグの有無は問わない）より後のもの。'
  '最新の未返信が7日以内の顧客だけを返す。既読（read_at）は返信とみなさない。'
  '顧客が書ける created_at の未来・非有限の値は数えない。'
  '今の担当顧客の判定は clients.trainer_id を信頼する（顧客本人が書ける列。書き込みの制限は RLS の別タスク）。'
  '戻り列は許可リスト（client_id, client_name, profile_image_url, unreplied_since, latest_unreplied_at, unreplied_count）。'
  'SECURITY INVOKER である理由: 本人が RLS で読める messages / clients の行だけを読めば足り、'
  '関数の条件（auth.uid() 固定・引数なし）と RLS の二重で他人の顧客を守るため（DEFINER にすると RLS が外れる）。'
  'スコアと並び順は Web の純関数（triageScore）で決める。消し込み（返信不要にする）は無い。'
  '仕様: docs/tasks/2026-09-13-trainer-intervention-plan.md「契約」';

-- EXECUTE を authenticated のみに限定
-- （関数のデフォルト権限 + remote_schema の ALTER DEFAULT PRIVILEGES により
--   PUBLIC / anon へも EXECUTE が付与されるため明示的に剥がす）
REVOKE ALL ON FUNCTION public.get_unreplied_clients_for_trainer() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_unreplied_clients_for_trainer() FROM anon;
GRANT EXECUTE ON FUNCTION public.get_unreplied_clients_for_trainer() TO authenticated;
