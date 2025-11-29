'use client';

import { useEffect, useState } from 'react';
import { useForm } from 'react-hook-form';
import { zodResolver } from '@hookform/resolvers/zod';
import * as z from 'zod';
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog';
import { Button } from '@/components/ui/button';
import { Input } from '@/components/ui/input';
import { Label } from '@/components/ui/label';
import { Textarea } from '@/components/ui/textarea';
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select';
import { getClients } from '@/lib/supabase/getClients';
import { createSession } from '@/lib/supabase/createSession';
import { updateSession } from '@/lib/supabase/updateSession';
import { deleteSession } from '@/lib/supabase/deleteSession';
import { getTickets } from '@/lib/supabase/getTickets';
import { updateTicket } from '@/lib/supabase/updateTicket';
import { Session } from '@/lib/supabase/getSessions';
import { supabase } from '@/lib/supabase';
import { Ticket } from '@/types/client';
import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
    AlertDialogTrigger,
} from "@/components/ui/alert-dialog"

const sessionSchema = z.object({
    client_id: z.string().min(1, '顧客を選択してください'),
    session_date: z.string().min(1, '日付を入力してください'),
    session_time: z.string().min(1, '時間を入力してください'),
    duration_minutes: z.number().min(1, '時間を入力してください'),
    session_type: z.string().optional(),
    memo: z.string().optional(),
    status: z.enum(['scheduled', 'confirmed', 'completed', 'cancelled']),
    ticket_id: z.string().optional(),
});

type SessionFormValues = z.infer<typeof sessionSchema>;

interface SessionModalProps {
    isOpen: boolean;
    onClose: () => void;
    selectedDate?: Date;
    session?: Session | null;
    onSuccess: () => void;
}

