-- Update the webhook function to include image_urls in payload
CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
RETURNS TRIGGER AS $$
DECLARE
  payload jsonb;
  edge_function_url text;
BEGIN
  -- Build the payload with image_urls
  payload := jsonb_build_object(
    'type', 'INSERT',
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

  -- Production Edge Function URL
  edge_function_url := 'https://viribpvnpgtgtmeulcmx.supabase.co/functions/v1/parse-message-tags';

  -- Call Edge Function without auth (--no-verify-jwt)
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
