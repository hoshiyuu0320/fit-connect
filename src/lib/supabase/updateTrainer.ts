import { supabaseAdmin } from '../supabaseAdmin'
import { UpdateTrainerParams } from '@/types/trainer'

export async function updateTrainer(params: UpdateTrainerParams) {
  const { id, name, email, profileImageUrl } = params

  const updateData: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  }

  if (name !== undefined) updateData.name = name
  if (email !== undefined) updateData.email = email
  if (profileImageUrl !== undefined) updateData.profile_image_url = profileImageUrl

  const { data, error } = await supabaseAdmin
    .from('trainers')
    .update(updateData)
    .eq('id', id)
    .select()
    .single()

  if (error) throw error
  return data
}
