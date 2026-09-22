-- =============================================================================
-- Migration: secure_parse_message_tags_webhook
-- messages のトリガー関数 public.call_parse_message_tags() の呼び出し先と認証の是正:
-- 本番の Edge Function URL の直書きをやめて Vault の project_url から組み立て、Vault の
-- secret キーを apikey ヘッダーで送る。Vault に 2 つが揃っていない環境（ローカルスタック等）
-- では Edge Function を呼ばない。あわせて関数を SECURITY DEFINER / SET search_path = '' にし、
-- EXECUTE を全ロールから剥がす
--
-- 仕様出典: docs/tasks/lessons.md（2026-09-12「Edge Function の認証を SUPABASE_SERVICE_ROLE_KEY
--           との文字列一致で書くと本番で通らない」/ 2026-09-13「SECURITY DEFINER 関数の権限是正」）
-- テスト:   supabase/tests/parse_message_tags_webhook_test.sql
--
-- 対象:
--   public.call_parse_message_tags()（トリガー関数。トリガー自体は変更しない）
--     - on_message_insert: AFTER INSERT ON public.messages FOR EACH ROW
--     - on_message_update: AFTER UPDATE OF content ON public.messages FOR EACH ROW
--
-- 背景（2026-09-22 発見）:
--   - 直前の定義（20260719000000_repair_message_trigger_drift.sql。2026-09-22 のリモートの
--     読み取り専用 dump と本体が一致）は、Edge Function の URL
--     https://viribpvnpgtgtmeulcmx.supabase.co/functions/v1/parse-message-tags を直書きし、
--     認証ヘッダー無しで net.http_post していた
--   - そのため、この migration 群を適用したすべての DB（開発者のローカルスタックを含む）で、
--     コミットされた messages の INSERT / content の UPDATE がすべて本番の Edge Function へ
--     送られていた。2026-09-22 に、ローカルスタックの Seed.sql が投入したメッセージが本番へ
--     POST され、本番の notification_logs に 18 行（kind = 'message'、status = 'skipped'、
--     user_id は Seed.sql のプレースホルダー UUID 11111111-… / 22222222-…）が書き込まれて
--     いるのを確認した（この 18 行の後始末は本 migration の対象外）
--   - parse-message-tags は verify_jwt = false で、関数側にも呼び出し元の認証が無かった。
--     旧 Edge Function は payload の record（sender_id / content 等）をそのまま信用して
--     service role で記録の作成・削除と通知を行っていたため、関数 URL を知っていれば誰でも
--     偽の payload を送れた（関数側の是正 = apikey の照合と messages からの取り直しは、
--     supabase/functions/parse-message-tags/index.ts と _shared/service_auth.ts で別途行う）
--   - 関数は SECURITY INVOKER で、EXECUTE が PUBLIC（PostgreSQL 既定）と anon / authenticated /
--     service_role（dump の GRANT ALL = role postgres の default privileges）に付いていた。
--     トリガー関数なので直接呼んでもエラーになるだけだが、付けておく理由も無い
--
-- 方針:
--   - 呼び出し先は Vault の project_url から組み立て、Vault の secret_key（新しい secret キー
--     sb_secret_...）を apikey ヘッダーで送る（cron と同じ方式: 20260912000000_cron_use_secret_key.sql）。
--     Authorization ヘッダーは送らない（secret キーを Bearer で送ると、ゲートウェイが JWT として
--     解析しようとして弾く）
--   - Vault に project_url / secret_key のどちらかが無い（NULL または空文字）環境では
--     net.http_post を呼ばず、WARNING を出して RETURN NEW する。Vault が空のローカルスタックは
--     これで本番を呼ばなくなる。フォールバック URL は持たない（直書きの URL を残すと、
--     また別の環境から本番へ送る経路になる）
--   - メッセージの INSERT / UPDATE 自体は止めない（スキップ時は WARNING だけで、アプリの
--     送信・編集は成功する）
--   - payload は現行と同一のキー構成のまま送る。デプロイの切り替え中に動いている旧 Edge Function
--     との互換のため（新しい Edge Function は type と record.id だけを使い、残りは messages から
--     取り直す）
--   - Vault を読むため SECURITY DEFINER（owner postgres）にし、search_path を空文字に固定する。
--     EXECUTE は PUBLIC / anon / authenticated / service_role のすべてから剥がし、GRANT はしない
--     （理由はセクション 1 のコメント）
--   - pg_net のタイムアウトは既定のまま（従来どおり timeout_milliseconds を指定しない）
--
-- リモートへの影響:
--   - 前提: リモートの Vault に project_url（https://viribpvnpgtgtmeulcmx.supabase.co）と
--     secret_key が登録済みであること。2026-09-12 に登録済みで、cron の auto-skip-workouts /
--     cleanup-ai-images が同じ 2 つを apikey ヘッダーで送って本番で動いている
--     （docs/tasks/2026-07-10-cron-vault-setup.md）。揃っていないまま push すると、本番のメッセージの
--     タグ解析・記録作成・通知がすべて止まる。止まってもエラーにはならず WARNING が出るだけなので
--     気付きにくい。push 前に下の確認 SQL で必ず確かめること
--   - 呼び出し先 URL は変わらない（project_url + '/functions/v1/parse-message-tags'）。
--     変わるのは apikey ヘッダーが付くことと、関数の属性（SECURITY DEFINER / search_path）と ACL だけ
--   - トリガー（on_message_insert / on_message_update）には触れない
--   - アプリ（Web / Mobile）のリリースは不要。どちらも messages への INSERT / UPDATE を
--     authenticated として行うだけで、この関数を直接呼ばない（トリガーの発火では関数の EXECUTE
--     権限は検査されない）
--
-- デプロイ順序（重要）:
--   1. 本 migration を先に push する（`supabase db push`）
--      - push 後、トリガーは apikey ヘッダー付きで送る。旧 Edge Function（認証なし）は
--        apikey ヘッダーを無視するので、今までどおり動く
--   2. その後で新しい parse-message-tags（_shared/service_auth.ts で apikey を照合する版）を deploy する
--      - 逆順にすると、deploy から push までの間はトリガーの要求（apikey 無し）がすべて 401 になり、
--        その間のメッセージのタグ解析・記録作成・通知が失われる（pg_net は再送しない）
--   push 前の確認（Dashboard の SQL Editor。secret キーの値は表示しない）:
--     SELECT name,
--            CASE WHEN name = 'project_url' THEN decrypted_secret END AS project_url,
--            decrypted_secret LIKE 'sb_secret_%' AS is_sb_secret
--     FROM vault.decrypted_secrets
--     WHERE name IN ('project_url', 'secret_key');
--     → 2 行あり、project_url が https://viribpvnpgtgtmeulcmx.supabase.co（末尾の / は有無どちらでも可）、
--       secret_key の is_sb_secret が true であること
--   push・deploy 後の確認: 本番でタグ付きメッセージを 1 件送り、記録が作られること。あわせて
--     SELECT id, status_code, created FROM net._http_response ORDER BY created DESC LIMIT 5;
--     で直近の応答が 200 であること（401 なら Vault の secret_key が関数側のキーと一致していない）
--
-- ローカル環境への影響:
--   - Vault に project_url / secret_key が無いローカルスタックでは、メッセージを保存しても
--     Edge Function は呼ばれない（WARNING 'PARSE_MESSAGE_TAGS_SKIPPED: ...' が出る）。
--     Seed.sql のメッセージが本番へ送られることも無くなる
--   - ローカルで parse-message-tags を動かしたいときは、ローカルの Vault に次の 2 つを登録する
--     （登録したローカルスタックは、そのスタック自身のローカルの関数だけを呼ぶ。本番へは送られない）:
--       - project_url: http://kong:8000（ローカルスタックの Docker ネットワーク内での API ゲートウェイの
--         エイリアス。project_id / ポートにかかわらず、どのローカルスタックでも同じ。2026-09-22 に
--         隔離したローカルスタックで確認済み）
--       - secret_key: `supabase status` の Secret key（sb_secret_...）。ローカルの CLI（v2.75）は
--         SUPABASE_SECRET_KEYS を edge runtime に渡さないが、ローカルの kong が
--         `apikey: <ローカルの sb_secret>` を `Authorization: Bearer <ローカルの service_role JWT>` に
--         書き換えるため、_shared/service_auth.ts の互換の Bearer 経路で通る。その経路を削除する
--         までは、ローカルでもこれで動く
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 0. 事前ガード: 2026-09-22 の dump 以降のリモートのドリフト検知
--    本 migration は call_parse_message_tags() を CREATE OR REPLACE で作り直す。起点にしている
--    本体（20260719000000 の定義）がリモートと同一だと確かめたのは 2026-09-22 の dump 時点で
--    しかない。push までにリモートで（migration を経ずに）本体が変更されていると、本 migration は
--    その変更を黙って元に戻してしまう。そうならないよう、作り直す前に本体（pg_proc.prosrc）の
--    md5 を dump 時点の値と比べ、一致しなければ例外（REMOTE_DRIFT_SINCE_CAPTURE）で migration
--    全体を失敗させる。関数が存在しない場合も同じ例外で止める。
--
--    期待値 5c0b99091b07e9017b1666d0b5ab84e2: 20260719000000 の本体の md5。2026-09-22 のリモートの
--    dump の本体、および repo の migration だけで作った DB（fresh DB）の本体と一致することを確認済み
--    - 比較するのは本体（prosrc）だけ。SECURITY DEFINER / search_path / ACL は本 migration が
--      明示的に上書きする対象なので比べない
--    - 是正済みの DB（本 migration を適用した後）に本ファイルを流し直すと、本体が変わっている
--      ため必ずこのガードで止まる。migration は 1 回しか適用されないので問題ない
-- -----------------------------------------------------------------------------
DO $$
DECLARE
  v_signature    constant text := 'public.call_parse_message_tags()';
  v_expected_md5 constant text := '5c0b99091b07e9017b1666d0b5ab84e2';
  v_oid oid;
  v_md5 text;
