import { supabase } from '@/lib/supabase';

// トレーナーの全クライアントとの最終メッセージを取得（RPC使用）
// 戻り値: Map<clientId, { content, created_at }>
export async function getLastMessagesForClients(
  trainerId: string
): Promise<Map<string, { content: string; created_at: string }>> {
  const { data, error } = await supabase
    .rpc('get_last_messages_for_trainer', { p_trainer_id: trainerId });

  if (error) {
    console.error('Error fetching last messages:', error);
    return new Map();
  }

  const lastMessageMap = new Map<string, { content: string; created_at: string }>();

  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data?.forEach((row: any) => {
    lastMessageMap.set(row.client_id, {
      content: row.content || (row.image_urls?.length > 0 ? '画像' : ''),
      created_at: row.created_at,
    });
  });

  return lastMessageMap;
}
