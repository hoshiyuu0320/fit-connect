import { supabase } from '@/lib/supabase';

// トレーナーのクライアント別未読メッセージ数を取得（RPC使用）
// clientsテーブルに存在するクライアントのみカウント
// 戻り値: Map<string, number> (client_id → 未読件数)
export async function getUnreadCounts(trainerId: string): Promise<Map<string, number>> {
  const { data, error } = await supabase
    .rpc('get_unread_counts_for_trainer', { p_trainer_id: trainerId });

  if (error) {
    console.error('Error fetching unread counts:', error);
    return new Map();
  }

  const countMap = new Map<string, number>();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data?.forEach((row: any) => {
    countMap.set(row.sender_id, Number(row.unread_count));
  });

  return countMap;
}
