import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function deletePushSubscription(trainerId: string, endpoint: string) {
  const { error } = await supabaseAdmin
    .from('push_subscriptions')
    .delete()
    .eq('trainer_id', trainerId)
    .eq('endpoint', endpoint)

  if (error) throw error

  // 段階移行 stage1: device_tokens 側も削除（読み取り・送信側の切替は PR2）
  // device_tokens 側の失敗は既存の push_subscriptions フローを壊さない（ログのみ）
  try {
    const { error: deviceTokenError } = await supabaseAdmin
      .from('device_tokens')
      .delete()
      .eq('user_id', trainerId)
      .eq('token', endpoint)

    if (deviceTokenError) {
      console.error('[deletePushSubscription] device_tokens delete failed:', deviceTokenError)
    }
  } catch (e) {
    console.error('[deletePushSubscription] device_tokens delete threw:', e)
  }
}
