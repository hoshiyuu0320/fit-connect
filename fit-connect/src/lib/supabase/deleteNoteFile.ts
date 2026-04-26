import { supabase } from '@/lib/supabase'

export async function deleteNoteFile(fileUrl: string): Promise<void> {
  // ハッシュフラグメント（元ファイル名）を除去
  const urlWithoutHash = fileUrl.split('#')[0]
  // publicUrlからStorageパスを抽出
  const bucketPath = '/storage/v1/object/public/client-notes/'
  const pathIndex = urlWithoutHash.indexOf(bucketPath)

  if (pathIndex === -1) {
    throw new Error('無効なファイルURLです')
  }

  const filePath = urlWithoutHash.substring(pathIndex + bucketPath.length)

  const { error } = await supabase.storage
    .from('client-notes')
    .remove([filePath])

  if (error) {
    console.error('ファイル削除エラー:', error)
    throw error
  }
}
