import { supabaseAdmin } from '@/lib/supabaseAdmin'

export type PushSubscriptionData = {
  trainerId: string
  endpoint: string
  p256dh: string
  auth: string
}

/**
 * トレーナーのブラウザの Web Push 購読を登録する（設計書 §7.6）。
 *
 * 1. device_tokens に自分の行を upsert（送信側 _shared/push.ts が読む唯一の宛先）
 * 2. 同じ endpoint を持つ「他のトレーナー」の web_push 行を消す。購読はブラウザに付くので、
 *    同じブラウザで後から登録したトレーナー1人のものにする（前のトレーナー宛の通知が出続けないように）。
 *    顧客の ios / android 行は触らない
 * 3. 旧 push_subscriptions に upsert（段階移行の両書き。失敗しても応答は失敗にしない）
 *
 * 1・2 の失敗は throw する（API ルートが 500 を返す）。どちらも何度流しても同じ結果になるので、画面から再試行できる。
 * 1 を先にするのは、削除だけが済んで自分の行が無い（誰にも届かない）状態を作らないため。
 */
export async function savePushSubscription(data: PushSubscriptionData) {
  const now = new Date().toISOString()

  const { error: upsertError } = await supabaseAdmin
    .from('device_tokens')
    .upsert(
      {
        user_id: data.trainerId,
        user_type: 'trainer',
        platform: 'web_push',
        token: data.endpoint,
        web_push_p256dh: data.p256dh,
        web_push_auth: data.auth,
        last_seen_at: now,
      },
      { onConflict: 'user_id,token' }
    )
  if (upsertError) throw upsertError

  const { error: deleteError } = await supabaseAdmin
    .from('device_tokens')
    .delete()
    .eq('platform', 'web_push')
    .eq('token', data.endpoint)
    .eq('user_type', 'trainer')
    .neq('user_id', data.trainerId)
  if (deleteError) throw deleteError

  // 段階移行の両書き（旧 push_subscriptions）。endpoint で一意なので、ここでも最後に登録したトレーナーのものになる
  try {
    const { error: legacyError } = await supabaseAdmin
      .from('push_subscriptions')
      .upsert(
        {
          trainer_id: data.trainerId,
          endpoint: data.endpoint,
          p256dh: data.p256dh,
          auth: data.auth,
          updated_at: now,
        },
        { onConflict: 'endpoint' }
      )
    if (legacyError) {
      console.error('[savePushSubscription] push_subscriptions upsert failed:', legacyError)
    }
  } catch (e) {
    console.error('[savePushSubscription] push_subscriptions upsert threw:', e)
  }
}
