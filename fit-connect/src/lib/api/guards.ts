import { NextResponse } from 'next/server'
import type { User } from '@supabase/supabase-js'
import { getAuthenticatedUser } from '@/lib/supabase/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export type TrainerAuth =
  | { user: User; response: null }
  | { user: null; response: NextResponse }

/**
 * API Route の認証ゲート。cookie セッションからトレーナーを特定する。
 * trainer_id は必ずここで得た user.id から導出し、リクエスト由来の値は使わない。
 */
export async function requireTrainer(): Promise<TrainerAuth> {
  const user = await getAuthenticatedUser()
  if (!user) {
    return {
      user: null,
      response: NextResponse.json({ error: 'UNAUTHORIZED' }, { status: 401 }),
    }
  }
  return { user, response: null }
}

/** 非所有・不在はどちらも 404（存在の推測を防ぐ） */
export function notFoundResponse(): NextResponse {
  return NextResponse.json({ error: 'NOT_FOUND' }, { status: 404 })
}

export async function trainerOwnsClient(
  trainerId: string,
  clientId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('clients')
    .select('client_id')
    .eq('client_id', clientId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

/** tickets は trainer_id 列を持たないため clients 経由で検証する */
export async function trainerOwnsTicket(
  trainerId: string,
  ticketId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('tickets')
    .select('client_id')
    .eq('id', ticketId)
    .maybeSingle()
  if (error || !data) return false
  return trainerOwnsClient(trainerId, data.client_id)
}

export async function trainerOwnsTemplate(
  trainerId: string,
  templateId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('ticket_templates')
    .select('id')
    .eq('id', templateId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

/** ticket_subscriptions は trainer_id 列を持たないため template 経由で検証する */
export async function trainerOwnsSubscription(
  trainerId: string,
  subscriptionId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('ticket_subscriptions')
    .select('template_id')
    .eq('id', subscriptionId)
    .maybeSingle()
  if (error || !data) return false
  return trainerOwnsTemplate(trainerId, data.template_id)
}

export async function trainerOwnsNote(
  trainerId: string,
  noteId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('client_notes')
    .select('id')
    .eq('id', noteId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

/** messages は sender_id/sender_type で所有を判定する */
export async function trainerOwnsMessage(
  trainerId: string,
  messageId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('messages')
    .select('sender_id, sender_type')
    .eq('id', messageId)
    .maybeSingle()
  if (error || !data) return false
  return data.sender_type === 'trainer' && data.sender_id === trainerId
}

export async function trainerOwnsPlan(
  trainerId: string,
  planId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('workout_plans')
    .select('id')
    .eq('id', planId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

export async function trainerOwnsAssignment(
  trainerId: string,
  assignmentId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('workout_assignments')
    .select('id')
    .eq('id', assignmentId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

export async function trainerOwnsSession(
  trainerId: string,
  sessionId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('sessions')
    .select('id')
    .eq('id', sessionId)
    .eq('trainer_id', trainerId)
    .maybeSingle()
  return !error && data !== null
}

export async function trainerOwnsAssignmentExercise(
  trainerId: string,
  exerciseId: string
): Promise<boolean> {
  const { data, error } = await supabaseAdmin
    .from('workout_assignment_exercises')
    .select('assignment_id')
    .eq('id', exerciseId)
    .maybeSingle()
  if (error || !data) return false
  return trainerOwnsAssignment(trainerId, data.assignment_id)
}
