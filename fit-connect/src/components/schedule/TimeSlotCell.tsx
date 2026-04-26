'use client';

import { useDroppable } from '@dnd-kit/core';

interface TimeSlotCellProps {
  dateStr: string;
  hour: number;
  onClick: () => void;
  children?: React.ReactNode;
}

export function TimeSlotCell({ dateStr, hour, onClick, children }: TimeSlotCellProps) {
  const { isOver, setNodeRef } = useDroppable({
    id: `slot-${dateStr}-${hour}`,
    data: { type: 'timeSlot', date: dateStr, hour },
  });

  return (
    <div
      ref={setNodeRef}
      className={`h-20 w-full transition-colors cursor-pointer ${
        isOver ? 'bg-blue-50 border border-blue-400 border-dashed' : 'hover:bg-gray-50/50'
      }`}
      onClick={onClick}
    >
      {children}
    </div>
  );
}
