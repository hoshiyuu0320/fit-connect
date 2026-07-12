-- Migration: enforce_client_limit
-- 目的: プランごとの顧客数上限を DB トリガーで強制する。
--
-- 仕様出典: docs/tasks/2026-07-11-pro-pricing-proposal.md §8（2026-07-12 オーナー確定）
--   - 顧客数上限: Free=3人 / Pro=10人 / Business=30人
--   - 実効プラン = subscription_plan != 'free' ? subscription_plan
--                : (trial_ends_at > now() ? 'pro'(14日トライアル中) : 'free')
--     （20260712000000_add_billing_foundation.sql §2 のアプリ側計算式と同一）
--   - 超過時の挙動: 新規追加のブロックのみ。既存顧客が上限を超過していても削除・制限はしない
--     （本トリガーは INSERT / trainer_id 変更 UPDATE の新規行にのみ作用し、既存行には触らない）
--
-- なぜ DB トリガーか:
--   clients は Mobile 端末が RLS 経由で直接 INSERT / UPDATE する
--   （registration_provider の upsert、onConflict: client_id。
--     clients_update_own により本人が trainer_id を書き換え可能 = トレーナー乗り換え）。
--   Web UI / API Route だけのゲートでは PostgREST 直叩きで迂回されるため、DB 側で強制する。
--
-- 既知の限界（許容済み）:
--   同一トレーナーへの同時 INSERT が競合すると、双方の count(*) が上限未満を観測し、
--   上限を僅かに超えて確定するレースが存在する（READ COMMITTED のスナップショット特性）。
--   advisory lock（pg_advisory_xact_lock(trainer_id)）で直列化すれば防げるが、
--   顧客登録は QR 連携由来の低頻度操作であり、超過しても高々同時実行数分に留まるため
--   今回は導入しない。厳密化が必要になった時点で advisory lock を追加すること。

-- ============================================================
-- 1. トリガー関数 enforce_client_limit()
-- ============================================================
-- SECURITY DEFINER の理由:
--   実行者は Mobile のクライアント本人（authenticated）だが、clients の SELECT ポリシーは
--   「トレーナー本人の顧客のみ」等に絞られており、本人ロールのままでは
--   移籍先トレーナー配下の顧客数を count できない。定義者（postgres = テーブルオーナー）
--   権限で RLS を跨いで正確に数えるために必要。
--   search_path 固定（public, pg_temp）で search_path ハイジャックを防ぐ。

CREATE OR REPLACE FUNCTION public.enforce_client_limit()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_plan           text;
  v_trial_ends_at  timestamptz;
  v_effective_plan text;
  v_limit          integer;
  v_current_count  bigint;
BEGIN
  -- trainer_id 未設定は対象外（現行スキーマは NOT NULL だが防御的に許可）
  IF NEW.trainer_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- UPDATE で trainer_id が変わらない場合は許可（乗り換えではない。
  -- registration_provider の upsert が既存行に当たるケースもここで素通しになる）
  IF TG_OP = 'UPDATE' AND OLD.trainer_id IS NOT DISTINCT FROM NEW.trainer_id THEN
    RETURN NEW;
  END IF;

  SELECT t.subscription_plan, t.trial_ends_at
    INTO v_plan, v_trial_ends_at
    FROM public.trainers t
   WHERE t.id = NEW.trainer_id;

  -- trainers 行が無ければ許可（存在しない trainer_id は clients_trainer_id_fkey が拒否する）
  IF NOT FOUND THEN
    RETURN NEW;
  END IF;

  -- 実効プラン（20260712000000 §2 の計算式と同一）
  IF COALESCE(v_plan, 'free') <> 'free' THEN
    v_effective_plan := v_plan;
  ELSIF v_trial_ends_at IS NOT NULL AND v_trial_ends_at > now() THEN
    v_effective_plan := 'pro'; -- 14日 Pro トライアル中
  ELSE
    v_effective_plan := 'free';
  END IF;

  v_limit := CASE v_effective_plan
    WHEN 'business' THEN 30
    WHEN 'pro'      THEN 10
    ELSE 3 -- free
  END;

  -- 自分自身（upsert / 乗り換え元の自行）を除いた現在の顧客数
  SELECT count(*)
    INTO v_current_count
    FROM public.clients c
   WHERE c.trainer_id = NEW.trainer_id
     AND c.client_id <> NEW.client_id;

  IF v_current_count >= v_limit THEN
    -- メッセージ文字列 'CLIENT_LIMIT_REACHED' は固定。
    -- クライアント側（Web/Mobile）はこの文字列でエラーマッチする。変更禁止。
    RAISE EXCEPTION 'CLIENT_LIMIT_REACHED'
      USING ERRCODE = 'P0001',
            DETAIL  = format(
              'trainer_id=%s plan=%s limit=%s current=%s',
              NEW.trainer_id, v_effective_plan, v_limit, v_current_count
            ),
            HINT    = 'このトレーナーの顧客数がプラン上限に達しています。プランをアップグレードしてください。';
  END IF;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.enforce_client_limit() IS
  'プラン別顧客数上限（free=3/pro=10/business=30、トライアル中はpro扱い）を BEFORE トリガーで強制する。上限到達時は CLIENT_LIMIT_REACHED（P0001）。仕様: docs/tasks/2026-07-11-pro-pricing-proposal.md §8';

-- ============================================================
-- 2. トリガー enforce_client_limit_trigger
-- ============================================================
-- clients の既存トリガーは無し（2026-07-12 時点の migrations 全数確認）。
-- UPDATE OF trainer_id: trainer_id が SET 句に含まれる UPDATE のみ発火。
--   値が実際には変わらないケースは関数冒頭の IS NOT DISTINCT FROM ガードで素通しする。

DROP TRIGGER IF EXISTS enforce_client_limit_trigger ON public.clients;

CREATE TRIGGER enforce_client_limit_trigger
  BEFORE INSERT OR UPDATE OF trainer_id ON public.clients
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_client_limit();
