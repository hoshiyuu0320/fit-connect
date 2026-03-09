'use client';

import React from 'react';
import { useDraggable } from '@dnd-kit/core';
import { CSS } from '@dnd-kit/utilities';
import { Session } from '@/lib/supabase/getSessions';
import { AlignLeft } from 'lucide-react';
import { format } from 'date-fns';

interface CalendarEventProps {
    event: Session;
    onClick: (event: Session) => void;
    viewMode: 'day' | 'week' | 'month';
    isDragOverlay?: boolean;
}

const SESSION_COLORS: Record<string, { bg: string; border: string; text: string }> = {
    'training': { bg: '#F0FDFA', border: '#14B8A6', text: '#0D9488' },
    'cardio': { bg: '#FFF7ED', border: '#F97316', text: '#C2410C' },
    'stretch': { bg: '#F0FDF4', border: '#22C55E', text: '#15803D' },
    'consultation': { bg: '#FAF5FF', border: '#A855F7', text: '#7E22CE' },
    'default': { bg: '#F8FAFC', border: '#94A3B8', text: '#475569' }
};

const STATUS_STYLES: Record<string, { opacity: number }> = {
    'scheduled': { opacity: 1 },
    'confirmed': { opacity: 1 },
    'completed': { opacity: 0.7 },
    'cancelled': { opacity: 0.4 }
};

export const CalendarEvent: React.FC<CalendarEventProps> = ({ event, onClick, viewMode, isDragOverlay = false }) => {
    const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
        id: `session-${event.id}`,
        data: { type: 'session', sessionId: event.id },
        disabled: isDragOverlay,
    });

    const dragStyle = !isDragOverlay ? {
        transform: CSS.Translate.toString(transform),
        opacity: isDragging ? 0.4 : 1,
    } : {};

    let typeKey = 'default';
    if (event.session_type === '有酸素トレーニング') typeKey = 'cardio';
    else if (event.session_type === 'ストレッチ') typeKey = 'stretch';
    else if (event.session_type === 'カウンセリング') typeKey = 'consultation';
    else if (event.session_type?.includes('トレーニング')) typeKey = 'training';

    const planName = event.workout_assignments?.[0]?.plan?.title ?? null;

    const colors = SESSION_COLORS[typeKey];
    const statusStyle = STATUS_STYLES[event.status] ?? { opacity: 1 };

    const formatTime = (dateStr: string) => {
        return format(new Date(dateStr), 'HH:mm');
    };

    const startTime = new Date(event.session_date);
    const endTime = new Date(startTime.getTime() + event.duration_minutes * 60000);

    const isSmall = viewMode === 'month';

    if (isSmall) {
        return (
            <div
                ref={!isDragOverlay ? setNodeRef : undefined}
                style={{
                    ...dragStyle,
                    backgroundColor: colors.bg,
                    borderLeft: `3px solid ${colors.border}`,
                    color: colors.text,
                    opacity: statusStyle.opacity,
                    borderRadius: '4px',
                }}
                {...(!isDragOverlay ? listeners : {})}
                {...(!isDragOverlay ? attributes : {})}
                onClick={(e) => { e.stopPropagation(); onClick(event); }}
                className="group flex items-center gap-1.5 px-2 py-1 mb-1 mx-1 text-xs truncate cursor-pointer transition-all"
            >
                <span className="font-semibold">{formatTime(event.session_date)}</span>
                <span className="truncate">{event.clients?.name || '不明'}</span>
            </div>
        );
    }

    // Week/Day view detailed card
    return (
        <div
            ref={!isDragOverlay ? setNodeRef : undefined}
            style={{
                ...dragStyle,
                top: 0,
                height: '100%',
                backgroundColor: colors.bg,
                borderLeft: `4px solid ${colors.border}`,
                color: colors.text,
                opacity: statusStyle.opacity,
                borderRadius: '6px',
            }}
            {...(!isDragOverlay ? listeners : {})}
            {...(!isDragOverlay ? attributes : {})}
            onClick={(e) => { e.stopPropagation(); onClick(event); }}
            className="absolute inset-x-0 mx-1 p-2 text-xs cursor-pointer overflow-hidden transition-all duration-200 hover:z-10 flex flex-col gap-1"
        >
            <div className="flex justify-between items-start">
                <span className="font-bold text-[11px] leading-tight opacity-90">
                    {formatTime(event.session_date)} - {format(endTime, 'HH:mm')}
                </span>
            </div>
            <div className="font-semibold leading-tight text-sm truncate">{event.clients?.name}</div>
            <div className="text-[10px] truncate opacity-80">{event.session_type}</div>
            {planName && (
                <div className="text-[10px] truncate opacity-70 italic">
                    {planName}
                </div>
            )}
            {event.memo && (
                <div className="flex items-center gap-1 opacity-75 mt-auto">
                    <AlignLeft size={10} />
                    <span className="truncate text-[10px]">メモあり</span>
                </div>
            )}
        </div>
    );
};
