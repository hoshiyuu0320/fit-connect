'use client';

import { useState, useEffect, useCallback } from 'react';
import { format, startOfMonth, endOfMonth, startOfWeek, isSameMonth, isSameDay, addMonths, addDays, getDay } from 'date-fns';
import { ja } from 'date-fns/locale';
import { ChevronLeft, ChevronRight, Plus, Search, ClipboardList } from 'lucide-react';
import { DndContext, DragOverlay, closestCenter, DragEndEvent, DragStartEvent, useDroppable, useSensor, useSensors, PointerSensor } from '@dnd-kit/core';
import { Button } from '@/components/ui/button';
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog';
import { supabase } from '@/lib/supabase';
import { getSessions, Session } from '@/lib/supabase/getSessions';
import { updateSession } from '@/lib/supabase/updateSession';
import { ClientSelector } from '@/components/workout/ClientSelector';
import { TemplatePanel } from '@/components/workout/TemplatePanel';
import TicketSelectModal from '@/components/workout/TicketSelectModal';
import SessionModal from './SessionModal';
import { CalendarEvent } from './CalendarEvent';
import { TimeSlotCell } from './TimeSlotCell';
import { AssignmentMiniCard } from './AssignmentMiniCard';
import type { WorkoutAssignment, WorkoutPlan } from '@/types/workout';

type ViewMode = 'day' | 'week' | 'month';

const HOURS = Array.from({ length: 17 }, (_, i) => i + 6);
const WEEK_DAYS = ['月', '火', '水', '木', '金', '土', '日'];
const VIEW_MODE_LABELS: Record<ViewMode, string> = { day: '日', week: '週', month: '月' };
const TODAY_LABELS: Record<ViewMode, string> = { day: '今日', week: '今週', month: '今月' };

// 月ビュー用のdroppableセル
function MonthDayCell({ date, isCurrentMonth, isToday, children, onClick }: {
    date: Date;
    isCurrentMonth: boolean;
    isToday: boolean;
    children: React.ReactNode;
    onClick: () => void;
}) {
    const dateStr = format(date, 'yyyy-MM-dd');
    const { isOver, setNodeRef } = useDroppable({
        id: `monthDay-${dateStr}`,
        data: { type: 'monthDay', date: dateStr },
    });

    return (
        <div
            ref={setNodeRef}
            className={`border-b border-r border-gray-100 p-1 min-h-[100px] flex flex-col transition-colors cursor-pointer ${
                !isCurrentMonth ? 'bg-gray-50/30 text-gray-400' : ''
            } ${isOver ? 'bg-blue-50 border-blue-400' : 'hover:bg-gray-50/30'}`}
            onClick={onClick}
        >
            <div className="flex justify-end mb-1">
                <span className={`text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full ${isToday ? 'bg-blue-600 text-white' : ''}`}>
                    {format(date, 'd')}
                </span>
            </div>
            <div className="flex-1 overflow-y-auto space-y-0.5 custom-scrollbar">
                {children}
            </div>
        </div>
    );
}

