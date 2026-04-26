import { supabase } from '../supabase'

const ALLOWED_TYPES = ['image/jpeg', 'image/png', 'image/webp']
const MAX_FILE_SIZE = 2 * 1024 * 1024 // 2MB

export async function uploadProfileImage(
  file: File,
  trainerId: string
): Promise<string> {
  // Validate file type
  if (!ALLOWED_TYPES.includes(file.type)) {
    throw new Error(
      'Invalid file type. Only JPEG, PNG, and WebP images are allowed.'
    )
  }

  // Validate file size
  if (file.size > MAX_FILE_SIZE) {
    throw new Error('File size exceeds 2MB limit.')
  }

  // Generate safe filename with ASCII characters only
  const timestamp = Date.now()
  const safeName = file.name.replace(/[^a-zA-Z0-9._-]/g, '_')
  const filePath = `${trainerId}/${timestamp}_${safeName}`

  // Upload to Supabase Storage
  const { error: uploadError } = await supabase.storage
    .from('profile-images')
    .upload(filePath, file, {
      cacheControl: '3600',
      upsert: false,
    })

  if (uploadError) throw uploadError

  // Get public URL
  const {
    data: { publicUrl },
  } = supabase.storage.from('profile-images').getPublicUrl(filePath)

  // Append original filename as hash fragment for display purposes
  const urlWithOriginalName = `${publicUrl}#${encodeURIComponent(file.name)}`

  return urlWithOriginalName
}
