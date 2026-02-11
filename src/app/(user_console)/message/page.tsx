// app/chat/page.tsx
'use client';

import { useEffect, useState, useRef, Suspense } from "react";
import { useSearchParams } from 'next/navigation';
import { getClientDetail } from '@/lib/supabase/getClientDetail'
import { useUserStore } from '@/store/userStore';
import { supabase } from '@/lib/supabase';
import { getClients } from '@/lib/supabase/getClients';
import { getMessages } from '@/lib/supabase/getMessages';
import { uploadMessageImage } from '@/lib/supabase/uploadMessageImage';
import { ImageUploader } from '@/components/message/ImageUploader';
import { ImageModal } from '@/components/message/ImageModal';
import { ReplyPreview } from '@/components/message/ReplyPreview';
import { ReplyQuote } from '@/components/message/ReplyQuote';
import { getMessageById } from '@/lib/supabase/getMessageById';
import type { RealtimeChannel } from '@supabase/supabase-js';
import type { Client, Message } from '@/types/client'

const EDIT_TIME_LIMIT_MINUTES = 5;

function canEditMessage(createdAt: string): boolean {
    const now = new Date();
    const created = new Date(createdAt);
    const diffMinutes = (now.getTime() - created.getTime()) / 1000 / 60;
    return diffMinutes <= EDIT_TIME_LIMIT_MINUTES;
}

