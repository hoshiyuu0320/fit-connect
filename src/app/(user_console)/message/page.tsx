// app/chat/page.tsx
'use client';

import { useEffect, useState } from "react";
import { useUserStore } from '@/store/userStore';
import { supabase } from '@/lib/supabase';
import { sendMessage } from '@/lib/supabase/sendMessage';
import { getClients } from '@/lib/supabase/getClients';
import { getMessages } from '@/lib/supabase/getMessages';
import type { RealtimeChannel } from '@supabase/supabase-js';

export default function MessagePage() {
    type Message = {
        sender: string,
        content: string,
        timestamp: string,
        senderType: 'client' | 'trainer',
        receiverType: 'client' | 'trainer',
    }

    type Client = {
        clientId: string;
        clientName: string;
    }

    const { userName } = useUserStore()
    const [userId, setUserId] = useState<string | null>(null);
    const [input, setInput] = useState('');
    const [clientList, setClientList] = useState<any[]>([]);
    const [selectedClient, setSelectedClient] = useState<Client | null>(null);
    const [messages, setMessages] = useState<Message[]>([]);

    const handleSend = async () => {
        if (!input.trim() || !userId || !selectedClient?.clientId) return;

        try {
            await sendMessage({
                senderId: userId,
                receiverId: selectedClient.clientId,
                message: input,
                senderType: 'trainer',
                receiverType: 'client',
            });

            setMessages([...messages, {
                sender: 'You',
                content: input,
                timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                senderType: 'trainer',
                receiverType: 'client',
            }]);
            setInput('');
        } catch (err) {
            console.error('送信エラー:', err);
        }
    }

    // 顧客情報の取得
    useEffect(() => {
        const fetchClients = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser()

            if (user) {
                setUserId(user.id);
                const clients = await getClients(user.id)
                console.log("user.id" + user.id)
                setClientList(clients)
            }
        }
        fetchClients();
    }, []);

    // メッセージ取得処理
    useEffect(() => {
        if (!selectedClient) return;

        let channel: RealtimeChannel | null = null;
        let currentUser: any = null;

        const fetchAndSubscribe = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser();

            if (!user) return;
            currentUser = user;

            // ✅ 初期取得処理
            const rawMessages = await getMessages({
                senderId: user.id,
                receiverId: selectedClient.clientId,
            });
            console.log("rawMessages", rawMessages);

            const formattedMessages: Message[] = rawMessages.map((msg: any) => ({
                sender: msg.sender_type === 'client' ? selectedClient.clientName : 'You',
                content: msg.message,
                timestamp: new Date(msg.timestamp).toLocaleTimeString([], {
                    hour: '2-digit',
                    minute: '2-digit',
                }),
                senderType: msg.sender_type,
                receiverType: msg.receiver_type,
            }));
            console.log("formattedMessages", formattedMessages);

            setMessages(formattedMessages);

            // ✅ Realtime購読
            channel = supabase
                .channel('message-room')
                .on(
                    'postgres_changes',
                    {
                        event: 'INSERT',
                        schema: 'public',
                        table: 'messages',
                        filter: `receiver_id=eq.${user.id}`,
                    },
                    (payload) => {
                        const msg = payload.new;

                        // 送信者と受信者が一致する場合にのみ反映
                        if (msg.receiver_id !== user.id || msg.sender_id !== selectedClient.clientId) return;

                        const newMsg: Message = {
                            sender: selectedClient.clientName,
                            content: msg.message,
                            timestamp: new Date(msg.timestamp).toLocaleTimeString([], {
                                hour: '2-digit',
                                minute: '2-digit',
                            }),
                            senderType: msg.sender_type,
                            receiverType: msg.receiver_type,
                        };
                        setMessages((prev) => [...prev, newMsg]);
                    }
                )
                .subscribe();
        };
        fetchAndSubscribe();
        return () => {
            if (channel) supabase.removeChannel(channel);
        };
    }, [selectedClient]);

    return (
        <div className="flex h-[calc(100vh-48px)]  bg-gray-50 text-gray-900 overflow-hidden">

            {/* Sidebar */}
            <aside className="w-64 bg-white border-r p-4 space-y-2">
                <h2 className="text-lg font-semibold mb-4">Clients</h2>
                <ul className="space-y-1">
                    {clientList.map((client) => (
                        <li
                            key={client.client_id}
                            className={`cursor-pointer p-2 rounded ${selectedClient?.clientId === client.client_id ? 'bg-blue-100' : ''
                                }`}
                            onClick={() => {
                                setSelectedClient(
                                    {
                                        clientId: client.client_id,
                                        clientName: client.name
                                    }
                                )
                            }
                            }
                        >
                            👤 {client.name}
                        </li>
                    ))}
                </ul>
            </aside>

            {/* Chat Area */}
            <div className="flex flex-col flex-1 overflow-hidden">
                {/* Header */}
                <header className="flex justify-between items-center px-4 py-3 border-b bg-white">
                    <h1 className="text-lg font-semibold">{selectedClient?.clientName || ''}</h1>
                    <div className="flex items-center space-x-3">
                        <span className="text-sm">{userName}</span>
                        <div className="w-8 h-8 bg-gray-300 rounded-full" />
                    </div>
                </header>

                {/* Messages */}
                <main className="flex-1 overflow-y-auto p-6 space-y-4">
                    {messages.map((msg, index) => (
                        <div key={index} className="flex items-start space-x-3">
                            <div className="w-10 h-10 bg-gray-300 rounded-full" />
                            <div>
                                <div className='text-sm font-medium'>
                                    {msg.sender}{' '}
                                    <span className='text-gray-500 text-xs ml-2'>{msg.timestamp}</span>
                                </div>
                                <div className={`p-3 rounded border mt-1 max-w-md ${msg.senderType === 'client' ? 'bg-white' : 'bg-blue-100'}`}>
                                    {msg.content}
                                </div>
                            </div>
                        </div>
                    ))}
                </main>

                {/* Input */}
                <footer className="border-t p-4 bg-white">
                    <div className="flex items-center space-x-3">
                        <input
                            type="text"
                            value={input}
                            onChange={(e) => setInput(e.target.value)}
                            placeholder="Send a message..."
                            className="flex-1 border rounded px-3 py-2 outline-none focus:ring-2 focus:ring-blue-300"
                        />
                        <button
                            onClick={handleSend}
                            className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700"
                        >
                            Send
                        </button>
                    </div>
                </footer>
            </div>
        </div>
    );
}