'use client';

import { useState, useEffect, useCallback } from 'react';
import { format, startOfMonth, endOfMonth, eachDayOfInterval, startOfWeek, endOfWeek, isSameMonth, isSameDay, addMonths, subMonths } from 'date-fns';
import { ja } from 'date-fns/locale';
import { ChevronLeft, ChevronRight, Plus } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { getSessions, Session } from '@/lib/supabase/getSessions';
import SessionModal from './SessionModal';
import { cn } from '@/lib/utils';

export default function CalendarView() {
    const [currentDate, setCurrentDate] = useState<Date | null>(null);
    const [sessions, setSessions] = useState<Session[]>([]);
    const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
    const [selectedSession, setSelectedSession] = useState<Session | null>(null);
    const [isModalOpen, setIsModalOpen] = useState(false);

    useEffect(() => {
        setCurrentDate(new Date());
    }, []);

    const fetchSessions = useCallback(async () => {
        if (!currentDate) return;
        const start = startOfWeek(startOfMonth(currentDate));
        const end = endOfWeek(endOfMonth(currentDate));
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

    const handlePrevMonth = () => {
        if (currentDate) setCurrentDate(subMonths(currentDate, 1));
    };

    const handleNextMonth = () => {
        if (currentDate) setCurrentDate(addMonths(currentDate, 1));
    };

    const handleDateClick = (date: Date) => {
        setSelectedDate(date);
        setSelectedSession(null);
        setIsModalOpen(true);
    };

    const handleSessionClick = (e: React.MouseEvent, session: Session) => {
        e.stopPropagation();
        setSelectedSession(session);
        setSelectedDate(undefined);
        setIsModalOpen(true);
    };

    const getStatusColor = (status: string) => {
        switch (status) {
            case 'confirmed': return 'bg-blue-100 text-blue-800 border-blue-200';
            case 'completed': return 'bg-green-100 text-green-800 border-green-200';
            case 'cancelled': return 'bg-red-100 text-red-800 border-red-200';
            default: return 'bg-gray-100 text-gray-800 border-gray-200';
        }
    };

    if (!currentDate) {
        return null;
    }

    const days = eachDayOfInterval({
        start: startOfWeek(startOfMonth(currentDate)),
        end: endOfWeek(endOfMonth(currentDate)),
    });

    return (
        <div className="bg-white rounded-lg shadow p-6">
            <div className="flex items-center justify-between mb-6">
                <h2 className="text-2xl font-bold text-gray-800">
                    {format(currentDate, 'yyyy年 M月', { locale: ja })}
                </h2>
                <div className="flex gap-2">
                    <Button variant="outline" size="icon" onClick={handlePrevMonth}>
                        <ChevronLeft className="h-4 w-4" />
                    </Button>
                    <Button variant="outline" size="icon" onClick={handleNextMonth}>
                        <ChevronRight className="h-4 w-4" />
                    </Button>
                    <Button onClick={() => { setSelectedDate(new Date()); setSelectedSession(null); setIsModalOpen(true); }}>
                        <Plus className="h-4 w-4 mr-2" />
                        予約作成
                    </Button>
                </div>
            </div>

            <div className="grid grid-cols-7 gap-px bg-gray-200 border border-gray-200 rounded-lg overflow-hidden">
                {['日', '月', '火', '水', '木', '金', '土'].map((day) => (
                    <div key={day} className="bg-gray-50 p-2 text-center text-sm font-medium text-gray-500">
                        {day}
                    </div>
                ))}
                {days.map((day) => {
                    const daySessions = sessions.filter(s => isSameDay(new Date(s.session_date), day));
                    return (
                        <div
                            key={day.toISOString()}
                            onClick={() => handleDateClick(day)}
                            className={cn(
                                "bg-white min-h-[120px] p-2 cursor-pointer hover:bg-gray-50 transition-colors relative",
                                !isSameMonth(day, currentDate) && "bg-gray-50 text-gray-400"
                            )}
                        >
                            <div className={cn(
                                "text-sm font-medium mb-1 w-7 h-7 flex items-center justify-center rounded-full",
                                isSameDay(day, new Date()) && "bg-primary text-primary-foreground"
                            )}>
                                {format(day, 'd')}
                            </div>
                            <div className="space-y-1">
                                {daySessions.map((session) => (
                                    <div
                                        key={session.id}
                                        onClick={(e) => handleSessionClick(e, session)}
                                        className={cn(
                                            "text-xs p-1 rounded border truncate",
                                            getStatusColor(session.status)
                                        )}
                                    >
                                        {format(new Date(session.session_date), 'HH:mm')} {session.clients?.name}
                                    </div>
                                ))}
                            </div>
                        </div>
                    );
                })}
            </div>

            <SessionModal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
                selectedDate={selectedDate}
                session={selectedSession}
                onSuccess={fetchSessions}
            />
        </div>
    );
}
