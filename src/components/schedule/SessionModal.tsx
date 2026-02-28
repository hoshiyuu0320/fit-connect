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
import { SESSION_TYPE_OPTIONS } from '@/types/session';
import { getSessionWorkoutPlans, SessionWorkoutPlan } from '@/lib/supabase/getSessionWorkoutPlans';
import {
    AlertDialog,
    AlertDialogAction,
    AlertDialogCancel,
    AlertDialogContent,
    AlertDialogDescription,
    AlertDialogFooter,
    AlertDialogHeader,
    AlertDialogTitle,
} from "@/components/ui/alert-dialog"
import RecurrenceDeleteDialog from './RecurrenceDeleteDialog';
import { createRecurringSessions } from '@/lib/supabase/createRecurringSessions';
import { deleteRecurringSessionsFromDate } from '@/lib/supabase/deleteRecurringSessionsFromDate';

const sessionSchema = z.object({
    client_id: z.string({ required_error: '必須項目です' }).min(1, '顧客を選択してください'),
    session_date: z.string({ required_error: '必須項目です' }).min(1, '日付を入力してください'),
    session_time: z.string({ required_error: '必須項目です' }).min(1, '時間を入力してください'),
    duration_minutes: z.number({ required_error: '必須項目です' }).min(1, '時間を入力してください'),
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
    const [workoutPlans, setWorkoutPlans] = useState<SessionWorkoutPlan[]>([]);
    const [selectedPlanId, setSelectedPlanId] = useState<string | null>(null);
    const [customSessionType, setCustomSessionType] = useState('');

    // 繰り返し設定のstate
    const [isRecurring, setIsRecurring] = useState(false);
    const [recurrencePattern, setRecurrencePattern] = useState<'weekly' | 'biweekly' | 'monthly'>('weekly');
    const [recurrenceEndType, setRecurrenceEndType] = useState<'date' | 'count'>('count');
    const [recurrenceEndDate, setRecurrenceEndDate] = useState('');
    const [recurrenceCount, setRecurrenceCount] = useState(8);

    // 削除ダイアログのstate
    const [isDeleteConfirmOpen, setIsDeleteConfirmOpen] = useState(false);
    const [isRecurrenceDeleteOpen, setIsRecurrenceDeleteOpen] = useState(false);

    const { register, handleSubmit, setValue, reset, watch, formState: { errors } } = useForm<SessionFormValues>({
        resolver: zodResolver(sessionSchema),
        defaultValues: {
            duration_minutes: 60,
            status: 'scheduled',
        },
    });

    const selectedClientId = watch('client_id');
    const selectedSessionType = watch('session_type');
    const isTrainingType = selectedSessionType === 'パーソナルトレーニング' || selectedSessionType === '有酸素トレーニング';

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

    useEffect(() => {
        const fetchWorkoutPlans = async () => {
            try {
                const data = await getSessionWorkoutPlans();
                setWorkoutPlans(data);
            } catch (error) {
                console.error('Failed to fetch workout plans', error);
            }
        };
        fetchWorkoutPlans();
    }, []);

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

                // session_type の初期値: SESSION_TYPE_OPTIONS に含まれない値は 'other' として扱う
                const knownValues = SESSION_TYPE_OPTIONS.map(o => o.value);
                const sessionTypeValue = session.session_type || '';
                if (sessionTypeValue && !knownValues.includes(sessionTypeValue as typeof SESSION_TYPE_OPTIONS[number]['value'])) {
                    setValue('session_type', 'other');
                    setCustomSessionType(sessionTypeValue);
                } else {
                    setValue('session_type', sessionTypeValue);
                    setCustomSessionType('');
                }

                setValue('memo', session.memo || '');
                setValue('status', session.status);
                setValue('ticket_id', session.ticket_id || undefined);

                // workout_assignments から初期プランを設定
                const planId = session.workout_assignments?.[0]?.plan?.id ?? null;
                setSelectedPlanId(planId);
            } else if (selectedDate) {
                // Format date in local timezone to avoid UTC conversion issues
                const year = selectedDate.getFullYear();
                const month = String(selectedDate.getMonth() + 1).padStart(2, '0');
                const day = String(selectedDate.getDate()).padStart(2, '0');
                const localDateString = `${year}-${month}-${day}`;

                const hours = String(selectedDate.getHours()).padStart(2, '0');
                const minutes = String(selectedDate.getMinutes()).padStart(2, '0');
                const localTimeString = `${hours}:${minutes}`;

                reset({
                    duration_minutes: 60,
                    status: 'scheduled',
                    session_date: localDateString,
                    session_time: localTimeString,
                });
            }
            // モーダルを開くたびに繰り返し設定をリセット
            setIsRecurring(false);
            setRecurrencePattern('weekly');
            setRecurrenceEndType('count');
            setRecurrenceEndDate('');
            setRecurrenceCount(8);
            if (!session) {
                setSelectedPlanId(null);
                setCustomSessionType('');
            }
        }
    }, [isOpen, session, selectedDate, setValue, reset]);

    const onSubmit = async (data: SessionFormValues) => {
        if (!userId) return;
        setIsLoading(true);
        try {
            const dateTime = new Date(`${data.session_date}T${data.session_time}`);

            // 'other' の場合はカスタムテキストを session_type として保存
            const resolvedSessionType = data.session_type === 'other' ? customSessionType : data.session_type;

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
                    session_type: resolvedSessionType,
                    memo: data.memo,
                    ticket_id: data.ticket_id,
                });
            } else if (isRecurring) {
                await createRecurringSessions({
                    trainer_id: userId,
                    client_id: data.client_id,
                    base_date: dateTime,
                    duration_minutes: data.duration_minutes,
                    pattern: recurrencePattern,
                    end_type: recurrenceEndType,
                    end_date: recurrenceEndType === 'date' ? new Date(recurrenceEndDate) : undefined,
                    count: recurrenceEndType === 'count' ? recurrenceCount : undefined,
                    status: data.status,
                    session_type: resolvedSessionType,
                    memo: data.memo,
                    ticket_id: data.ticket_id,
                });
            } else {
                const createdSession = await createSession({
                    trainer_id: userId,
                    client_id: data.client_id,
                    session_date: dateTime,
                    duration_minutes: data.duration_minutes,
                    status: data.status,
                    session_type: resolvedSessionType,
                    memo: data.memo,
                    ticket_id: data.ticket_id,
                });

                // ワークアウトプランが選択されている場合はアサインメントを作成
                if (selectedPlanId && createdSession?.id) {
                    await fetch('/api/workout-assignments', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            trainerId: userId,
                            clientId: data.client_id,
                            planId: selectedPlanId,
                            assignedDate: dateTime.toISOString(),
                            sessionId: createdSession.id,
                        }),
                    });
                }
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

    const handleDeleteSingle = async () => {
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

    const handleDeleteFromDate = async () => {
        if (!session?.recurrence_group_id) return;
        try {
            await deleteRecurringSessionsFromDate(
                session.recurrence_group_id,
                session.session_date
            );
            onSuccess();
            onClose();
        } catch (error) {
            console.error('Failed to delete recurring sessions', error);
            alert('削除に失敗しました');
        }
    };

    return (
        <>
            <Dialog open={isOpen} onOpenChange={onClose}>
                <DialogContent className="sm:max-w-[425px] bg-white">
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
                                <SelectContent className="bg-white">
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
                                <SelectContent className="bg-white">
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
                                    <SelectContent className="bg-white">
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
                            <Select
                                onValueChange={(value) => {
                                    setValue('session_type', value);
                                    if (value !== 'other') setCustomSessionType('');
                                    if (value !== 'パーソナルトレーニング' && value !== '有酸素トレーニング') {
                                        setSelectedPlanId(null);
                                    }
                                }}
                                value={selectedSessionType || ''}
                            >
                                <SelectTrigger>
                                    <SelectValue placeholder="種別を選択" />
                                </SelectTrigger>
                                <SelectContent className="bg-white">
                                    {SESSION_TYPE_OPTIONS.map((option) => (
                                        <SelectItem key={option.value} value={option.value}>
                                            {option.label}
                                        </SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                            {selectedSessionType === 'other' && (
                                <Input
                                    value={customSessionType}
                                    onChange={(e) => setCustomSessionType(e.target.value)}
                                    placeholder="種別を入力"
                                />
                            )}
                        </div>

                        {isTrainingType && workoutPlans.length > 0 && (
                            <div className="space-y-2">
                                <Label>ワークアウトプラン（任意）</Label>
                                <Select
                                    onValueChange={(value) => {
                                        const planId = value === 'none' ? null : value;
                                        setSelectedPlanId(planId);
                                        if (planId) {
                                            const plan = workoutPlans.find(p => p.id === planId);
                                            if (plan?.estimated_minutes) {
                                                setValue('duration_minutes', plan.estimated_minutes);
                                            }
                                        }
                                    }}
                                    value={selectedPlanId ?? 'none'}
                                >
                                    <SelectTrigger>
                                        <SelectValue placeholder="プランを選択（任意）" />
                                    </SelectTrigger>
                                    <SelectContent className="bg-white">
                                        <SelectItem value="none">プランなし</SelectItem>
                                        {workoutPlans.map((plan) => (
                                            <SelectItem key={plan.id} value={plan.id}>
                                                {plan.title}
                                                {plan.estimated_minutes ? ` (${plan.estimated_minutes}分)` : ''}
                                            </SelectItem>
                                        ))}
                                    </SelectContent>
                                </Select>
                            </div>
                        )}

                        {/* 繰り返し設定（新規作成時のみ） */}
                        {!session && (
                            <div className="space-y-3 rounded-md border border-gray-200 p-3">
                                <div className="flex items-center gap-2">
                                    <input
                                        type="checkbox"
                                        id="isRecurring"
                                        checked={isRecurring}
                                        onChange={(e) => setIsRecurring(e.target.checked)}
                                        className="h-4 w-4 rounded border-gray-300"
                                    />
                                    <Label htmlFor="isRecurring" className="cursor-pointer font-medium">
                                        繰り返し設定
                                    </Label>
                                </div>

                                {isRecurring && (
                                    <div className="space-y-3 pl-1">
                                        <div className="space-y-1">
                                            <Label>繰り返しパターン</Label>
                                            <Select
                                                onValueChange={(value: 'weekly' | 'biweekly') => setRecurrencePattern(value)}
                                                defaultValue={recurrencePattern}
                                            >
                                                <SelectTrigger>
                                                    <SelectValue />
                                                </SelectTrigger>
                                                <SelectContent className="bg-white">
                                                    <SelectItem value="weekly">毎週</SelectItem>
                                                    <SelectItem value="biweekly">隔週</SelectItem>
                                                    <SelectItem value="monthly">毎月</SelectItem>
                                                </SelectContent>
                                            </Select>
                                        </div>

                                        <div className="space-y-1">
                                            <Label>終了条件</Label>
                                            <Select
                                                onValueChange={(value: 'date' | 'count') => setRecurrenceEndType(value)}
                                                defaultValue={recurrenceEndType}
                                            >
                                                <SelectTrigger>
                                                    <SelectValue />
                                                </SelectTrigger>
                                                <SelectContent className="bg-white">
                                                    <SelectItem value="count">指定回数</SelectItem>
                                                    <SelectItem value="date">指定日まで</SelectItem>
                                                </SelectContent>
                                            </Select>
                                        </div>

                                        {recurrenceEndType === 'count' && (
                                            <div className="space-y-1">
                                                <Label>回数</Label>
                                                <Input
                                                    type="number"
                                                    min={1}
                                                    max={52}
                                                    value={recurrenceCount}
                                                    onChange={(e) => setRecurrenceCount(Number(e.target.value))}
                                                />
                                            </div>
                                        )}

                                        {recurrenceEndType === 'date' && (
                                            <div className="space-y-1">
                                                <Label>終了日</Label>
                                                <Input
                                                    type="date"
                                                    value={recurrenceEndDate}
                                                    onChange={(e) => setRecurrenceEndDate(e.target.value)}
                                                />
                                            </div>
                                        )}
                                    </div>
                                )}
                            </div>
                        )}

                        <div className="space-y-2">
                            <Label htmlFor="memo">メモ</Label>
                            <Textarea {...register('memo')} placeholder="メモを入力" />
                        </div>

                        <DialogFooter>
                            <div className="flex justify-between space-x-2 pt-4 w-full">
                                {session ? (
                                    <Button
                                        type="button"
                                        variant="destructive"
                                        disabled={isLoading}
                                        onClick={() => {
                                            if (session.recurrence_group_id) {
                                                setIsRecurrenceDeleteOpen(true);
                                            } else {
                                                setIsDeleteConfirmOpen(true);
                                            }
                                        }}
                                    >
                                        削除
                                    </Button>
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

            {session && (
                <>
                    <AlertDialog open={isDeleteConfirmOpen} onOpenChange={setIsDeleteConfirmOpen}>
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
                    <RecurrenceDeleteDialog
                        isOpen={isRecurrenceDeleteOpen}
                        onClose={() => setIsRecurrenceDeleteOpen(false)}
                        onDeleteSingle={handleDeleteSingle}
                        onDeleteFromDate={handleDeleteFromDate}
                        isLoading={isLoading}
                    />
                </>
            )}
        </>
    );
}
