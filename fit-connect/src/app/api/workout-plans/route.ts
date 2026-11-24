import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'
import { requireTrainer } from '@/lib/api/guards'

export async function GET() {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const { data, error } = await supabaseAdmin
      .from('workout_plans')
      .select('*, exercises:workout_exercises(*)')
      .eq('trainer_id', trainerId)
      .order('created_at', { ascending: false })

    if (error) throw error

    const plans = (data || []).map((plan) => ({
      ...plan,
      exercise_count: plan.exercises?.length || 0,
    }))

    return NextResponse.json({ status: 'ok', data: plans })
  } catch (error) {
    console.error('ワークアウトプラン取得エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response
  const trainerId = auth.user.id

  try {
    const body = await request.json()
    const { title, description, category, planType, estimatedMinutes, exercises } = body

    if (!title) {
      return NextResponse.json({ error: 'title is required' }, { status: 400 })
    }

    // ワークアウトプランを作成
    const { data: plan, error: planError } = await supabaseAdmin
      .from('workout_plans')
      .insert([
        {
          trainer_id: trainerId,
          title,
          description: description || null,
          category: category || 'other',
          plan_type: planType || 'session',
          estimated_minutes: estimatedMinutes || null,
        },
      ])
      .select()
      .single()

    if (planError) throw planError

    // 種目を一括登録
    if (exercises && exercises.length > 0) {
      const exerciseRows = exercises.map(
        (ex: {
          name: string
          sets: number
          reps?: number
          weight?: number
          durationSeconds?: number
          restSeconds?: number
          memo?: string
          orderIndex: number
        }) => ({
          plan_id: plan.id,
          name: ex.name,
          sets: ex.sets,
          reps: ex.reps || null,
          weight: ex.weight || null,
          duration_seconds: ex.durationSeconds || null,
          rest_seconds: ex.restSeconds || null,
          memo: ex.memo || null,
          order_index: ex.orderIndex,
        })
      )

      const { error: exercisesError } = await supabaseAdmin
        .from('workout_exercises')
        .insert(exerciseRows)

      if (exercisesError) throw exercisesError
    }

    return NextResponse.json({ status: 'ok', data: plan })
  } catch (error) {
    console.error('ワークアウトプラン作成エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
