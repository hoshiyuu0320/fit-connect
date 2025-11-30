'use client';

import { useState, useEffect, useCallback } from 'react';
import { format, startOfMonth, endOfMonth, startOfWeek, endOfWeek, isSameMonth, isSameDay, addMonths, addDays, getDay } from 'date-fns';
import { ChevronLeft, ChevronRight, Plus, Search } from 'lucide-react';
import { Button } from '@/components/ui/button';
import { getSessions, Session } from '@/lib/supabase/getSessions';
import SessionModal from './SessionModal';
import { CalendarEvent } from './CalendarEvent';

type ViewMode = 'day' | 'week' | 'month';

const HOURS = Array.from({ length: 17 }, (_, i) => i + 6); // 6 AM to 10 PM
const WEEK_DAYS = ['月', '火', '水', '木', '金', '土', '日'];

export default function CalendarView() {
    const [currentDate, setCurrentDate] = useState<Date | null>(null);
    const [viewMode, setViewMode] = useState<ViewMode>('week');
    const [sessions, setSessions] = useState<Session[]>([]);
    const [selectedDate, setSelectedDate] = useState<Date | undefined>(undefined);
    const [selectedSession, setSelectedSession] = useState<Session | null>(null);
    const [isModalOpen, setIsModalOpen] = useState(false);
    const [searchQuery, setSearchQuery] = useState('');

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
        setSelectedSession(session);
        setSelectedDate(undefined);
        setIsModalOpen(true);
    };

    const visibleDays = useCallback(() => {
        if (!currentDate) return [];
        if (viewMode === 'day') {
            return [currentDate];
        }
        const start = startOfWeek(currentDate, { weekStartsOn: 1 }); // Monday start
        return Array.from({ length: 7 }, (_, i) => addDays(start, i));
    }, [viewMode, currentDate]);

    const filteredSessions = useCallback(() => {
        if (!searchQuery) return sessions;
        const lower = searchQuery.toLowerCase();
        return sessions.filter(s =>
            s.clients?.name.toLowerCase().includes(lower) ||
            s.session_type?.toLowerCase().includes(lower)
        );
    }, [sessions, searchQuery]);

    // Time Grid View Render (Shared for Week and Day)
    const renderTimeGridView = () => {
        const days = visibleDays();
        return (
            <div className="flex flex-col h-full overflow-hidden bg-white rounded-tl-2xl shadow-sm border border-gray-200">
                {/* Header */}
                <div className="flex border-b border-gray-100 mr-[8px]">
                    <div className="w-16 flex-shrink-0 border-r border-gray-100 bg-gray-50/50"></div>
                    <div className={`flex-1 grid ${viewMode === 'day' ? 'grid-cols-1' : 'grid-cols-7'}`}>
                        {days.map((day, i) => {
                            const isToday = isSameDay(day, new Date());
                            return (
                                <div key={i} className={`py-3 text-center border-r border-gray-100 last:border-0 ${isToday ? 'bg-blue-50/30' : ''}`}>
                                    <div className={`text-xs font-semibold uppercase tracking-wider ${isToday ? 'text-blue-600' : 'text-gray-400'}`}>
                                        {format(day, 'EEE')}
                                    </div>
                                    <div className={`mt-1 text-xl font-medium ${isToday ? 'text-blue-600' : 'text-gray-900'}`}>
                                        {format(day, 'd')}
                                    </div>
                                </div>
                            );
                        })}
                    </div>
                </div>

                {/* Grid Scrollable Area */}
                <div className="flex-1 overflow-y-auto relative">
                    <div className="flex min-h-[800px]">
                        {/* Time Column */}
                        <div className="w-16 flex-shrink-0 border-r border-gray-100 bg-gray-50/30 text-xs text-gray-400 font-medium sticky left-0 z-20 bg-white">
                            {HOURS.map(hour => (
                                <div key={hour} className="h-20 border-b border-gray-100 relative">
                                    <span className="absolute -top-2.5 right-2 bg-white px-1">
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
                            <div className="absolute inset-0 flex flex-col pointer-events-none">
                                {HOURS.map((_, i) => (
                                    <div key={i} className="h-20 border-b border-gray-100 w-full"></div>
                                ))}
                            </div>

                            {/* Interactive Slots & Events */}
                            {days.map((day, dayIndex) => (
                                <div key={dayIndex} className="relative h-full">
                                    {/* Clickable Time Slots */}
                                    {HOURS.map((hour) => (
                                        <div
                                            key={hour}
                                            className="h-20 w-full hover:bg-gray-50/50 transition-colors cursor-pointer"
                                            onClick={() => handleSlotClick(day, hour)}
                                        ></div>
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

                                            // Calculate position relative to 6 AM (start of grid)
                                            const gridStartHour = 6;
                                            const top = ((startHour - gridStartHour) * 60 + startMin) * (80 / 60); // 80px per hour
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
        const endDate = endOfMonth(addDays(monthEnd, 6 - getDay(monthEnd))); // Fill the grid

        const calendarDays: Date[] = [];
        let day = startDate;
        while (day <= endDate || calendarDays.length % 7 !== 0) {
            calendarDays.push(day);
            day = addDays(day, 1);
        }

        // Limit to 6 weeks max to prevent overflow
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
                        const isToday = isSameDay(date, new Date());

                        return (
                            <div
                                key={idx}
                                className={`border-b border-r border-gray-100 p-1 min-h-[100px] flex flex-col transition-colors hover:bg-gray-50/30 cursor-pointer ${!isCurrentMonth ? 'bg-gray-50/30 text-gray-400' : ''}`}
                                onClick={() => handleSlotClick(date, 9)}
                            >
                                <div className="flex justify-end mb-1">
                                    <span className={`text-xs font-medium w-6 h-6 flex items-center justify-center rounded-full ${isToday ? 'bg-blue-600 text-white' : ''}`}>
                                        {format(date, 'd')}
                                    </span>
                                </div>
                                <div className="flex-1 overflow-y-auto space-y-0.5 custom-scrollbar">
                                    {dayAppts.map(appt => (
                                        <CalendarEvent key={appt.id} event={appt} onClick={handleSessionClick} viewMode="month" />
                                    ))}
                                </div>
                            </div>
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
        <div className="flex flex-col h-full bg-gray-50/50 selection:bg-blue-100">
            {/* Top Header */}
            <header className="h-16 flex items-center justify-between px-6 border-b border-gray-100 bg-white flex-shrink-0 z-30">
                <div className="flex items-center gap-6">
                    <h1 className="text-xl font-semibold tracking-tight w-[190px]">
                        {format(currentDate, 'MMMM yyyy')}
                    </h1>

                    <div className="flex items-center bg-gray-100 rounded-lg p-1 gap-1">
                        <button onClick={() => navigateDate('prev')} className="p-1 hover:bg-white hover:shadow-sm rounded-md transition-all text-gray-600"><ChevronLeft size={16} /></button>
                        <button onClick={() => navigateDate('today')} className="px-3 py-1 text-xs font-medium text-gray-700 hover:bg-white hover:shadow-sm rounded-md transition-all">Today</button>
                        <button onClick={() => navigateDate('next')} className="p-1 hover:bg-white hover:shadow-sm rounded-md transition-all text-gray-600"><ChevronRight size={16} /></button>
                    </div>
                </div>

                <div className="flex items-center gap-4">
                    {/* Search */}
                    <div className="hidden md:flex items-center relative group">
                        <Search size={16} className="absolute left-3 text-gray-400 group-focus-within:text-gray-600" />
                        <input
                            type="text"
                            placeholder="Search schedule..."
                            value={searchQuery}
                            onChange={(e) => setSearchQuery(e.target.value)}
                            className="pl-9 pr-4 py-1.5 bg-gray-50 border border-transparent focus:bg-white focus:border-gray-200 focus:ring-2 focus:ring-gray-100 rounded-lg text-sm transition-all w-64 outline-none"
                        />
                    </div>

                    {/* View Toggle */}
                    <div className="bg-gray-100 p-1 rounded-lg flex text-sm font-medium">
                        {(['day', 'week', 'month'] as ViewMode[]).map((mode) => (
                            <button
                                key={mode}
                                onClick={() => setViewMode(mode)}
                                className={`px-3 py-2 rounded-md capitalize transition-all ${viewMode === mode ? 'bg-white text-gray-900 shadow-sm' : 'text-gray-500 hover:text-gray-700'}`}
                            >
                                {mode}
                            </button>
                        ))}
                    </div>

                    <Button size="sm" onClick={() => { setSelectedDate(new Date()); setSelectedSession(null); setIsModalOpen(true); }}>
                        <Plus className="h-4 w-4 mr-2" />
                        New Session
                    </Button>
                </div>
            </header >

            {/* Content Area */}
            < div className="flex-1 overflow-hidden p-0 bg-gray-50/50" >
                {viewMode === 'month' ? renderMonthView() : renderTimeGridView()
                }
            </div >

            <SessionModal
                isOpen={isModalOpen}
                onClose={() => setIsModalOpen(false)}
                selectedDate={selectedDate}
                session={selectedSession}
                onSuccess={fetchSessions}
            />
        </div >
    );
}