export default function CalendarView() {
    const [currentDate, setCurrentDate] = useState<Date | null>(null);
    const [viewMode, setViewMode] = useState<ViewMode>('week');
    const [sessions, setSessions] = useState<Session[]>([]);
    const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
    const [selectedSession, setSelectedSession] = useState<Session | null>(null);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');
    const [draggedSession, setDraggedSession] = useState<Session | null>(null);

    // 追加 state
    const [trainerId, setTrainerId] = useState('');
    const [selectedClientId, setSelectedClientId] = useState<string | null>(null);
    const [isWorkoutPanelOpen, setIsWorkoutPanelOpen] = useState(false);
    const [templates, setTemplates] = useState<WorkoutPlan[]>([]);
    const [assignments, setAssignments] = useState<WorkoutAssignment[]>([]);
    const [draggedTemplate, setDraggedTemplate] = useState<WorkoutPlan | null>(null);
    const [pendingDrop, setPendingDrop] = useState<{ planId: string; date: string; hour?: number } | null>(null);
    const [isTicketModalOpen, setIsTicketModalOpen] = useState(false);
    const [isClientSelectModalOpen, setIsClientSelectModalOpen] = useState(false);
    const [pendingTemplateDrop, setPendingTemplateDrop] = useState<{ planId: string; date: string; hour?: number } | null>(null);

    const sensors = useSensors(
        useSensor(PointerSensor, {
            activationConstraint: {
                distance: 8,
            },
        })
    );

    useEffect(() => {
        setCurrentDate(new Date());
    }, []);

    // トレーナーID取得
    useEffect(() => {
        const fetchUser = async () => {
            const { data: { user } } = await supabase.auth.getUser();
            if (user) setTrainerId(user.id);
        };
        fetchUser();
    }, []);

    const fetchSessions = useCallback(async () => {
        if (!currentDate) return;
        // 月ビューの表示グリッド（42日間・月曜始まり）と完全一致させる
        const start = startOfWeek(startOfMonth(currentDate), { weekStartsOn: 1 });
        const end = addDays(start, 41);
        try {
            const data = await getSessions(start, end);
            setSessions(data);
        } catch (error) {
            console.error('Failed to fetch sessions', error);
        }
    }, [currentDate]);

    useEffect(() => {
        fetchSessions();
    }, [fetchSessions]);

    // テンプレート取得
    const fetchTemplates = useCallback(async () => {
        if (!trainerId) return;
        try {
            const res = await fetch(`/api/workout-plans?trainerId=${trainerId}`);
            if (res.ok) {
                const json = await res.json();
                setTemplates(json.data || []);
            }
        } catch (error) {
            console.error('テンプレート取得エラー:', error);
        }
    }, [trainerId]);

    useEffect(() => {
        fetchTemplates();
    }, [fetchTemplates]);

    // アサインメント取得（クライアント選択時のみ）
    const fetchAssignments = useCallback(async () => {
        if (!trainerId || !selectedClientId) {
            setAssignments([]);
            return;
        }
        try {
            const start = startOfWeek(startOfMonth(currentDate!), { weekStartsOn: 1 });
            const end = addDays(start, 41);
            const weekStart = format(start, 'yyyy-MM-dd');
            const weekEnd = format(end, 'yyyy-MM-dd');
            const res = await fetch(
                `/api/workout-assignments?trainerId=${trainerId}&clientId=${selectedClientId}&weekStart=${weekStart}&weekEnd=${weekEnd}`
            );
            if (res.ok) {
                const json = await res.json();
                setAssignments(json.data || []);
            }
        } catch (error) {
            console.error('アサインメント取得エラー:', error);
        }
    }, [trainerId, selectedClientId, currentDate]);

    useEffect(() => {
        fetchAssignments();
    }, [fetchAssignments]);

    const navigateDate = (direction: 'prev' | 'next' | 'today') => {
        if (direction === 'today') {
            setCurrentDate(new Date());
            return;
        }

        const delta = direction === 'next' ? 1 : -1;
        if (viewMode === 'day') setCurrentDate(d => d ? addDays(d, delta) : new Date());
        else if (viewMode === 'week') setCurrentDate(d => d ? addDays(d, delta * 7) : new Date());
        else if (viewMode === 'month') setCurrentDate(d => d ? addMonths(d, delta) : new Date());
    };

    const handleSlotClick = (date: Date, hour?: number) => {
        const start = new Date(date);
        if (hour !== undefined) {
            start.setHours(hour, 0, 0, 0);
        }
        setSelectedDate(start);
        setSelectedSession(null);
        setIsModalOpen(true);
    };

    const handleSessionClick = (session: Session) => {
        if (draggedSession) return;
        setSelectedSession(session);
        setSelectedDate(undefined);
        setIsModalOpen(true);
    };

    const visibleDays = useCallback(() => {
        if (!currentDate) return [];
        if (viewMode === 'day') {
            return [currentDate];
        }
        const start = startOfWeek(currentDate, { weekStartsOn: 1 });
        return Array.from({ length: 7 }, (_, i) => addDays(start, i));
    }, [viewMode, currentDate]);

    // クライアントフィルタ対応
    const filteredSessions = useCallback(() => {
        let result = sessions;
        // クライアント選択フィルタ
        if (selectedClientId) {
            result = result.filter(s => s.client_id === selectedClientId);
        }
        // テキスト検索
        if (searchQuery) {
            const lower = searchQuery.toLowerCase();
            result = result.filter(s =>
                s.clients?.name.toLowerCase().includes(lower) ||
                s.session_type?.toLowerCase().includes(lower)
            );
        }
        return result;
    }, [sessions, searchQuery, selectedClientId]);

    // D&D handlers
    const handleDragStart = (event: DragStartEvent) => {
        const { active } = event;
        const activeData = active.data.current;
        if (activeData?.type === 'session') {
            const session = sessions.find(s => s.id === activeData.sessionId);
            if (session) setDraggedSession(session);
        }
        if (activeData?.type === 'template') {
            const plan = templates.find(t => t.id === activeData.planId);
            if (plan) setDraggedTemplate(plan);
        }
    };

    const handleDragEnd = async (event: DragEndEvent) => {
        setDraggedSession(null);
        setDraggedTemplate(null);
        const { active, over } = event;
        if (!over || !active.data.current) return;

        const activeData = active.data.current;
        const overData = over.data.current;
        if (!overData) return;

        // ===== 既存: セッション移動 =====
        if (activeData.type === 'session') {
            const sessionId = activeData.sessionId as string;
            const session = sessions.find(s => s.id === sessionId);
            if (!session) return;

            const originalDate = new Date(session.session_date);
            let newDate: Date;

            if (overData.type === 'timeSlot') {
                const [year, month, day] = (overData.date as string).split('-').map(Number);
                newDate = new Date(year, month - 1, day, overData.hour as number, originalDate.getMinutes());
            } else if (overData.type === 'monthDay') {
                const [year, month, day] = (overData.date as string).split('-').map(Number);
                newDate = new Date(year, month - 1, day, originalDate.getHours(), originalDate.getMinutes());
            } else {
                return;
            }

            if (newDate.getTime() === originalDate.getTime()) return;

            // 楽観的更新: ローカルstateを即座に更新して複製表示を防ぐ
            setSessions(prev => prev.map(s =>
                s.id === sessionId
                    ? { ...s, session_date: newDate.toISOString() }
                    : s
            ));

            try {
                await updateSession({ id: sessionId, session_date: newDate });
                await fetchSessions();
            } catch (error) {
                console.error('Failed to move session:', error);
                await fetchSessions();
            }
            return;
        }

        // ===== 新規: テンプレート → カレンダーにD&D =====
        if (activeData.type === 'template' && (overData.type === 'timeSlot' || overData.type === 'monthDay')) {
            const plan = templates.find(t => t.id === activeData.planId);
            if (!plan) return;

            const dropDate = overData.date as string;
            const dropHour = overData.type === 'timeSlot' ? (overData.hour as number) : undefined;

            if (!selectedClientId) {
                setPendingTemplateDrop({ planId: plan.id, date: dropDate, hour: dropHour });
                setIsClientSelectModalOpen(true);
                return;
            }

            if (plan.plan_type === 'session') {
                setPendingDrop({ planId: plan.id, date: dropDate, hour: dropHour });
                setIsTicketModalOpen(true);
            } else {
                // 宿題: 即時作成
                try {
                    const res = await fetch('/api/workout-assignments', {
                        method: 'POST',
                        headers: { 'Content-Type': 'application/json' },
                        body: JSON.stringify({
                            trainerId,
                            clientId: selectedClientId,
                            planId: plan.id,
                            assignedDate: dropDate,
                        }),
                    });
                    if (res.ok) {
                        await fetchAssignments();
                    }
                } catch (error) {
                    console.error('アサインメント作成エラー:', error);
                }
            }
            return;
        }

        // ===== 新規: アサインメント日付移動 =====
        if (activeData.type === 'assignment' && (overData.type === 'timeSlot' || overData.type === 'monthDay')) {
            const newDate = overData.date as string;
            try {
                const res = await fetch(`/api/workout-assignments/${activeData.assignmentId}`, {
                    method: 'PATCH',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({ assignedDate: newDate }),
                });
                if (res.ok) {
                    await fetchAssignments();
                }
            } catch (error) {
                console.error('アサインメント更新エラー:', error);
            }
            return;
        }
    };

    // TicketSelectModal ハンドラ
    const handleTicketConfirm = async (ticketId: string | null, sessionTime: string) => {
        if (!pendingDrop || !selectedClientId) return;
        setIsTicketModalOpen(false);
        try {
            const res = await fetch('/api/workout-assignments', {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                body: JSON.stringify({
                    trainerId,
                    clientId: selectedClientId,
                    planId: pendingDrop.planId,
                    assignedDate: pendingDrop.date,
                    ticketId,
                    sessionTime,
                    createSession: true,
                }),
            });
            if (res.ok) {
                await fetchAssignments();
                await fetchSessions();
            } else {
                const json = await res.json();
                alert(json.error || 'エラーが発生しました');
            }
        } catch (error) {
            console.error('セッション付きアサインメント作成エラー:', error);
        } finally {
            setPendingDrop(null);
        }
    };

    const handleTicketCancel = () => {
        setIsTicketModalOpen(false);
        setPendingDrop(null);
    };

    const handleDeleteAssignment = async (id: string) => {
        try {
            const res = await fetch(`/api/workout-assignments/${id}`, { method: 'DELETE' });
            if (res.ok) {
                setAssignments(prev => prev.filter(a => a.id !== id));
            }
        } catch (error) {
            console.error('アサインメント削除エラー:', error);
        }
    };

    const handleClientSelectForDrop = async (clientId: string) => {
        setSelectedClientId(clientId);
        setIsClientSelectModalOpen(false);
        if (!pendingTemplateDrop) return;
        const { planId, date, hour } = pendingTemplateDrop;
        setPendingTemplateDrop(null);
        const plan = templates.find(t => t.id === planId);
        if (!plan) return;

        if (plan.plan_type === 'session') {
            setPendingDrop({ planId: plan.id, date, hour });
            setIsTicketModalOpen(true);
        } else {
            try {
                const res = await fetch('/api/workout-assignments', {
                    method: 'POST',
                    headers: { 'Content-Type': 'application/json' },
                    body: JSON.stringify({
                        trainerId,
                        clientId,
                        planId: plan.id,
                        assignedDate: date,
                    }),
                });
                if (res.ok) {
                    await fetchAssignments();
                }
            } catch (error) {
                console.error('アサインメント作成エラー:', error);
            }
        }
    };

    // Time Grid View Render (Shared for Week and Day)
    const renderTimeGridView = () => {
        const days = visibleDays();
        return (
            <div className="flex flex-col h-full overflow-hidden bg-white rounded-tl-2xl shadow-sm border border-gray-200">
                {/* Header */}
                <div className="flex border-b border-gray-100">
                    <div className="w-16 flex-shrink-0 border-r border-gray-100 bg-gray-50/50"></div>
                    <div className={`flex-1 grid ${viewMode === 'day' ? 'grid-cols-1' : 'grid-cols-7'}`}>
                        {days.map((day, i) => {
                            const isToday = isSameDay(day, new Date());
                            return (
                                <div key={i} className={`py-3 text-center border-r border-gray-100 last:border-0 ${isToday ? 'bg-blue-50/30' : ''}`}>
                                    <div className={`text-xs font-semibold tracking-wider ${isToday ? 'text-blue-600' : 'text-gray-400'}`}>
                                        {format(day, 'E', { locale: ja })}
                                    </div>
                                    <div className={`mt-1 text-xl font-medium ${isToday ? 'text-blue-600' : 'text-gray-900'}`}>
                                        {format(day, 'd')}
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>

                {/* All-day エリア (アサインメント) */}
                {selectedClientId && days.some(day => assignments.some(a => a.assigned_date === format(day, 'yyyy-MM-dd') && a.plan?.plan_type !== 'session')) && (
                    <div className="flex border-b border-gray-200 bg-gray-50/30">
                        <div className="w-16 flex-shrink-0 border-r border-gray-100 flex items-center justify-center">
                            <span className="text-[10px] text-gray-400">終日</span>
                        </div>
                        <div className={`flex-1 grid ${viewMode === 'day' ? 'grid-cols-1' : 'grid-cols-7'}`}>
                            {days.map((day, i) => {
                                const dayStr = format(day, 'yyyy-MM-dd');
                                const dayAssignments = assignments.filter(a => a.assigned_date === dayStr && a.plan?.plan_type !== 'session');
                                return (
                                    <div key={i} className="px-1 py-1 border-r border-gray-100 last:border-0 min-h-[32px] space-y-0.5">
                                        {dayAssignments.map(a => (
                                            <AssignmentMiniCard key={a.id} assignment={a} viewMode={viewMode} onDelete={handleDeleteAssignment} />
                                        ))}
                                    </div>
                                );
                            })}
                        </div>
                    </div>
                )}

                {/* Grid Scrollable Area */}
                <div className="flex-1 overflow-y-auto relative">
                    <div className="flex min-h-[1360px]">
                        {/* Time Column */}
                        <div className="w-16 flex-shrink-0 border-r border-gray-100 bg-gray-50/30 text-xs text-gray-400 font-medium sticky left-0 z-20 bg-white pb-[50px]">
                            {HOURS.map(hour => (
                                <div key={hour} className="h-20 border-b border-gray-100 relative">
                                    <span className="absolute top-1 right-2 bg-white px-1">
                                        {hour}:00
                                    </span>
                                </div>
                            ))}
                        </div>

                        {/* Days Columns */}
                        <div className={`flex-1 grid ${viewMode === 'day' ? 'grid-cols-1' : 'grid-cols-7'} relative`}>
                            {/* Grid Lines Background */}
                            <div className={`absolute inset-0 grid ${viewMode === 'day' ? 'grid-cols-1' : 'grid-cols-7'} pointer-events-none`}>
                                {days.map((_, i) => (
                                    <div key={i} className="border-r border-gray-100 h-full"></div>
                                ))}
                            </div>

                            {/* Horizontal Hour Lines Background */}
                            <div className="absolute inset-0 flex flex-col pointer-events-none pb-[50px]">
                                {HOURS.map((_, i) => (
                                    <div key={i} className="h-20 border-b border-gray-100 w-full"></div>
                                ))}
                            </div>

                            {/* Interactive Slots & Events */}
                            {days.map((day, dayIndex) => (
                                <div key={dayIndex} className="relative h-full">
                                    {/* Droppable Time Slots */}
                                    {HOURS.map((hour) => (
                                        <TimeSlotCell
                                            key={hour}
                                            dateStr={format(day, 'yyyy-MM-dd')}
                                            hour={hour}
                                            onClick={() => handleSlotClick(day, hour)}
                                        />
                                    ))}

                                    {/* Render Events for this Day */}
                                    {filteredSessions()
                                        .filter(session => isSameDay(new Date(session.session_date), day))
                                        .map(session => {
                                            const startTime = new Date(session.session_date);
                                            const startHour = startTime.getHours();
                                            const startMin = startTime.getMinutes();
                                            const endTime = new Date(startTime.getTime() + session.duration_minutes * 60000);
                                            const endHour = endTime.getHours();
                                            const endMin = endTime.getMinutes();

                                            const gridStartHour = 6;
                                            const top = ((startHour - gridStartHour) * 60 + startMin) * (80 / 60);
                                            const durationMins = (endHour * 60 + endMin) - (startHour * 60 + startMin);
                                            const height = durationMins * (80 / 60);

                                            return (
                                                <div key={session.id} style={{ top: `${top}px`, height: `${height}px`, position: 'absolute', width: '100%' }} className="px-0.5 z-10">
                                                    <CalendarEvent event={session} onClick={handleSessionClick} viewMode={viewMode} />
                                                </div>
                                            );
                                        })
                                    }
                                </div>
                            ))}
                        </div>
                    </div>
                </div>
            </div>
        );
    };

    // Month View Render
    const renderMonthView = () => {
        if (!currentDate) return null;
        const monthStart = startOfMonth(currentDate);
        const monthEnd = endOfMonth(currentDate);
        const startDate = startOfWeek(monthStart, { weekStartsOn: 1 });
        const endDate = endOfMonth(addDays(monthEnd, 6 - getDay(monthEnd)));

        const calendarDays: Date[] = [];
        let day = startDate;
        while (day <= endDate || calendarDays.length % 7 !== 0) {
            calendarDays.push(day);
            day = addDays(day, 1);
        }

        const displayDays = calendarDays.slice(0, 42);

        return (
            <div className="flex flex-col h-full bg-white rounded-tl-2xl shadow-sm border border-gray-200 overflow-hidden">
                {/* Headers */}
                <div className="grid grid-cols-7 border-b border-gray-200 bg-gray-50/50">
                    {WEEK_DAYS.map(d => (
                        <div key={d} className="py-2 text-center text-xs font-semibold text-gray-500 uppercase tracking-wider">
                            {d}
                        </div>
                    ))}
                </div>

                {/* Grid */}
                <div className="flex-1 grid grid-cols-7 grid-rows-5 md:grid-rows-6">
                    {displayDays.map((date, idx) => {
                        const isCurrentMonth = isSameMonth(date, currentDate);
                        const dayAppts = filteredSessions().filter(s => isSameDay(new Date(s.session_date), date));
                        const today = isSameDay(date, new Date());
                        const dayAssignments = assignments.filter(a => a.assigned_date === format(date, 'yyyy-MM-dd'));

                        return (
                            <MonthDayCell
                                key={idx}
                                date={date}
                                isCurrentMonth={isCurrentMonth}
                                isToday={today}
                                onClick={() => handleSlotClick(date, 9)}
                            >
                                {/* アサインメントカードをセッションカードの前に表示 */}
                                {dayAssignments.map(a => (
                                    <AssignmentMiniCard key={a.id} assignment={a} viewMode="month" onDelete={handleDeleteAssignment} />
                                ))}
                                {dayAppts.map(appt => (
                                    <CalendarEvent key={appt.id} event={appt} onClick={handleSessionClick} viewMode="month" />
                                ))}
                            </MonthDayCell>
                        );
                    })}
                </div>
            </div>
        );
    };

    if (!currentDate) {
        return null;
    }

    return (
        <DndContext
            sensors={sensors}
            collisionDetection={closestCenter}
            onDragStart={handleDragStart}
            onDragEnd={handleDragEnd}
        >
            <div className="flex flex-col h-full bg-gray-50/50 selection:bg-blue-100">
                {/* Top Header */}
                <header className="flex flex-col border-b border-gray-100 bg-white flex-shrink-0 z-30">
                    {/* 上段: 日付 + セッション追加 + ワークアウト */}
                    <div className="flex items-center justify-between px-6 py-2.5">
                        <h1 className="text-lg font-semibold tracking-tight">
                            {format(currentDate, 'yyyy年M月', { locale: ja })}
                        </h1>
                        <div className="flex items-center gap-3">
                            <Button size="sm" className="w-40 h-10 justify-center" onClick={() => { setSelectedDate(new Date()); setSelectedSession(null); setIsModalOpen(true); }}>
                                <Plus className="h-4 w-4 mr-2" />
                                セッション追加
                            </Button>
                            <button
                                onClick={() => setIsWorkoutPanelOpen(prev => !prev)}
                                className={`w-40 h-10 flex items-center justify-center gap-1.5 px-3 rounded-lg text-sm font-medium transition-all ${
                                    isWorkoutPanelOpen
                                        ? 'bg-blue-100 text-blue-700'
                                        : 'bg-gray-100 text-gray-600 hover:bg-gray-200'
                                }`}
                            >
                                <ClipboardList size={16} />
                                <span className="hidden md:inline">ワークアウト</span>
                            </button>
                        </div>
                    </div>

                    {/* 下段: ビュー切替 + ナビ | 検索 + クライアント選択 */}
                    <div className="flex items-center justify-between px-6 py-2">
                        <div className="flex items-center gap-3">
                            <div className="bg-gray-100 p-1 rounded-lg flex text-sm font-medium">
                                {(['day', 'week', 'month'] as ViewMode[]).map((mode) => (
                                    <button
                                        key={mode}
                                        onClick={() => setViewMode(mode)}
                                        className={`px-3 py-1.5 rounded-md transition-all ${viewMode === mode ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}
                                    >
                                        {VIEW_MODE_LABELS[mode]}
                                    </button>
                                ))}
                            </div>
                            <div className="flex items-center bg-gray-100 rounded-lg p-1 gap-1 text-sm font-medium">
                                <button onClick={() => navigateDate('prev')} className="px-1.5 py-1.5 hover:bg-white hover:shadow-sm rounded-md transition-all text-gray-600"><ChevronLeft size={16} /></button>
                                <button onClick={() => navigateDate('today')} className="px-3 py-1.5 text-gray-700 hover:bg-white hover:shadow-sm rounded-md transition-all">{TODAY_LABELS[viewMode]}</button>
                                <button onClick={() => navigateDate('next')} className="px-1.5 py-1.5 hover:bg-white hover:shadow-sm rounded-md transition-all text-gray-600"><ChevronRight size={16} /></button>
                            </div>
                        </div>
                        <div className="flex items-center gap-3">
                            <div className="hidden md:flex items-center relative group">
                                <Search size={16} className="absolute left-3 text-gray-400 group-focus-within:text-gray-600" />
                                <input
                                    type="text"
                                    placeholder="スケジュールを検索..."
                                    value={searchQuery}
                                    onChange={(e) => setSearchQuery(e.target.value)}
                                    className="pl-9 pr-4 h-10 bg-gray-50 border border-transparent focus:bg-white focus:border-gray-200 focus:ring-2 focus:ring-gray-100 rounded-lg text-xs font-medium transition-all w-40 outline-none"
                                />
                            </div>
                            {trainerId && (
                                <ClientSelector
                                    trainerId={trainerId}
                                    selectedClientId={selectedClientId ?? '__all__'}
                                    onSelect={(id) => setSelectedClientId(id === '__all__' ? null : id)}
                                    showAllOption
                                    className="w-40 h-10"
                                />
                            )}
                        </div>
                    </div>
                </header>

                {/* Content Area - サイドパネル付き */}
                <div className="flex-1 overflow-hidden flex">
                    {/* カレンダー本体 */}
                    <div className="flex-1 overflow-hidden bg-gray-50/50 min-w-0">
                        {viewMode === 'month' ? renderMonthView() : renderTimeGridView()}
                    </div>

                    {/* ワークアウトサイドパネル */}
                    <div className={`transition-all duration-300 ease-in-out flex-shrink-0 overflow-hidden border-l border-gray-200 bg-white ${
                        isWorkoutPanelOpen ? 'w-80' : 'w-0'
                    }`}>
                        {isWorkoutPanelOpen && (
                            <TemplatePanel
                                trainerId={trainerId}
                                templates={templates}
                                onRefetch={fetchTemplates}
                            />
                        )}
                    </div>
                </div>

                <SessionModal
                    isOpen={isModalOpen}
                    onClose={() => setIsModalOpen(false)}
                    selectedDate={selectedDate}
                    session={selectedSession}
                    onSuccess={fetchSessions}
                />

                {/* TicketSelectModal */}
                {selectedClientId && pendingDrop && (
                    <TicketSelectModal
                        isOpen={isTicketModalOpen}
                        clientId={selectedClientId}
                        planTitle={templates.find(t => t.id === pendingDrop.planId)?.title ?? ''}
                        assignedDate={pendingDrop.date}
                        estimatedMinutes={templates.find(t => t.id === pendingDrop.planId)?.estimated_minutes ?? null}
                        defaultSessionTime={pendingDrop.hour != null ? `${String(pendingDrop.hour).padStart(2, '0')}:00` : undefined}
                        onConfirm={handleTicketConfirm}
                        onCancel={handleTicketCancel}
                    />
                )}

                {/* クライアント選択モーダル */}
                <Dialog open={isClientSelectModalOpen} onOpenChange={(open) => { if (!open) { setIsClientSelectModalOpen(false); setPendingTemplateDrop(null); } }}>
                    <DialogContent className="sm:max-w-[400px] bg-white">
                        <DialogHeader>
                            <DialogTitle>クライアントを選択してください</DialogTitle>
                        </DialogHeader>
                        <div className="py-4">
                            {trainerId && (
                                <ClientSelector
                                    trainerId={trainerId}
                                    selectedClientId={null}
                                    onSelect={handleClientSelectForDrop}
                                    className="w-full"
                                />
                            )}
                        </div>
                    </DialogContent>
                </Dialog>
            </div>

            {/* Drag Overlay */}
            <DragOverlay>
                {draggedSession && (
                    <div className="w-48 opacity-90 shadow-xl">
                        <CalendarEvent
                            event={draggedSession}
                            onClick={() => {}}
                            viewMode="month"
                            isDragOverlay
                        />
                    </div>
                )}
                {draggedTemplate && (
                    <div className="p-3 bg-white border-2 border-blue-400 rounded-lg shadow-lg opacity-90">
                        <div className="font-bold text-gray-800 text-sm">{draggedTemplate.title}</div>
                        <div className="text-xs text-gray-500 mt-1">
                            {draggedTemplate.exercise_count ?? 0} 種目
                        </div>
                    </div>
                )}
            </DragOverlay>
        </DndContext>
    );
}