function MessageContent() {
    const searchParams = useSearchParams()
    const client_id = searchParams.get("clientId")
    const { userName } = useUserStore()
    const [userId, setUserId] = useState<string | null>(null);
    const [input, setInput] = useState('');
    const [clientList, setClientList] = useState<Client[]>([]);
    const [selectedClient, setSelectedClient] = useState<Client | null>(null);
    const [messages, setMessages] = useState<Message[]>([]);
    const [loading, setLoading] = useState(false);
    const [selectedImages, setSelectedImages] = useState<File[]>([]);
    const [uploading, setUploading] = useState(false);
    const [selectedImageUrl, setSelectedImageUrl] = useState<string | null>(null);
    const [editingMessageId, setEditingMessageId] = useState<string | null>(null);
    const [editInput, setEditInput] = useState('');
    const [editSaving, setEditSaving] = useState(false);
    const [replyToMessage, setReplyToMessage] = useState<Message | null>(null);
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const editTextareaRef = useRef<HTMLTextAreaElement>(null);

    const handleSend = async () => {
        const hasText = input.trim().length > 0;
        const hasImages = selectedImages.length > 0;
        if ((!hasText && !hasImages) || !userId || !selectedClient?.client_id) return;

        setLoading(true);
        setUploading(hasImages);

        try {
            // 画像がある場合は並列アップロード
            let imageUrls: string[] = [];
            if (hasImages) {
                imageUrls = await Promise.all(
                    selectedImages.map((file) =>
                        uploadMessageImage(file, userId, selectedClient.client_id)
                    )
                );
            }

            const res = await fetch('/api/messages/send', {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json',
                },
                body: JSON.stringify({
                    trainerId: userId,
                    clientId: selectedClient.client_id,
                    content: input,
                    ...(imageUrls.length > 0 && { image_urls: imageUrls }),
                    ...(replyToMessage && { reply_to_message_id: replyToMessage.id }),
                }),
            });
            console.log('Response status:', res.status);
            const text = await res.text();
            console.log('Response text:', text);
            const data = text ? JSON.parse(text) : {};
            if (res.ok) {
                setMessages([...messages, {
                    id: data.id,
                    sender: 'You',
                    content: input,
                    timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                    created_at: data.created_at || new Date().toISOString(),
                    senderType: 'trainer',
                    receiverType: 'client',
                    image_urls: imageUrls,
                    is_edited: false,
                    edited_at: null,
                    reply_to_message_id: replyToMessage?.id || null,
                    reply_to_message: replyToMessage ? {
                        id: replyToMessage.id,
                        sender: replyToMessage.sender,
                        content: replyToMessage.content,
                        image_urls: replyToMessage.image_urls,
                    } : null,
                }]);
                setSelectedImages([]);
                setReplyToMessage(null);
            } else {
                alert('送信に失敗しました' + data.error);
            }

            setLoading(false);
            setUploading(false);
            setInput('');
            if (textareaRef.current) {
                textareaRef.current.style.height = 'auto';
            }
        } catch (err) {
            console.error('送信エラー:', err);
            alert('送信に失敗しました');
        } finally {
            setLoading(false);
            setUploading(false);
        }
    }

    const handleEditStart = (msg: Message) => {
        setEditingMessageId(msg.id);
        setEditInput(msg.content);
    };

    const handleEditCancel = () => {
        setEditingMessageId(null);
        setEditInput('');
    };

    const handleEditSave = async () => {
        if (!editingMessageId || editSaving) return;
        const trimmed = editInput.trim();
        if (!trimmed) return;

        setEditSaving(true);
        try {
            const res = await fetch('/api/messages/edit', {
                method: 'PUT',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    messageId: editingMessageId,
                    content: trimmed,
                }),
            });

            if (res.ok) {
                setMessages((prev) =>
                    prev.map((m) =>
                        m.id === editingMessageId
                            ? { ...m, content: trimmed, is_edited: true, edited_at: new Date().toISOString() }
                            : m
                    )
                );
                setEditingMessageId(null);
                setEditInput('');
            } else {
                const data = await res.json();
                alert(data.error || '編集に失敗しました');
            }
        } catch (err) {
            console.error('編集エラー:', err);
            alert('編集に失敗しました');
        } finally {
            setEditSaving(false);
        }
    };

    const handleReplyStart = (msg: Message) => {
        setReplyToMessage(msg);
        // 入力欄にフォーカス
        textareaRef.current?.focus();
    };

    const handleReplyCancel = () => {
        setReplyToMessage(null);
    };

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

            // 初期取得処理
            const rawMessages = await getMessages({
                senderId: user.id,
                receiverId: selectedClient.client_id,
            });
            console.log("rawMessages", rawMessages);

            const formattedMessages: Message[] = await Promise.all(
                // eslint-disable-next-line @typescript-eslint/no-explicit-any
                rawMessages.map(async (msg: any) => {
                    let replyToMessageData = null;
                    if (msg.reply_to_message_id) {
                        try {
                            const replyMsg = await getMessageById(msg.reply_to_message_id);
                            replyToMessageData = {
                                id: replyMsg.id,
                                sender: replyMsg.sender_type === 'client' ? selectedClient.name : 'You',
                                content: replyMsg.content,
                                image_urls: replyMsg.image_urls || [],
                            };
                        } catch (error) {
                            console.error('返信先メッセージ取得エラー:', error);
                        }
                    }

                    return {
                        id: msg.id,
                        sender: msg.sender_type === 'client' ? selectedClient.name : 'You',
                        content: msg.content,
                        timestamp: new Date(msg.created_at).toLocaleTimeString([], {
                            hour: '2-digit',
                            minute: '2-digit',
                        }),
                        created_at: msg.created_at,
                        senderType: msg.sender_type,
                        receiverType: msg.receiver_type,
                        image_urls: msg.image_urls || [],
                        is_edited: msg.is_edited || false,
                        edited_at: msg.edited_at || null,
                        reply_to_message_id: msg.reply_to_message_id || null,
                        reply_to_message: replyToMessageData,
                    };
                })
            );
            console.log("formattedMessages", formattedMessages);

            setMessages(formattedMessages);

            // 既に存在する同名チャンネルを削除
            const existingChannel = supabase
                .getChannels()
                .find((c) => c.topic === "realtime:message-room");
            if (existingChannel) supabase.removeChannel(existingChannel)

            // Realtime購読
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
                            id: msg.id,
                            sender: selectedClient.name,
                            content: msg.content,
                            timestamp: new Date(msg.created_at).toLocaleTimeString([], {
                                hour: '2-digit',
                                minute: '2-digit',
                            }),
                            created_at: msg.created_at,
                            senderType: msg.sender_type,
                            receiverType: msg.receiver_type,
                            image_urls: msg.image_urls || [],
                            is_edited: msg.is_edited || false,
                            edited_at: msg.edited_at || null,
                            reply_to_message_id: msg.reply_to_message_id || null,
                            reply_to_message: null,  // Realtime時は簡易対応
                        };
                        setMessages((prev) => [...prev, newMsg]);
                    }
                )
                .on(
                    'postgres_changes',
                    {
                        event: 'UPDATE',
                        schema: 'public',
                        table: 'messages',
                    },
                    (payload) => {
                        const msg = payload.new;

                        setMessages((prev) =>
                            prev.map((m) =>
                                m.id === msg.id
                                    ? {
                                        ...m,
                                        content: msg.content,
                                        is_edited: msg.is_edited || false,
                                        edited_at: msg.edited_at || null,
                                    }
                                    : m
                            )
                        );
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
                <main className="flex-1 overflow-y-auto p-6 flex flex-col-reverse gap-4">
                    {[...messages].reverse().map((msg, index) => (
                        <div key={index} className="flex items-start space-x-3">
                            <div className="w-10 h-10 bg-gray-300 rounded-full" />
                            <div className="flex-1 min-w-0">
                                <div className='text-sm font-medium'>
                                    {msg.sender}{' '}
                                    <span className='text-gray-500 text-xs ml-2'>{msg.timestamp}</span>
                                    {msg.is_edited && (
                                        <span
                                            className='text-gray-400 text-xs ml-2 cursor-default'
                                            title={msg.edited_at ? `編集: ${new Date(msg.edited_at).toLocaleString()}` : '編集済み'}
                                        >
                                            編集済み
                                        </span>
                                    )}
                                </div>
                                {editingMessageId === msg.id ? (
                                    <div className="mt-1 max-w-md">
                                        <textarea
                                            ref={editTextareaRef}
                                            value={editInput}
                                            onChange={(e) => setEditInput(e.target.value)}
                                            onKeyDown={(e) => {
                                                if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                                                    e.preventDefault();
                                                    handleEditSave();
                                                }
                                                if (e.key === 'Escape') {
                                                    handleEditCancel();
                                                }
                                            }}
                                            className="w-full border-2 border-blue-400 rounded p-3 outline-none focus:ring-2 focus:ring-blue-300 resize-none bg-white"
                                            rows={2}
                                            autoFocus
                                        />
                                        <div className="flex items-center gap-2 mt-1">
                                            <button
                                                type="button"
                                                onClick={handleEditCancel}
                                                className="px-3 py-1 text-sm text-gray-600 rounded hover:bg-gray-100"
                                            >
                                                キャンセル
                                            </button>
                                            <button
                                                type="button"
                                                onClick={handleEditSave}
                                                disabled={editSaving || !editInput.trim()}
                                                className="px-3 py-1 text-sm bg-blue-600 text-white rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                                            >
                                                {editSaving ? '保存中...' : '保存'}
                                            </button>
                                            <span className="text-xs text-gray-400">Enter で保存 / Esc でキャンセル</span>
                                        </div>
                                    </div>
                                ) : (
                                    <div className="group relative inline-block max-w-md">
                                        <div className={`p-3 rounded border mt-1 whitespace-pre-wrap ${msg.senderType === 'trainer' ? 'bg-blue-100' : 'bg-white'}`}>
                                            {msg.reply_to_message && (
                                                <ReplyQuote
                                                    senderName={msg.reply_to_message.sender}
                                                    content={msg.reply_to_message.content}
                                                    isTrainerMessage={msg.senderType === 'trainer'}
                                                />
                                            )}
                                            {msg.content}
                                            {msg.image_urls && msg.image_urls.length > 0 && (
                                                <div className="flex gap-2 mt-2">
                                                    {msg.image_urls.map((url, imgIndex) => (
                                                        <button
                                                            key={imgIndex}
                                                            type="button"
                                                            onClick={() => setSelectedImageUrl(url)}
                                                            className="block"
                                                        >
                                                            <img
                                                                src={url}
                                                                alt={`添付画像 ${imgIndex + 1}`}
                                                                className="w-24 h-24 object-cover rounded cursor-pointer hover:opacity-80 transition-opacity"
                                                            />
                                                        </button>
                                                    ))}
                                                </div>
                                            )}
                                        </div>
                                        {msg.senderType === 'trainer' && canEditMessage(msg.created_at) && (
                                            <button
                                                type="button"
                                                onClick={() => handleEditStart(msg)}
                                                className="absolute -right-8 top-1 opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-gray-200"
                                                title="メッセージを編集"
                                            >
                                                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-500">
                                                    <path d="M17 3a2.85 2.83 0 1 1 4 4L7.5 20.5 2 22l1.5-5.5Z" />
                                                    <path d="m15 5 4 4" />
                                                </svg>
                                            </button>
                                        )}
                                        {/* 返信ボタン - クライアントメッセージのみ表示 */}
                                        {msg.senderType === 'client' && (
                                            <button
                                                type="button"
                                                onClick={() => handleReplyStart(msg)}
                                                className="absolute -right-8 top-1 opacity-0 group-hover:opacity-100 transition-opacity p-1 rounded hover:bg-gray-200"
                                                title="返信"
                                            >
                                                <svg xmlns="http://www.w3.org/2000/svg" width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" className="text-gray-500">
                                                    <polyline points="9 14 4 9 9 4"></polyline>
                                                    <path d="M20 20v-7a4 4 0 0 0-4-4H4"></path>
                                                </svg>
                                            </button>
                                        )}
                                    </div>
                                )}
                            </div>
                        </div>
                    ))}
                </main>

                {/* Input */}
                <footer className="border-t p-4 bg-white">
                    <ImageUploader
                        images={selectedImages}
                        onImagesChange={setSelectedImages}
                        disabled={loading}
                    />
                    {/* 返信プレビュー */}
                    {replyToMessage && (
                        <ReplyPreview
                            senderName={replyToMessage.sender}
                            content={replyToMessage.content}
                            imageUrls={replyToMessage.image_urls}
                            onCancel={handleReplyCancel}
                        />
                    )}
                    <div className="flex items-center space-x-3 mt-2">
                        <textarea
                            ref={textareaRef}
                            value={input}
                            onChange={(e) => {
                                setInput(e.target.value);
                                const el = textareaRef.current;
                                if (el) {
                                    el.style.height = 'auto';
                                    el.style.height = `${el.scrollHeight}px`;
                                }
                            }}
                            onKeyDown={(e) => {
                                if (e.key === 'Enter' && !e.shiftKey && !e.nativeEvent.isComposing) {
                                    e.preventDefault();
                                    handleSend();
                                }
                            }}
                            placeholder="Send a message..."
                            rows={1}
                            className="flex-1 border rounded px-3 py-2 outline-none focus:ring-2 focus:ring-blue-300 resize-none overflow-y-auto"
                            style={{ maxHeight: '120px' }}
                        />
                        <button
                            onClick={handleSend} disabled={loading}
                            className="bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed"
                        >
                            {uploading ? 'アップロード中...' : loading ? '送信中...' : '送信'}
                        </button>
                    </div>
                </footer>
            </div>

            {/* 画像拡大モーダル */}
            <ImageModal
                imageUrl={selectedImageUrl}
                onClose={() => setSelectedImageUrl(null)}
            />
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
