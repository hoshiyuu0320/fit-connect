import { supabase } from '@/lib/supabase'
import { extractStoragePath } from '@/lib/supabase/storagePaths'

/**
 * カルテ添付ファイルを client-notes バケットから削除する。
 * 値は「バケット相対パス（新形式）」「フルURL（レガシー行）」の両対応。
 */
export async function deleteNoteFile(fileUrl: string): Promise<void> {
  // フラグメント（元ファイル名）・クエリを除去し、フルURLならパスを逆算
  const filePath = extractStoragePath(fileUrl, 'client-notes')

  if (!filePath) {
    throw new Error('無効なファイルURLです')
  }

  const { error } = await supabase.storage
    .from('client-notes')
    .remove([filePath])

  if (error) {
    console.error('ファイル削除エラー:', error)
    throw error
  }
}
