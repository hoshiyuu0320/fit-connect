-- Update the webhook function to use production Edge Function URL
CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
RETURNS TRIGGER AS $$
DECLARE
  payload jsonb;
  edge_function_url text;
  supabase_anon_key text;
BEGIN
  -- Build the payload
  payload := jsonb_build_object(
    'type', 'INSERT',
    'table', 'messages',
    'record', jsonb_build_object(
      'id', NEW.id,
      'content', NEW.content,
      'sender_id', NEW.sender_id,
      'receiver_id', NEW.receiver_id,
      'created_at', NEW.created_at
    )
  );

  -- Production Edge Function URL
  edge_function_url := 'https://viribpvnpgtgtmeulcmx.supabase.co/functions/v1/parse-message-tags';

  -- Get the anon key from vault (or use environment variable)
  -- Note: For production, you may want to use service_role key stored in vault
  supabase_anon_key := current_setting('app.settings.supabase_anon_key', true);

  -- If key is not set, try without auth (for Edge Functions with --no-verify-jwt)
  IF supabase_anon_key IS NULL OR supabase_anon_key = '' THEN
    PERFORM net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json'
      ),
      body := payload
    );
  ELSE
    PERFORM net.http_post(
      url := edge_function_url,
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || supabase_anon_key
      ),
      body := payload
    );
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
