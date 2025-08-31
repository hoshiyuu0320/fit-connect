import { supabase } from '@/lib/supabase'

export const getClients = async (trainerId: string) => {
    const { data, error } = await supabase
    .from('clients')
    .select('*')
    .eq('trainer_id', trainerId) 
    console.table(data)
    console.log("hogehoge")
;
    if (error) {
        console.error('クライアント取得エラー：', error)
        throw error
    }

    return data
}