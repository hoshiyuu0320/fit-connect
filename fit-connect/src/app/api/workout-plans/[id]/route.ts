import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing plan ID' }, { status: 400 })
  }

  try {
    const body = await request.json()
    const { title, description, category, planType, estimatedMinutes, exercises } = body

    // ワークアウトプランを更新
    const updateData: Record<string, unknown> = {
      updated_at: new Date().toISOString(),
    }
    if (title !== undefined) updateData.title = title
    if (description !== undefined) updateData.description = description
    if (category !== undefined) updateData.category = category
    if (planType !== undefined) updateData.plan_type = planType
    if (estimatedMinutes !== undefined) updateData.estimated_minutes = estimatedMinutes

    const { data: plan, error: planError } = await supabaseAdmin
      .from('workout_plans')
      .update(updateData)
      .eq('id', id)
      .select()
      .single()

    if (planError) throw planError

    // 既存の種目を削除して再登録
    if (exercises !== undefined) {
      const { error: deleteError } = await supabaseAdmin
        .from('workout_exercises')
        .delete()
        .eq('plan_id', id)

      if (deleteError) throw deleteError

      if (exercises.length > 0) {
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
            plan_id: id,
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

        const { error: insertError } = await supabaseAdmin
          .from('workout_exercises')
          .insert(exerciseRows)

        if (insertError) throw insertError
      }
    }

    return NextResponse.json({ status: 'ok', data: plan })
  } catch (error) {
    console.error('ワークアウトプラン更新エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}

export async function DELETE(
  _request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing plan ID' }, { status: 400 })
  }

  try {
    const { error } = await supabaseAdmin
      .from('workout_plans')
      .delete()
      .eq('id', id)

    if (error) throw error

    return NextResponse.json({ status: 'ok' })
  } catch (error) {
    console.error('ワークアウトプラン削除エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
