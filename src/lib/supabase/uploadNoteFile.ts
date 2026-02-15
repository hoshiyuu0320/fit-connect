import { supabase } from '@/lib/supabase'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'application/pdf']
const MAX_FILE_SIZE = 10 * 1024 * 1024 // 10MB

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

  const { data: { publicUrl } } = supabase.storage
    .from('client-notes')
    .getPublicUrl(path)

  // 元のファイル名をハッシュフラグメントに付加（表示用）
  return `${publicUrl}#${encodeURIComponent(file.name)}`
}
