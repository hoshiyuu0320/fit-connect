import { supabaseAdmin } from '@/lib/supabaseAdmin'

export type UpdateClientParams = {
  clientId: string
  age?: number
  gender?: 'male' | 'female' | 'other'
  occupation?: string | null
  height?: number
  target_weight?: number
  purpose?: 'diet' | 'contest' | 'body_make' | 'health_improvement' | 'mental_improvement' | 'performance_improvement'
  goal_description?: string | null
  goal_deadline?: string | null
}

export async function updateClient(params: UpdateClientParams) {
  const { clientId, ...fields } = params

  const updateData: Record<string, unknown> = {}

  if (fields.age !== undefined) updateData.age = fields.age
  if (fields.gender !== undefined) updateData.gender = fields.gender
  if (fields.occupation !== undefined) updateData.occupation = fields.occupation
  if (fields.height !== undefined) updateData.height = fields.height
  if (fields.target_weight !== undefined) updateData.target_weight = fields.target_weight
  if (fields.purpose !== undefined) updateData.purpose = fields.purpose
  if (fields.goal_description !== undefined) updateData.goal_description = fields.goal_description
  if (fields.goal_deadline !== undefined) updateData.goal_deadline = fields.goal_deadline

  const { data, error } = await supabaseAdmin
    .from('clients')
    .update(updateData)
    .eq('client_id', clientId)
    .select()
    .single()

  if (error) {
    throw error
  }

  return data
}
