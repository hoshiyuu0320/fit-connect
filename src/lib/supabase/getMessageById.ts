import { supabase } from '@/lib/supabase'

export const getMessageById = async (messageId: string) => {
  const { data, error } = await supabase
    .from('messages')
    .select('*')
    .eq('id', messageId)
    .single()

  if (error) {
    console.error('メッセージ取得エラー', error)
    throw error
  }

  return data
}
