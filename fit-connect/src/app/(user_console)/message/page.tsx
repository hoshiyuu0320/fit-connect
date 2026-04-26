// app/chat/page.tsx
'use client';

import { useEffect, useState, useRef, Suspense } from "react";
import { useSearchParams } from 'next/navigation';
import { getClientDetail } from '@/lib/supabase/getClientDetail'

import { supabase } from '@/lib/supabase';
import { getClients } from '@/lib/supabase/getClients';
import { getMessages } from '@/lib/supabase/getMessages';
import { uploadMessageImage } from '@/lib/supabase/uploadMessageImage';
import { getUnreadCounts } from '@/lib/supabase/getUnreadCounts';
import { markMessagesAsRead } from '@/lib/supabase/markMessagesAsRead';
import { getLastMessagesForClients } from '@/lib/supabase/getLastMessagesForClients';
import { ImageUploader } from '@/components/message/ImageUploader';
import { ImageModal } from '@/components/message/ImageModal';
import { ReplyPreview } from '@/components/message/ReplyPreview';
import { MessageBubble } from '@/components/message/MessageBubble';
import { ClientListItem } from '@/components/message/ClientListItem';
import { ChatHeader } from '@/components/message/ChatHeader';
import { MessageDateDivider } from '@/components/message/MessageDateDivider';
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

interface LastMessageInfo {
    content: string;
    created_at: string;
}

