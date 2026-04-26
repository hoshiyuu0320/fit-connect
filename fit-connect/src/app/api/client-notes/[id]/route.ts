import { NextRequest, NextResponse } from 'next/server'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function PUT(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params
  const body = await req.json()
  const { title, content, fileUrls, isShared, sessionNumber } = body

  if (!id) {
    return NextResponse.json({ error: 'Missing note ID' }, { status: 400 })
  }

  const updateData: Record<string, unknown> = {
    updated_at: new Date().toISOString(),
  }

  if (title !== undefined) updateData.title = title
  if (content !== undefined) updateData.content = content
  if (fileUrls !== undefined) updateData.file_urls = fileUrls
  if (sessionNumber !== undefined) updateData.session_number = sessionNumber
  if (isShared !== undefined) {
    updateData.is_shared = isShared
    if (isShared) {
      updateData.shared_at = new Date().toISOString()
    } else {
      updateData.shared_at = null
    }
  }

  const { data, error } = await supabaseAdmin
    .from('client_notes')
    .update(updateData)
    .eq('id', id)
    .select()
    .single()

  if (error) {
    console.error('カルテ更新エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok', data })
}

export async function DELETE(
  req: NextRequest,
  { params }: { params: Promise<{ id: string }> }
) {
  const { id } = await params

  if (!id) {
    return NextResponse.json({ error: 'Missing note ID' }, { status: 400 })
  }

  // まずノート情報を取得してファイルURLを確認
  const { data: note, error: fetchError } = await supabaseAdmin
    .from('client_notes')
    .select('file_urls')
    .eq('id', id)
    .single()

  if (fetchError) {
    console.error('カルテ取得エラー:', fetchError)
    return NextResponse.json({ error: fetchError.message }, { status: 500 })
  }

  // 関連ファイルをStorageから削除
  if (note?.file_urls && note.file_urls.length > 0) {
    const bucketPath = '/storage/v1/object/public/client-notes/'
    const filePaths = note.file_urls
      .map((url: string) => {
        const pathIndex = url.indexOf(bucketPath)
        if (pathIndex === -1) return null
        return url.substring(pathIndex + bucketPath.length)
      })
      .filter(Boolean) as string[]

    if (filePaths.length > 0) {
      const { error: storageError } = await supabaseAdmin.storage
        .from('client-notes')
        .remove(filePaths)

      if (storageError) {
        console.error('ファイル削除エラー:', storageError)
        // ファイル削除エラーはログのみ、ノート削除は続行
      }
    }
  }

  // ノートを削除
  const { error } = await supabaseAdmin
    .from('client_notes')
    .delete()
    .eq('id', id)

  if (error) {
    console.error('カルテ削除エラー:', error)
    return NextResponse.json({ error: error.message }, { status: 500 })
  }

  return NextResponse.json({ status: 'ok' })
}
