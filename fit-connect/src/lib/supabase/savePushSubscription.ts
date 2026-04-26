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
}
