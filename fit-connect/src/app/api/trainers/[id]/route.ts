import { NextRequest, NextResponse } from 'next/server'
import { updateTrainer } from '@/lib/supabase/updateTrainer'

export async function PUT(
  request: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  try {
    const { id } = await params
    const body = await request.json()

    const { name, email, profileImageUrl } = body

    const updatedTrainer = await updateTrainer({
      id,
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
