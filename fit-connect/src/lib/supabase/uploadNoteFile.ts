import { supabase } from '@/lib/supabase'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10MB

/**
 * カルテ添付ファイルを client-notes バケットへアップロードする。
 * 戻り値は `パス#encodeURIComponent(元ファイル名)` 形式
 * （DB にはパスを保存し、表示時に署名URLへ解決する）。
 */
export async function uploadNoteFile(
  file: File,
  trainerId: string,
  clientId: string,
): Promise<string> {
  if (!ALLOWED_TYPES.includes(file.type)) {
    throw new Error('対応していないファイル形式です（JPEG, PNG, WebP, PDFのみ）')
  }

  if (file.size > MAX_FILE_SIZE) {
    throw new Error('ファイルサイズが10MBを超えています')
  }

  const timestamp = Date.now()
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const path = `${trainerId}/${clientId}/${timestamp}_${safeName}`

  const { error } = await supabase.storage
    .from('client-notes')
    .upload(path, file)

  if (error) {
    console.error('ファイルアップロードエラー:', error)
    throw error
  }

  // 元のファイル名をハッシュフラグメントに付加（表示用）。ベースはバケット相対パス
  return `${path}#${encodeURIComponent(file.name)}`
}
