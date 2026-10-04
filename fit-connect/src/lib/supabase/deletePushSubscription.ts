import { supabaseAdmin } from '@/lib/supabaseAdmin'

/**
 * トレーナー自身の Web Push 購読（endpoint 単位）を削除する。
 *
 * device_tokens（送信側が読む唯一の宛先）を先に消し、失敗は throw する（API ルートが 500 を返し、
 * 画面はブラウザの購読を解除しない。サーバーに行が残ったままブラウザの購読だけが消える状態を作らない）。
 * 旧 push_subscriptions の削除は段階移行の両書きで、失敗しても応答は失敗にしない。
 */
export async function deletePushSubscription(trainerId: string, endpoint: string) {
  const { error: deleteError } = await supabaseAdmin
    .from('device_tokens')
    .delete()
    .eq('user_id', trainerId)
    .eq('token', endpoint)
  if (deleteError) throw deleteError

  try {
    const { error: legacyError } = await supabaseAdmin
      .from('push_subscriptions')
      .delete()
      .eq('trainer_id', trainerId)
      .eq('endpoint', endpoint)
    if (legacyError) {
      console.error('[deletePushSubscription] push_subscriptions delete failed:', legacyError)
    }
  } catch (e) {
    console.error('[deletePushSubscription] push_subscriptions delete threw:', e)
  }
}
