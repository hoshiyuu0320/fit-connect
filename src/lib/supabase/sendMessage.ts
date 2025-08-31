import { supabase } from '@/lib/supabase';

type MessageParam = {
    senderId: string;
    receiverId: string;
    message: string;
    senderType: 'client' | 'trainer';
    receiverType: 'client' | 'trainer';
};

export const sendMessage = async ({ senderId, receiverId, message, senderType, receiverType}: MessageParam ) => {
    const { data, error } = await supabase
    .from('messages')
    .insert([
        {
            sender_id: senderId,
            receiver_id: receiverId,
            message: message,
            timestamp: new Date().toISOString(),
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