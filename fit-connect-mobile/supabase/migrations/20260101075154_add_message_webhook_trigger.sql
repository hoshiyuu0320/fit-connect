-- Create a function to call the Edge Function when a message is inserted
CREATE OR REPLACE FUNCTION public.call_parse_message_tags()
RETURNS TRIGGER AS $$
DECLARE
  payload jsonb;
  edge_function_url text;
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

  -- Get the Edge Function URL (localhost for local development)
  edge_function_url := 'http://host.docker.internal:54321/functions/v1/parse-message-tags';

  -- Make the HTTP request using pg_net
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

-- Create trigger to call the function after insert
DROP TRIGGER IF EXISTS on_message_insert ON public.messages;
CREATE TRIGGER on_message_insert
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public.call_parse_message_tags();
