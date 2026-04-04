-- UPDATE対応: call_parse_message_tags()関数をTG_OP対応に変更し、UPDATEトリガーを追加

-- 1. call_parse_message_tags()関数を再定義（TG_OP対応、UPDATE時のold_record追加）
CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
RETURNS TRIGGER AS $$
DECLARE
  payload jsonb;
  edge_function_url text;
BEGIN
  -- 基本ペイロード（INSERT/UPDATE共通）
  payload := jsonb_build_object(
    'type', TG_OP,  -- 'INSERT' or 'UPDATE'
    'table', 'messages',
    'record', jsonb_build_object(
      'id', NEW.id,
      'content', NEW.content,
      'sender_id', NEW.sender_id,
      'receiver_id', NEW.receiver_id,
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. UPDATEトリガーを追加（contentカラム変更時のみ発火）
CREATE TRIGGER on_message_update
  AFTER UPDATE OF content ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.call_parse_message_tags();