BEGIN
  v_oid := to_regprocedure(v_signature);

  IF v_oid IS NULL THEN
    RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'function %s does not exist (expected md5(prosrc)=%s as of the 2026-09-22 remote dump)',
              v_signature, v_expected_md5
            ),
            HINT    = '2026-09-22 の dump 時点で存在したトリガー関数がありません。リモートの現状（関数とトリガー on_message_insert / on_message_update）を確認し、それを追認する migration を先に置いてから再適用してください。';
  END IF;

  SELECT md5(p.prosrc)
  INTO v_md5
  FROM pg_catalog.pg_proc p
  WHERE p.oid = v_oid;

  IF v_md5 IS DISTINCT FROM v_expected_md5 THEN
    RAISE EXCEPTION 'REMOTE_DRIFT_SINCE_CAPTURE'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'function %s has md5(prosrc)=%s, expected %s (2026-09-22 remote dump)',
              v_signature, v_md5, v_expected_md5
            ),
            HINT    = '関数本体が 2026-09-22 の dump 以降に変わっています。このまま適用すると CREATE OR REPLACE がその変更を元に戻すため中止しました。現定義を追認する migration を先に置き、本 migration の本体と期待 md5 をそれに合わせてから再適用してください。';
  END IF;
END $$;

-- -----------------------------------------------------------------------------
-- 1. call_parse_message_tags()
--    messages の INSERT / content の UPDATE ごとに、Edge Function parse-message-tags へ
--    pg_net（net.http_post）で payload を送る。payload の組み立ては 20260719000000 と同一で、
--    変わるのは送信先 URL と認証ヘッダーの出どころ（Vault）と、Vault が揃っていないときに
--    送らないことだけ。
--
--    呼び出し元:
--      - トリガー on_message_insert / on_message_update のみ（アプリからは Web / Mobile の
--        messages への INSERT / UPDATE で発火する。直接呼ぶ経路は無い）
--      → EXECUTE は誰にも付けない（セクション 2）
--
--    SECURITY DEFINER にする理由:
--      トリガー関数は、INSERT / UPDATE を実行したロール（アプリからは authenticated）の権限で
--      動く。authenticated は vault スキーマの USAGE も vault.decrypted_secrets の SELECT も
--      持たず、持たせてもいけない（secret キーは RLS を完全にバイパスする最高権限キー）。
--      そのため Vault を読む部分は、定義者 postgres（vault.decrypted_secrets を SELECT できる）の
--      権限で動かす必要がある。
--
--    DEFINER をトリガー関数そのものに付け、別のヘルパー関数に分けない理由:
--      - 「secret を返す DEFINER 関数」や「payload を受け取って送信する DEFINER 関数」を別に作り、
--        INVOKER のトリガー関数から呼ぶ形にすると、そのヘルパーの EXECUTE を authenticated に
--        付けざるを得ない（INVOKER のトリガー関数は authenticated として呼ぶため）。public
--        スキーマの関数は PostgREST の /rest/v1/rpc/<関数名> で公開されるので、前者は secret
--        キーの漏洩、後者は「本物の secret キーが付いた任意の payload」の送信を、ログイン
--        ユーザーなら誰でもできる経路になる（別スキーマに置いても、EXECUTE を持つ限り同じ穴が
--        残る）
--      - トリガー関数そのものを DEFINER にすれば、この穴は生じない:
--          - トリガー関数はトリガーとしてしか実行できない。直接呼ぶと PL/pgSQL が
--            'trigger functions can only be called as triggers' で拒否するので、呼び出し側が
--            NEW / TG_OP を偽造して送らせる手段が無い
--          - トリガーの発火時には、トリガー関数の EXECUTE 権限は検査されない（検査されるのは
--            CREATE TRIGGER の時だけ）。したがって EXECUTE を全ロールから剥がしても、
--            authenticated の INSERT / UPDATE でトリガーは従来どおり発火する
--        結果として、送られる payload は RLS（INSERT の WITH CHECK sender_id = auth.uid() 等）を
--        通って実際に書き込まれた messages の行から組み立てたものだけになる。また pg_net の要求は
--        net.http_request_queue への INSERT で、コミットされるまでワーカーからは見えないため、
--        ロールバックされた INSERT / UPDATE の分は送られない
--
--    search_path = '' について:
--      - vault.decrypted_secrets / net.http_post はスキーマ修飾して書く。組み込みの関数
--        （jsonb_build_object / coalesce / rtrim / format）は pg_catalog が暗黙に先頭検索される
--      - 関数の SET search_path は、実行中に発火するトリガーにも引き継がれる（lessons.md
--        2026-09-13）。本関数の中で起きる DML は net.http_post による net.http_request_queue への
--        INSERT だけで、net.http_post 自身が SET search_path = net を持つ SECURITY DEFINER 関数で
--        あり、net.http_request_queue にはトリガーが無い（ローカルの pg_net 0.14.0 で pg_trigger を
--        確認）。vault.decrypted_secrets はビューで、参照先はビュー作成時に解決済みのため
--        search_path の影響を受けない
--
--    Vault が揃っていないとき:
--      - project_url / secret_key のどちらかが NULL（未登録）または空文字なら、net.http_post を
--        呼ばずに RAISE WARNING して RETURN NEW する。WARNING の先頭 'PARSE_MESSAGE_TAGS_SKIPPED:' は
--        ログ検索用に固定。メッセージには message_id と操作種別を、DETAIL には 2 つそれぞれが
--        未登録 / 空文字 / 登録済みのどれかだけを入れ、Vault の値は一切出さない
--      - このチェックが無いと、secret_key 無しの要求を送るだけでなく、project_url が無い環境では
--        URL が NULL になって net.http_request_queue の NOT NULL 制約に違反し、メッセージの
--        INSERT / UPDATE そのものが失敗する
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path = ''
AS $function$
DECLARE
  payload jsonb;
  v_project_url text;
  v_secret_key text;
