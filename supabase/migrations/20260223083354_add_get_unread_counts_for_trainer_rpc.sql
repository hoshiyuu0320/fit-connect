
CREATE OR REPLACE FUNCTION get_unread_counts_for_trainer(p_trainer_id uuid)
RETURNS TABLE (
  sender_id uuid,
  unread_count bigint
) AS $$
  SELECT m.sender_id, count(*) as unread_count
  FROM public.messages m
  INNER JOIN public.clients c ON c.client_id = m.sender_id AND c.trainer_id = p_trainer_id
  WHERE m.receiver_id = p_trainer_id
    AND m.read_at IS NULL
    AND m.sender_type = 'client'
  GROUP BY m.sender_id;
$$ LANGUAGE sql STABLE;
;