function MessageContent() {
    const searchParams = useSearchParams()
    const client_id = searchParams.get("clientId")
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
    const [unreadCounts, setUnreadCounts] = useState<Map<string, number>>(new Map());
    const [lastMessages, setLastMessages] = useState<Map<string, LastMessageInfo>>(new Map());
    const textareaRef = useRef<HTMLTextAreaElement>(null);
    const selectedClientRef = useRef<Client | null>(null);

    // Keep ref in sync with state for use inside Realtime callbacks
    useEffect(() => {
        selectedClientRef.current = selectedClient;
    }, [selectedClient]);

    const handleSend = async () => {
        const hasText = input.trim().length > 0;
        const hasImages = selectedImages.length > 0;
        if ((!hasText && !hasImages) || !userId || !selectedClient?.client_id) return;

        setLoading(true);
        setUploading(hasImages);

        try {
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
            const text = await res.text();
            const data = text ? JSON.parse(text) : {};
            if (res.ok) {
                const newCreatedAt = data.created_at || new Date().toISOString();
                const newMsg: Message = {
                    id: data.id,
                    sender: 'You',
                    content: input,
                    timestamp: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' }),
                    created_at: newCreatedAt,
                    senderType: 'trainer',
                    receiverType: 'client',
                    image_urls: imageUrls,
                    is_edited: false,
                    edited_at: null,
                    read_at: null,
                    reply_to_message_id: replyToMessage?.id || null,
                    reply_to_message: replyToMessage ? {
                        id: replyToMessage.id,
                        sender: replyToMessage.sender,
                        content: replyToMessage.content,
                        image_urls: replyToMessage.image_urls,
                    } : null,
                };
                setMessages((prev) => [...prev, newMsg]);
                // Update last message for sidebar
                setLastMessages((prev) => {
                    const next = new Map(prev);
                    next.set(selectedClient.client_id, {
                        content: input || (imageUrls.length > 0 ? '画像' : ''),
                        created_at: newCreatedAt,
                    });
                    return next;
                });
                setSelectedImages([]);
                setReplyToMessage(null);
            } else {
                alert('送信に失敗しました' + data.error);
            }

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
        textareaRef.current?.focus();
    };

    const handleReplyCancel = () => {
        setReplyToMessage(null);
    };

    // 顧客一覧の取得 + 未読カウント取得
    useEffect(() => {
        const fetchClients = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser()

            if (user) {
                setUserId(user.id);
                const clients = await getClients(user.id)
                setClientList(clients as unknown as Client[])

                // 未読カウント + 最終メッセージ取得
                const [counts, lastMsgs] = await Promise.all([
                    getUnreadCounts(user.id),
                    getLastMessagesForClients(user.id),
                ]);
                setUnreadCounts(counts);
                setLastMessages(lastMsgs);
            }
        }
        fetchClients();
    }, []);

    // URLパラメータによるクライアント自動選択
    useEffect(() => {
        if (!client_id) return;
        const fetchClientInfo = async () => {
            try {
                const clientInfo = await getClientDetail(client_id)
                setSelectedClient(clientInfo as Client)
            } catch (error) {
                console.error('顧客情報取得エラー:', error);
            }
        }
        fetchClientInfo();
    }, [client_id]);

    // 既読マーク: クライアント選択時
    useEffect(() => {
        if (!selectedClient || !userId) return;
        markMessagesAsRead(userId, selectedClient.client_id);
        // 未読カウントをリセット
        setUnreadCounts((prev) => {
            const next = new Map(prev);
            next.set(selectedClient.client_id, 0);
            return next;
        });
    }, [selectedClient, userId]);

    // メッセージ取得 + Realtime購読
    useEffect(() => {
        if (!selectedClient) return;

        let channel: RealtimeChannel | null = null;

        const fetchAndSubscribe = async () => {
            const {
                data: { user },
            } = await supabase.auth.getUser();

            if (!user) return;

            const rawMessages = await getMessages({
                senderId: user.id,
                receiverId: selectedClient.client_id,
            });

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
                        read_at: msg.read_at || null,
                        reply_to_message_id: msg.reply_to_message_id || null,
                        reply_to_message: replyToMessageData,
                    };
                })
            );

            setMessages(formattedMessages);

            // Update last message for this client in sidebar
            if (formattedMessages.length > 0) {
                const last = formattedMessages[formattedMessages.length - 1];
                setLastMessages((prev) => {
                    const next = new Map(prev);
                    next.set(selectedClient.client_id, {
                        content: last.content || (last.image_urls && last.image_urls.length > 0 ? '画像' : ''),
                        created_at: last.created_at,
                    });
                    return next;
                });
            }

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
                        const currentSelected = selectedClientRef.current;

                        // Update last message for sidebar
                        setLastMessages((prev) => {
                            const next = new Map(prev);
                            next.set(msg.sender_id, {
                                content: msg.content || (msg.image_urls?.length > 0 ? '画像' : ''),
                                created_at: msg.created_at,
                            });
                            return next;
                        });

                        // 現在選択中のクライアントからのメッセージ
                        if (currentSelected && msg.sender_id === currentSelected.client_id) {
                            const newMsg: Message = {
                                id: msg.id,
                                sender: currentSelected.name,
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
                                read_at: msg.read_at || null,
                                reply_to_message_id: msg.reply_to_message_id || null,
                                reply_to_message: null,
                            };
                            setMessages((prev) => [...prev, newMsg]);
                            // 即既読
                            if (user) {
                                markMessagesAsRead(user.id, currentSelected.client_id);
                            }
                            // 未読カウント増やさない
                        } else {
                            // 別クライアントからのメッセージ → 未読カウント+1
                            setUnreadCounts((prev) => {
                                const next = new Map(prev);
                                const current = next.get(msg.sender_id) || 0;
                                next.set(msg.sender_id, current + 1);
                                return next;
                            });
                        }
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
                                        read_at: msg.read_at || null,
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

    // Build reversed array for flex-col-reverse rendering
    const reversedMessages = [...messages].reverse();

    return (
        <div className="flex h-[calc(100vh-48px)] bg-[#F8FAFC] text-[#0F172A] overflow-hidden">

            {/* Sidebar */}
            <aside className="w-72 bg-white border-r border-[#E2E8F0] flex flex-col">
                <div className="px-4 py-4 border-b border-[#E2E8F0]">
                    <h2 className="text-base font-semibold text-[#0F172A]">メッセージ</h2>
                </div>
                <div className="flex-1 overflow-y-auto">
                    {clientList.map((client) => {
                        const lastInfo = lastMessages.get(client.client_id);
                        return (
                            <ClientListItem
                                key={client.client_id}
                                client={client}
                                isSelected={selectedClient?.client_id === client.client_id}
                                unreadCount={unreadCounts.get(client.client_id) || 0}
                                lastMessage={lastInfo?.content}
                                lastMessageAt={lastInfo?.created_at}
                                onClick={() => setSelectedClient(client as Client)}
                            />
                        );
                    })}
                </div>
            </aside>

            {/* Chat Area */}
            <div className="flex flex-col flex-1 overflow-hidden">
                {/* Header */}
                <ChatHeader
                    client={selectedClient ? {
                        client_id: selectedClient.client_id,
                        name: selectedClient.name,
                        profile_image_url: selectedClient.profile_image_url,
                        purpose: selectedClient.purpose,
                        gender: selectedClient.gender,
                        age: selectedClient.age,
                    } : null}
                />

                {/* Messages */}
                <main className="flex-1 overflow-y-auto p-4 flex flex-col-reverse gap-1">
                    {reversedMessages.map((msg, index) => {
                        const currentDate = new Date(msg.created_at).toDateString();
                        const prevDate = index < reversedMessages.length - 1
                            ? new Date(reversedMessages[index + 1].created_at).toDateString()
                            : null;
                        const showDateDivider = currentDate !== prevDate;

                        return (
                            <div key={msg.id}>
                                <MessageBubble
                                    message={msg}
                                    isTrainer={msg.senderType === 'trainer'}
                                    clientId={selectedClient?.client_id || ''}
                                    clientName={selectedClient?.name || ''}
                                    clientProfileImageUrl={selectedClient?.profile_image_url || null}
                                    onEditStart={handleEditStart}
                                    onReplyStart={handleReplyStart}
                                    canEdit={msg.senderType === 'trainer' && canEditMessage(msg.created_at)}
                                    isEditing={editingMessageId === msg.id}
                                    editInput={editInput}
                                    onEditInputChange={setEditInput}
                                    onEditSave={handleEditSave}
                                    onEditCancel={handleEditCancel}
                                    editSaving={editSaving}
                                    onImageClick={setSelectedImageUrl}
                                />
                                {showDateDivider && (
                                    <MessageDateDivider date={msg.created_at} />
                                )}
                            </div>
                        );
                    })}
                </main>

                {/* Input */}
                <footer className="border-t border-[#E2E8F0] p-4 bg-white">
                    <ImageUploader
                        images={selectedImages}
                        onImagesChange={setSelectedImages}
                        disabled={loading}
                    />
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
                            placeholder="メッセージを入力..."
                            rows={1}
                            className="flex-1 border border-[#E2E8F0] rounded-md px-3 py-2 outline-none focus:border-[#14B8A6] resize-none overflow-y-auto text-[#0F172A] placeholder:text-[#94A3B8] bg-white"
                            style={{ maxHeight: '120px' }}
                        />
                        <button
                            onClick={handleSend}
                            disabled={loading}
                            className="bg-[#14B8A6] hover:bg-[#0D9488] text-white px-4 py-2 rounded-md disabled:bg-[#E2E8F0] disabled:text-[#94A3B8] disabled:cursor-not-allowed transition-colors"
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
        <Suspense fallback={<div className="flex items-center justify-center h-screen text-[#94A3B8]">Loading...</div>}>
            <MessageContent />
        </Suspense>
    );
}
