import { supabase } from '@/lib/supabase';

type GetMessageParam = {
    senderId: string;
    receiverId: string;
};

export const getMessages = async ({senderId, receiverId} : GetMessageParam ) => {
    const { data, error } = await supabase
    .from('messages')
    .select('*')
    .or(`and(sender_id.eq.${senderId},receiver_id.eq.${receiverId}),and(sender_id.eq.${receiverId},receiver_id.eq.${senderId})`)
    .order('created_at', { ascending: true });

    if(error) {
        console.error('メッセージ取得エラー', error)
        throw error
    }

    return data
}