
CREATE OR REPLACE FUNCTION get_last_messages_for_trainer(p_trainer_id uuid)
RETURNS TABLE (
  client_id uuid,
  content text,
  image_urls text[],
  created_at timestamptz
) AS $$
  SELECT DISTINCT ON (partner_id) 
    partner_id as client_id,
    m.content,
    m.image_urls,
    m.created_at
  FROM (
    SELECT *,
      CASE 
        WHEN sender_id = p_trainer_id THEN receiver_id 
        ELSE sender_id 
      END as partner_id
    FROM public.messages
    WHERE sender_id = p_trainer_id OR receiver_id = p_trainer_id
  ) m
  ORDER BY partner_id, created_at DESC;
$$ LANGUAGE sql STABLE;
;
