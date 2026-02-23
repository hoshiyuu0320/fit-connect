import { supabase } from '@/lib/supabase';

// トレーナー（受信者）のクライアント別未読メッセージ数を取得
// 戻り値: Map<string, number> (sender_id → 未読件数)
export async function getUnreadCounts(trainerId: string): Promise<Map<string, number>> {
  const { data, error } = await supabase
    .from('messages')
    .select('sender_id')
    .eq('receiver_id', trainerId)
    .is('read_at', null)
    .eq('sender_type', 'client');

  if (error) {
    console.error('Error fetching unread counts:', error);
    return new Map();
  }

  const countMap = new Map<string, number>();
  data?.forEach((msg) => {
    const current = countMap.get(msg.sender_id) || 0;
    countMap.set(msg.sender_id, current + 1);
  });

  return countMap;
}