export default function SessionModal({ isOpen, onClose, selectedDate, session, onSuccess }: SessionModalProps) {
    const [userId, setUserId] = useState<string | null>(null);
    const [clients, setClients] = useState<{ client_id: string; name: string }[]>([]);
    const [tickets, setTickets] = useState<Ticket[]>([]);
    const [isLoading, setIsLoading] = useState(false);

    const { register, handleSubmit, setValue, reset, watch, formState: { errors } } = useForm<SessionFormValues>({
        resolver: zodResolver(sessionSchema),
        defaultValues: {
            duration_minutes: 60,
            status: 'scheduled',
        },
    });

    const selectedClientId = watch('client_id');

    useEffect(() => {
        const fetchUser = async () => {
            const { data: { user } } = await supabase.auth.getUser();
            if (user) {
                setUserId(user.id);
            }
        };
        fetchUser();
    }, []);

    useEffect(() => {
        const fetchClients = async () => {
            if (!userId) return;
            try {
                const data = await getClients(userId);
                setClients(data);
            } catch (error) {
                console.error('Failed to fetch clients', error);
            }
        };
        fetchClients();
    }, [userId]);

    // 顧客が選択されたらチケットを取得
    useEffect(() => {
        const fetchClientTickets = async () => {
            if (!selectedClientId) {
                setTickets([]);
                return;
            }
            try {
                const data = await getTickets(selectedClientId);
                // 有効期限内かつ残回数があるチケット、または現在選択されているチケットを表示
                const validTickets = data.filter(t =>
                    (t.remaining_sessions > 0 && new Date(t.valid_until) >= new Date()) ||
                    t.id === session?.ticket_id
                );
                setTickets(validTickets);
            } catch (error) {
                console.error('Failed to fetch tickets', error);
            }
        };
        fetchClientTickets();
    }, [selectedClientId, session?.ticket_id]);

    useEffect(() => {
        if (isOpen) {
            if (session) {
                const date = new Date(session.session_date);
                setValue('client_id', session.client_id);
                setValue('session_date', date.toISOString().split('T')[0]);
                setValue('session_time', date.toTimeString().slice(0, 5));
                setValue('duration_minutes', session.duration_minutes);
                setValue('session_type', session.session_type || '');
                setValue('memo', session.memo || '');
                setValue('status', session.status);
                setValue('ticket_id', session.ticket_id || undefined);
            } else if (selectedDate) {
                reset({
                    duration_minutes: 60,
                    status: 'scheduled',
                    session_date: selectedDate.toISOString().split('T')[0],
                    session_time: '10:00',
                });
            }
        }
    }, [isOpen, session, selectedDate, setValue, reset]);

    const onSubmit = async (data: SessionFormValues) => {
        if (!userId) return;
        setIsLoading(true);
        try {
            const dateTime = new Date(`${data.session_date}T${data.session_time}`);

            // チケット消化ロジック
            // ステータスが「完了」になり、かつ以前は「完了」でなかった場合（新規作成含む）
            if (data.status === 'completed' && data.ticket_id) {
                const shouldConsume = !session || session.status !== 'completed';
                if (shouldConsume) {
                    const ticket = tickets.find(t => t.id === data.ticket_id);
                    if (ticket && ticket.remaining_sessions > 0) {
                        await updateTicket({
                            id: ticket.id,
                            remaining_sessions: ticket.remaining_sessions - 1
                        });
                    }
                }
            }

            if (session) {
                await updateSession({
                    id: session.id,
                    session_date: dateTime,
                    duration_minutes: data.duration_minutes,
                    status: data.status,
                    session_type: data.session_type,
                    memo: data.memo,
                    ticket_id: data.ticket_id,
                });
            } else {
                await createSession({
                    trainer_id: userId,
                    client_id: data.client_id,
                    session_date: dateTime,
                    duration_minutes: data.duration_minutes,
                    status: data.status,
                    session_type: data.session_type,
                    memo: data.memo,
                    ticket_id: data.ticket_id,
                });
            }
            onSuccess();
            onClose();
        } catch (error) {
            console.error('Failed to save session', error);
        } finally {
            setIsLoading(false);
        }
    };

    const handleDelete = async () => {
        if (!session) return;
        try {
            await deleteSession(session.id);
            onSuccess();
            onClose();
        } catch (error) {
            console.error('Failed to delete session', error);
            alert('削除に失敗しました');
        }
    };

    return (
        <Dialog open={isOpen} onOpenChange={onClose}>
            <DialogContent className="sm:max-w-[425px]">
                <DialogHeader>
                    <DialogTitle>{session ? 'セッション編集' : 'セッション予約'}</DialogTitle>
                </DialogHeader>
                <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
                    <div className="space-y-2">
                        <Label htmlFor="client">顧客</Label>
                        <Select
                            onValueChange={(value) => setValue('client_id', value)}
                            defaultValue={session?.client_id}
                            disabled={!!session} // 編集時は顧客変更不可（簡易実装）
                        >
                            <SelectTrigger>
                                <SelectValue placeholder="顧客を選択" />
                            </SelectTrigger>
                            <SelectContent>
                                {clients.map((client) => (
                                    <SelectItem key={client.client_id} value={client.client_id}>
                                        {client.name}
                                    </SelectItem>
                                ))}
                            </SelectContent>
                        </Select>
                        {errors.client_id && <p className="text-sm text-red-500">{errors.client_id.message}</p>}
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="ticket">使用チケット</Label>
                        <Select
                            onValueChange={(value) => setValue('ticket_id', value === 'none' ? undefined : value)}
                            defaultValue={session?.ticket_id || undefined}
                            disabled={!selectedClientId}
                        >
                            <SelectTrigger>
                                <SelectValue placeholder="チケットを選択（任意）" />
                            </SelectTrigger>
                            <SelectContent>
                                <SelectItem value="none">使用しない</SelectItem>
                                {tickets.map((ticket) => (
                                    <SelectItem key={ticket.id} value={ticket.id}>
                                        {ticket.ticket_name} (残: {ticket.remaining_sessions}回)
                                    </SelectItem>
                                ))}
                            </SelectContent>
                        </Select>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                            <Label htmlFor="date">日付</Label>
                            <Input type="date" {...register('session_date')} />
                            {errors.session_date && <p className="text-sm text-red-500">{errors.session_date.message}</p>}
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="time">時間</Label>
                            <Input type="time" {...register('session_time')} />
                            {errors.session_time && <p className="text-sm text-red-500">{errors.session_time.message}</p>}
                        </div>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                            <Label htmlFor="duration">所要時間 (分)</Label>
                            <Input
                                type="number"
                                {...register('duration_minutes', { valueAsNumber: true })}
                            />
                            {errors.duration_minutes && <p className="text-sm text-red-500">{errors.duration_minutes.message}</p>}
                        </div>
                        <div className="space-y-2">
                            <Label htmlFor="status">ステータス</Label>
                            <Select
                                onValueChange={(value: 'scheduled' | 'confirmed' | 'completed' | 'cancelled') => setValue('status', value)}
                                defaultValue={session?.status || 'scheduled'}
                            >
                                <SelectTrigger>
                                    <SelectValue />
                                </SelectTrigger>
                                <SelectContent>
                                    <SelectItem value="scheduled">予定</SelectItem>
                                    <SelectItem value="confirmed">確定</SelectItem>
                                    <SelectItem value="completed">完了</SelectItem>
                                    <SelectItem value="cancelled">キャンセル</SelectItem>
                                </SelectContent>
                            </Select>
                        </div>
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="type">セッション種別</Label>
                        <Input {...register('session_type')} placeholder="例: パーソナルトレーニング" />
                    </div>

                    <div className="space-y-2">
                        <Label htmlFor="memo">メモ</Label>
                        <Textarea {...register('memo')} placeholder="メモを入力" />
                    </div>

                    <DialogFooter>
                        <div className="flex justify-between space-x-2 pt-4 w-full">
                            {session ? (
                                <AlertDialog>
                                    <AlertDialogTrigger asChild>
                                        <Button type="button" variant="destructive" disabled={isLoading}>
                                            削除
                                        </Button>
                                    </AlertDialogTrigger>
                                    <AlertDialogContent>
                                        <AlertDialogHeader>
                                            <AlertDialogTitle>本当に削除しますか？</AlertDialogTitle>
                                            <AlertDialogDescription>
                                                この操作は取り消せません。
                                            </AlertDialogDescription>
                                        </AlertDialogHeader>
                                        <AlertDialogFooter>
                                            <AlertDialogCancel>キャンセル</AlertDialogCancel>
                                            <AlertDialogAction onClick={handleDelete} disabled={isLoading}>削除</AlertDialogAction>
                                        </AlertDialogFooter>
                                    </AlertDialogContent>
                                </AlertDialog>
                            ) : (
                                <div></div>
                            )}
                            <div className="flex gap-2">
                                <Button type="button" variant="outline" onClick={onClose} disabled={isLoading}>
                                    キャンセル
                                </Button>
                                <Button type="submit" disabled={isLoading}>
                                    {isLoading ? '保存中...' : '保存'}
                                </Button>
                            </div>
                        </div>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    );
}
