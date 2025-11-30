import React from 'react';
import { Session } from '@/lib/supabase/getSessions';
import { AlignLeft } from 'lucide-react';
import { format } from 'date-fns';

interface CalendarEventProps {
    event: Session;
    onClick: (event: Session) => void;
    viewMode: 'day' | 'week' | 'month';
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

export const CalendarEvent: React.FC<CalendarEventProps> = ({ event, onClick, viewMode }) => {
    // session_typeに基づいて色を決定（簡易的なマッピング）
    let typeKey = 'default';
    if (event.session_type?.includes('トレーニング')) typeKey = 'training';
    else if (event.session_type?.includes('有酸素')) typeKey = 'cardio';
    else if (event.session_type?.includes('ストレッチ')) typeKey = 'stretch';
    else if (event.session_type?.includes('カウンセリング')) typeKey = 'consultation';

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
                onClick={(e) => { e.stopPropagation(); onClick(event); }}
                className={`
          group flex items-center gap-1.5 px-2 py-1 mb-1 mx-1 rounded text-xs truncate cursor-pointer transition-all
          border-l-[3px] shadow-sm hover:shadow-md hover:scale-[1.01]
          ${styles.bg} ${styles.border} ${styles.text} ${statusOpacity}
        `}
            >
                <span className="font-semibold">{formatTime(event.session_date)}</span>
                <span className="truncate">{event.clients?.name || 'Unknown'}</span>
            </div>
        );
    }

    // Week/Day view detailed card
    return (
        <div
            onClick={(e) => { e.stopPropagation(); onClick(event); }}
            className={`
        absolute inset-x-0 mx-1 rounded-md p-2 text-xs border-l-4 cursor-pointer overflow-hidden
        transition-all duration-200 hover:z-10 hover:shadow-lg hover:-translate-y-0.5
        flex flex-col gap-1
        ${styles.bg} ${styles.border} ${styles.text} ${statusOpacity}
      `}
            style={{
                top: 0, // Positioned by parent
                height: '100%', // Positioned by parent
            }}
        >
            <div className="flex justify-between items-start">
                <span className="font-bold text-[11px] leading-tight opacity-90">
                    {formatTime(event.session_date)} - {format(endTime, 'HH:mm')}
                </span>
            </div>
            <div className="font-semibold leading-tight text-sm truncate">{event.clients?.name}</div>
            <div className="text-[10px] truncate opacity-80">{event.session_type}</div>
            {event.memo && (
                <div className="flex items-center gap-1 opacity-75 mt-auto">
                    <AlignLeft size={10} />
                    <span className="truncate text-[10px]">メモあり</span>
                </div>
            )}
        </div>
    );
};
