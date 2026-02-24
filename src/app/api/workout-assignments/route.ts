import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function GET(request: NextRequest) {
  const searchParams = request.nextUrl.searchParams
  const trainerId = searchParams.get('trainerId')
  const clientId = searchParams.get('clientId')
  const weekStart = searchParams.get('weekStart')
  const weekEnd = searchParams.get('weekEnd')
  const includeHistory = searchParams.get('includeHistory') === 'true'

  if (!trainerId || !clientId || !weekEnd) {
    return NextResponse.json(
      { error: 'trainerId, clientId, weekEnd are required' },
      { status: 400 }
    )
  }

  if (!includeHistory && !weekStart) {
    return NextResponse.json(
      { error: 'weekStart is required when includeHistory is not true' },
      { status: 400 }
    )
  }

  // includeHistory の場合は weekEnd から過去30日分を取得
  let effectiveStart: string
  if (includeHistory) {
    const effectiveStartDate = new Date(weekEnd)
    effectiveStartDate.setDate(effectiveStartDate.getDate() - 30)
    effectiveStart = effectiveStartDate.toISOString().split('T')[0]
  } else {
    effectiveStart = weekStart!
  }

  try {
    const { data, error } = await supabaseAdmin
      .from('workout_assignments')
      .select(`
        *,
        plan:workout_plans (
          id,
          title,
          category,
          plan_type,
          estimated_minutes
        ),
        exercises:workout_assignment_exercises (*)
      `)
      .eq('trainer_id', trainerId)
      .eq('client_id', clientId)
      .gte('assigned_date', effectiveStart)
      .lte('assigned_date', weekEnd)
      .order('assigned_date', { ascending: true })

    if (error) throw error

    return NextResponse.json({ status: 'ok', data: data || [] })
  } catch (error) {
    console.error('アサインメント取得エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}

export async function POST(request: NextRequest) {
  try {
    const body = await request.json()
    const { trainerId, clientId, planId, assignedDate, ticketId, sessionTime, createSession, sessionId } = body

    if (!trainerId || !clientId || !planId || !assignedDate) {
      return NextResponse.json(
        { error: 'trainerId, clientId, planId, assignedDate are required' },
        { status: 400 }
      )
    }

    // アサインメントを作成
    const { data: assignment, error: assignmentError } = await supabaseAdmin
      .from('workout_assignments')
      .insert([
        {
          trainer_id: trainerId,
          client_id: clientId,
          plan_id: planId,
          assigned_date: assignedDate,
          status: 'pending',
          session_id: sessionId || null,
        },
      ])
      .select()
      .single()

    if (assignmentError) throw assignmentError

    // テンプレートの種目を取得
    const { data: exercises, error: exercisesError } = await supabaseAdmin
      .from('workout_exercises')
      .select('*')
      .eq('plan_id', planId)
      .order('order_index', { ascending: true })

    if (exercisesError) throw exercisesError

    // アサインメント種目を一括作成（テンプレートのコピー）
    if (exercises && exercises.length > 0) {
      const assignmentExerciseRows = exercises.map(
        (ex: {
          name: string
          sets: number
          reps: number | null
          weight: number | null
          order_index: number
        }) => ({
          assignment_id: assignment.id,
          exercise_name: ex.name,
          target_sets: ex.sets,
          target_reps: ex.reps || 0,
          target_weight: ex.weight || null,
          order_index: ex.order_index,
          actual_sets: null,
          is_completed: false,
          memo: null,
          linked_exercise_id: null,
        })
      )

      const { error: insertError } = await supabaseAdmin
        .from('workout_assignment_exercises')
        .insert(assignmentExerciseRows)

      if (insertError) throw insertError
    }

    // createSession=true かつ sessionId が渡されていない場合、sessions テーブルにレコードを作成
    if (createSession === true && !sessionId) {
      // プランの estimated_minutes を取得
      const { data: plan } = await supabaseAdmin
        .from('workout_plans')
        .select('estimated_minutes')
        .eq('id', planId)
        .single()

      // セッション日時を決定（sessionTime が指定されていない場合は 10:00 をデフォルトとする）
      const sessionDate = sessionTime
        ? new Date(`${assignedDate}T${sessionTime}`)
        : new Date(`${assignedDate}T10:00`)

      const { data: newSession, error: sessionError } = await supabaseAdmin
        .from('sessions')
        .insert({
          trainer_id: trainerId,
          client_id: clientId,
          session_date: sessionDate.toISOString(),
          duration_minutes: plan?.estimated_minutes || 60,
          status: 'scheduled',
          ticket_id: ticketId || null,
        })
        .select()
        .single()

      if (sessionError) throw sessionError

      // workout_assignments に session_id を紐付け
      await supabaseAdmin
        .from('workout_assignments')
        .update({ session_id: newSession.id })
        .eq('id', assignment.id)

      // ticketId が指定されている場合はチケット消費処理
      if (ticketId) {
        const { data: ticket, error: ticketFetchError } = await supabaseAdmin
          .from('tickets')
          .select('remaining_sessions')
          .eq('id', ticketId)
          .single()

        if (ticketFetchError) throw ticketFetchError

        if (ticket.remaining_sessions <= 0) {
          return NextResponse.json(
            { error: 'チケットの残り回数がありません' },
            { status: 400 }
          )
        }

        const { error: ticketUpdateError } = await supabaseAdmin
          .from('tickets')
          .update({ remaining_sessions: ticket.remaining_sessions - 1 })
          .eq('id', ticketId)

        if (ticketUpdateError) throw ticketUpdateError
      }
    }

    return NextResponse.json({ status: 'ok', data: assignment })
  } catch (error) {
    console.error('アサインメント作成エラー:', error)
    return NextResponse.json({ error: 'Internal Server Error' }, { status: 500 })
  }
}
