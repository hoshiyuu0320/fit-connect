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
    'training': { bg: 'bg-blue-50', border: 'border-blue-500', text: 'text-blue-700' },
    'cardio': { bg: 'bg-orange-50', border: 'border-orange-500', text: 'text-orange-700' },
    'stretch': { bg: 'bg-emerald-50', border: 'border-emerald-500', text: 'text-emerald-700' },
    'consultation': { bg: 'bg-purple-50', border: 'border-purple-500', text: 'text-purple-700' },
    'default': { bg: 'bg-gray-50', border: 'border-gray-500', text: 'text-gray-700' }
};

const STATUS_STYLES: Record<string, string> = {
    'scheduled': 'opacity-100',
    'confirmed': 'opacity-100 ring-2 ring-blue-400 ring-opacity-50',
    'completed': 'opacity-60 grayscale',
    'cancelled': 'opacity-50 line-through decoration-gray-400',
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

    const styles = SESSION_COLORS[typeKey];
    const statusOpacity = STATUS_STYLES[event.status] || 'opacity-100';

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
                style={dragStyle}
                {...(!isDragOverlay ? listeners : {})}
                {...(!isDragOverlay ? attributes : {})}
                onClick={(e) => { e.stopPropagation(); onClick(event); }}
                className={`
                    group flex items-center gap-1.5 px-2 py-1 mb-1 mx-1 rounded text-xs truncate cursor-pointer transition-all
                    border-l-[3px] shadow-sm hover:shadow-md hover:scale-[1.01]
                    ${styles.bg} ${styles.border} ${styles.text} ${statusOpacity}
                `}
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
            }}
            {...(!isDragOverlay ? listeners : {})}
            {...(!isDragOverlay ? attributes : {})}
            onClick={(e) => { e.stopPropagation(); onClick(event); }}
            className={`
                absolute inset-x-0 mx-1 rounded-md p-2 text-xs border-l-4 cursor-pointer overflow-hidden
                transition-all duration-200 hover:z-10 hover:shadow-lg hover:-translate-y-0.5
                flex flex-col gap-1
                ${styles.bg} ${styles.border} ${styles.text} ${statusOpacity}
            `}
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
                    📋 {planName}
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
