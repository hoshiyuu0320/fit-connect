import { supabase } from '@/lib/supabase';

// 指定クライアントからの未読メッセージを全て既読にマーク
export async function markMessagesAsRead(
  trainerId: string,
  clientId: string
): Promise<void> {
  const { error } = await supabase
    .from('messages')
    .update({ read_at: new Date().toISOString() })
    .eq('receiver_id', trainerId)
    .eq('sender_id', clientId)
    .is('read_at', null);

  if (error) {
    console.error('Error marking messages as read:', error);
  }
}
