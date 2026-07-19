-- Migration: repair_message_trigger_drift
-- 目的: リモートDBで直接編集され migration 管理外となっていた
--       call_parse_message_tags() の実定義を migration に追認し、
--       空DBからの `supabase db reset` でリモートと同一定義を再現する。
--       （repair パターン: 20260710010000〜010002 踏襲）
--
-- ドリフトの経緯:
--   - repo 内の最新定義 20260207000000_add_message_update_trigger.sql の payload には
--     sender_type / receiver_type が含まれていない。
--   - 一方リモートの実定義（2026-07-19 に pg_get_functiondef で実測）には
--     record.sender_type / record.receiver_type が含まれる。
--     parse-message-tags Edge Function が通知の宛先種別判定に使うキーであり、
--     リモートが手動修正されて repo が追従していなかった。
--   - また 20260207000000 は SECURITY DEFINER 付きだが、リモート実定義には
--     SECURITY DEFINER が無い（= SECURITY INVOKER）。本 migration はリモートを正とし、
--     属性含めて実測定義どおりに再定義する。
--
-- リモートには no-op である理由:
--   - 下記 CREATE OR REPLACE はリモートの pg_get_functiondef 出力と一言一句同一のため、
--     適用しても定義は一切変化しない。
--
-- fresh DB（空DBからの reset）での効果:
--   - 20260207000000 適用後の「payload に sender_type / receiver_type が欠落し
--     通知ペイロードが不完全になる」バグの修正となる。

CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$
DECLARE
  payload jsonb;
  edge_function_url text;
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

  -- Edge Function URL（本番環境）
  edge_function_url := 'https://viribpvnpgtgtmeulcmx.supabase.co/functions/v1/parse-message-tags';

  -- Edge Functionを呼び出し
  PERFORM net.http_post(
    url := edge_function_url,
    headers := jsonb_build_object(
      'Content-Type', 'application/json'
    ),
    body := payload
  );

  RETURN NEW;
END;
$function$;