BEGIN
  -- 基本ペイロード（INSERT/UPDATE共通）
  payload := jsonb_build_object(
    'type', TG_OP,
    'table', 'messages',
    'record', jsonb_build_object(
      'id', NEW.id,
      'content', NEW.content,
      'sender_id', NEW.sender_id,
      'receiver_id', NEW.receiver_id,
      'sender_type', NEW.sender_type,
      'receiver_type', NEW.receiver_type,
      'created_at', NEW.created_at,
      'image_urls', NEW.image_urls
    )
  );

  -- UPDATE時は変更前の情報も含める
  IF TG_OP = 'UPDATE' THEN
    payload := payload || jsonb_build_object(
      'old_record', jsonb_build_object(
        'content', OLD.content,
        'tags', OLD.tags
      )
    );
  END IF;

  -- 送信先と認証キーは Vault から読む（URL を直書きしない。定義者 postgres の権限で読む）
  SELECT s.decrypted_secret
  INTO v_project_url
  FROM vault.decrypted_secrets s
  WHERE s.name = 'project_url';

  SELECT s.decrypted_secret
  INTO v_secret_key
  FROM vault.decrypted_secrets s
  WHERE s.name = 'secret_key';

  -- どちらかが無い環境（Vault 未登録のローカルスタック等）では Edge Function を呼ばない。
  -- フォールバック URL は持たない。メッセージの保存自体は止めない（WARNING のみ。値は出さない）
  IF coalesce(v_project_url, '') = '' OR coalesce(v_secret_key, '') = '' THEN
    RAISE WARNING 'PARSE_MESSAGE_TAGS_SKIPPED: Vault に project_url / secret_key が揃っていないため parse-message-tags を呼び出さない（message_id=%, op=%）',
      NEW.id, TG_OP
      USING DETAIL = format(
              'project_url: %s / secret_key: %s',
              CASE WHEN v_project_url IS NULL THEN '未登録' WHEN v_project_url = '' THEN '空文字' ELSE '登録済み' END,
              CASE WHEN v_secret_key IS NULL THEN '未登録' WHEN v_secret_key = '' THEN '空文字' ELSE '登録済み' END
            ),
            HINT   = 'Vault 未登録のローカル環境では想定どおり（本番の Edge Function を呼ばないため）。parse-message-tags を動かすには Vault に project_url と secret_key を登録する（docs/tasks/2026-07-10-cron-vault-setup.md）。本番で出た場合はタグ解析・記録作成・通知が止まっている。';
    RETURN NEW;
  END IF;

  -- Edge Functionを呼び出し
  -- secret キー（sb_secret_...）は apikey ヘッダーで送る。Authorization: Bearer では送らない
  -- （JWT ではないため、ゲートウェイが JWT として解析しようとして弾く）
  PERFORM net.http_post(
    url := rtrim(v_project_url, '/') || '/functions/v1/parse-message-tags',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'apikey', v_secret_key
    ),
    body := payload
  );

  RETURN NEW;
