import { NextRequest, NextResponse } from 'next/server'
import { updateTrainer } from '@/lib/supabase/updateTrainer'
import { requireTrainer } from '@/lib/api/guards'

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const auth = await requireTrainer()
  if (auth.response) return auth.response

  try {
    const { id } = await params

    if (id !== auth.user.id) {
      return NextResponse.json({ error: 'FORBIDDEN' }, { status: 403 })
    }

    const body = await request.json()

    const { name, email, profileImageUrl } = body

    const updatedTrainer = await updateTrainer({
      id: auth.user.id,
      name,
      email,
      profileImageUrl,
    })

    return NextResponse.json({
      status: 'ok',
      data: updatedTrainer,
    })
  } catch (error) {
    console.error('API Error:', error)
    const errorMessage =
      error instanceof Error ? error.message : 'Internal Server Error'

    return NextResponse.json(
      {
        status: 'error',
        message: errorMessage,
      },
      { status: 500 }
    )
  }
}
