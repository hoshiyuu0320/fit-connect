import { supabase } from '@/lib/supabase';

type MessageParam = {
    senderId: string;
    receiverId: string;
    content: string;
    senderType: 'client' | 'trainer';
    receiverType: 'client' | 'trainer';
};

export const sendMessage = async ({ senderId, receiverId, content, senderType, receiverType}: MessageParam ) => {
    const { data, error } = await supabase
    .from('messages')
    .insert([
        {
            sender_id: senderId,
            receiver_id: receiverId,
            content: content,
            sender_type: senderType,
            receiver_type: receiverType,
        },
    ]);

    if (error) {
        console.error('メッセージ送信エラー：', error);
        throw error;
    }

    return data;
}