import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function deletePushSubscription(trainerId: string, endpoint: string) {
  const { error } = await supabaseAdmin
    .from('push_subscriptions')
    .delete()
    .eq('trainer_id', trainerId)
    .eq('endpoint', endpoint)

  if (error) throw error
}
