// app/chat/page.tsx
'use client';

import { useEffect, useState, useRef, Suspense } from "react";
import { useSearchParams } from 'next/navigation';
import { getClientDetail } from '@/lib/supabase/getClientDetail'
import { useUserStore } from '@/store/userStore';
import { supabase } from '@/lib/supabase';
import { getClients } from '@/lib/supabase/getClients';
import { getMessages } from '@/lib/supabase/getMessages';
import type { RealtimeChannel } from '@supabase/supabase-js';
import type { Client } from '@/types/client'

function MessageContent() {
    type Message = {
        sender: string,
        content: string,
        timestamp: string,
        senderType: 'client' | 'trainer',
        receiverType: 'client' | 'trainer',
    }

    const searchParams = useSearchParams()
    const client_id = searchParams.get("clientId")
    const { userName } = useUserStore()
    const [userId, setUserId] = useState<string | null>(null);
    const [input, setInput] = useState('');
    const [clientList, setClientList] = useState<Client[]>([]);
    const [selectedClient, setSelectedClient] = useState<Client | null>(null);
    const [messages, setMessages] = useState<Message[]>([]);
    const [loading, setLoading] = useState(false);
    const messagesEndRef = useRef<HTMLDivElement>(null);

    // 最新のメッセージまでスクロールする関数
    const scrollToBottom = () => {
        messagesEndRef.current?.scrollIntoView({ behavior: 'smooth' });
    };

    // メッセージが更新されたら自動スクロール
    useEffect(() => {
        scrollToBottom();
    }, [messages]);

    const handleSend = async () => {
        if (!input.trim() || !userId || !selectedClient?.client_id) return;
        setLoading(true);
        try {
            const res = await fetch('/api/messages/send', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    trainerId: userId,
                    clientId: selectedClient.client_id,
                    content: input,
                }),
            });
            console.log('Response status:', res.status);
            const text = await res.text();
            console.log('Response text:', text);
            const data = text ? JSON.parse(text) : {};
            if (res.ok) {
                setMessages([...messages, {
                    sender: 'You',
                    content: input,
                    timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                    senderType: 'trainer',
                    receiverType: 'client',
                }]);
            } else {
                alert('送信に失敗しました' + data.error);
            }

            setLoading(false);
            setInput('');
        } catch (err) {
            console.error('送信エラー:', err);
            alert('送信に失敗しました');
        } finally {
            setLoading(false);
        }
    }

    // 顧客一覧の取得
    useEffect(() => {
        const fetchClients = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser()

            if (user) {
                setUserId(user.id);
                const clients = await getClients(user.id)
                console.log("user.id" + user.id)
                setClientList(clients as unknown as Client[])
            }
        }
        fetchClients();
    }, []);

    // 顧客情報の取得
    useEffect(() => {
        if (!client_id) return;
        const fetchClientInfo = async () => {
            try {
                const clientInfo = await getClientDetail(client_id)
                setSelectedClient(clientInfo as Client)
            } catch (error) {
                console.error('顧客情報取得エラー:', error);
            } finally {
                setLoading(false);
            }
        }
        fetchClientInfo();
    }, [client_id]);

    // メッセージ取得処理
    useEffect(() => {
        if (!selectedClient) return;

        let channel: RealtimeChannel | null = null;

        const fetchAndSubscribe = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser();

            if (!user) return;

            // ✅ 初期取得処理
            const rawMessages = await getMessages({
                senderId: user.id,
                receiverId: selectedClient.client_id,
            });
            console.log("rawMessages", rawMessages);

            // eslint-disable-next-line @typescript-eslint/no-explicit-any
            const formattedMessages: Message[] = rawMessages.map((msg: any) => ({
                sender: msg.sender_type === 'client' ? selectedClient.name : 'You',
                content: msg.content,
                timestamp: new Date(msg.created_at).toLocaleTimeString([], {
                    hour: '2-digit',
                    minute: '2-digit',
                }),
                senderType: msg.sender_type,
                receiverType: msg.receiver_type,
            }));
            console.log("formattedMessages", formattedMessages);

            setMessages(formattedMessages);

            // 既に存在する同名チャンネルを削除
            const existingChannel = supabase
                .getChannels()
                .find((c) => c.topic === "realtime:message-room");
            if (existingChannel) supabase.removeChannel(existingChannel)

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
                        if (msg.receiver_id !== user.id || msg.sender_id !== selectedClient.client_id) return;

                        const newMsg: Message = {
                            sender: selectedClient.name,
                            content: msg.content,
                            timestamp: new Date(msg.created_at).toLocaleTimeString([], {
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
                            className={`cursor-pointer p-2 rounded ${selectedClient?.client_id === client.client_id ? 'bg-blue-100' : ''
                                }`}
                            onClick={() => {
                                setSelectedClient(
                                    client as Client
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
                    <h1 className="text-lg font-semibold">{selectedClient?.name || ''}</h1>
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
                                <div className={`p-3 rounded border mt-1 max-w-md ${msg.senderType === 'trainer' ? 'bg-blue-100' : 'bg-white'}`}>
                                    {msg.content}
                                </div>
                            </div>
                        </div>
                    ))}
                    {/* スクロール位置の参照用要素 */}
                    <div ref={messagesEndRef} />
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
                            onClick={handleSend} disabled={loading}
                            className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {loading ? '送信中...' : '送信'}
                        </button>
                    </div>
                </footer>
            </div>
        </div>
    );
}

export default function MessagePage() {
    return (
        <Suspense fallback={<div className="flex items-center justify-center h-screen">Loading...</div>}>
            <MessageContent />
        </Suspense>
    );
}