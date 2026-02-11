import { supabase } from '@/lib/supabase'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp', 'image/heic']
const MAX_FILE_SIZE = 5 * 1024 * 1024 // 5MB

export async function uploadMessageImage(
  file: File,
  trainerId: string,
  clientId: string,
): Promise<string> {
  if (!ALLOWED_TYPES.includes(file.type)) {
    throw new Error('対応していないファイル形式です（JPEG, PNG, WebP, HEICのみ）')
  }

  if (file.size > MAX_FILE_SIZE) {
    throw new Error('ファイルサイズが5MBを超えています')
  }

  const ext = file.name.split('.').pop() || 'jpg'
  const timestamp = Date.now()
  const randomId = crypto.randomUUID()
  const path = `${trainerId}/${clientId}/${timestamp}_${randomId}.${ext}`

  const { error } = await supabase.storage
    .from('message-photos')
    .upload(path, file)

  if (error) {
    console.error('画像アップロードエラー:', error)
    throw error
  }

  const { data: { publicUrl } } = supabase.storage
    .from('message-photos')
    .getPublicUrl(path)

  return publicUrl
}
