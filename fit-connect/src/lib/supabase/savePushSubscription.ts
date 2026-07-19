import { supabaseAdmin } from '@/lib/supabaseAdmin'

export type PushSubscriptionData = {
  trainerId: string
  endpoint: string
  p256dh: string
  auth: string
}

export async function savePushSubscription(data: PushSubscriptionData) {
  const { error } = await supabaseAdmin
    .from('push_subscriptions')
    .upsert(
      {
        trainer_id: data.trainerId,
        endpoint: data.endpoint,
        p256dh: data.p256dh,
        auth: data.auth,
        updated_at: new Date().toISOString(),
      },
      { onConflict: 'endpoint' }
    )

  if (error) throw error

  // 段階移行 stage1: device_tokens への両書き（読み取り・送信側の切替は PR2）
  // device_tokens 側の失敗は既存の push_subscriptions フローを壊さない（ログのみ）
  try {
    const { error: deviceTokenError } = await supabaseAdmin
      .from('device_tokens')
      .upsert(
        {
          user_id: data.trainerId,
          user_type: 'trainer',
          platform: 'web_push',
          token: data.endpoint,
          web_push_p256dh: data.p256dh,
          web_push_auth: data.auth,
          last_seen_at: new Date().toISOString(),
        },
        { onConflict: 'user_id,token' }
      )

    if (deviceTokenError) {
      console.error('[savePushSubscription] device_tokens upsert failed:', deviceTokenError)
    }
  } catch (e) {
    console.error('[savePushSubscription] device_tokens upsert threw:', e)
  }
}