END;
$function$;

-- -----------------------------------------------------------------------------
-- 2. EXECUTE の剥奪（GRANT はしない。EXECUTE を持つのはオーナー postgres だけになる）
--    - リモートでは PUBLIC（PostgreSQL が関数作成時に付ける既定）と anon / authenticated /
--      service_role（role postgres の default privileges。dump の GRANT ALL）に付いている。
--      anon は PUBLIC のメンバーなので、PUBLIC と個別ロールの両方から剥がす
--    - CREATE OR REPLACE は既存の ACL を保持するため、ここで明示的に剥がさないと何も変わらない
--    - トリガーの発火は EXECUTE を検査しないので、剥がしてもアプリの INSERT / UPDATE は影響を
--      受けない。トリガーを作り直す（CREATE TRIGGER は EXECUTE を要求する）のはオーナー postgres
--      なので、それも妨げない
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.call_parse_message_tags() FROM PUBLIC, anon, authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3. コメント
-- -----------------------------------------------------------------------------
COMMENT ON FUNCTION public.call_parse_message_tags() IS
  'messages のトリガー on_message_insert（AFTER INSERT）/ on_message_update（AFTER UPDATE OF content）から呼ばれ、'
  'Edge Function parse-message-tags へ pg_net で payload（type / table / record / UPDATE 時は old_record）を送る。'
  '送信先は Vault の project_url + /functions/v1/parse-message-tags、認証は Vault の secret_key を apikey ヘッダーで送る（Authorization は送らない）。'
  'Vault に project_url / secret_key のどちらかが無ければ送らず WARNING（PARSE_MESSAGE_TAGS_SKIPPED）を出す（本番以外の環境が本番を呼ばないための前提）。'
  'Vault を読むため SECURITY DEFINER / search_path 空文字。EXECUTE は誰にも付けない（トリガーの発火は EXECUTE を検査しない）。'
  '仕様: supabase/migrations/20260922000100_secure_parse_message_tags_webhook.sql';
