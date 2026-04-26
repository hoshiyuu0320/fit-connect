'use client'

import React from 'react'
import { useDraggable } from '@dnd-kit/core'
import { CSS } from '@dnd-kit/utilities'
import { X } from 'lucide-react'
import {
  WorkoutAssignment,
  WORKOUT_CATEGORY_OPTIONS,
  ASSIGNMENT_STATUS_COLORS,
  ASSIGNMENT_STATUS_OPTIONS,
} from '@/types/workout'

interface AssignmentMiniCardProps {
  assignment: WorkoutAssignment
  viewMode: 'day' | 'week' | 'month'
  isDragOverlay?: boolean
  onDelete?: (id: string) => void
}

const PLAN_TYPE_COLORS: Record<string, { bg: string; border: string; text: string }> = {
  session: { bg: '#F0FDFA', border: '#14B8A6', text: '#0D9488' },
  self_guided: { bg: '#EFF6FF', border: '#3B82F6', text: '#1D4ED8' },
}

export const AssignmentMiniCard: React.FC<AssignmentMiniCardProps> = ({
  assignment,
  viewMode,
  isDragOverlay = false,
  onDelete,
}) => {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `assignment-${assignment.id}`,
    data: { type: 'assignment', assignmentId: assignment.id },
    disabled: isDragOverlay,
  })

  const dragStyle = !isDragOverlay
    ? {
        transform: CSS.Translate.toString(transform),
        opacity: isDragging ? 0.5 : 1,
      }
    : {}

  const planType = assignment.plan?.plan_type ?? 'self_guided'
  const statusColors = ASSIGNMENT_STATUS_COLORS[assignment.status]
  const title = assignment.plan?.title ?? '無題'
  const category = assignment.plan?.category as keyof typeof WORKOUT_CATEGORY_OPTIONS | undefined

  const colors = PLAN_TYPE_COLORS[planType] ?? PLAN_TYPE_COLORS['self_guided']

  if (viewMode === 'month') {
    return (
      <div
        ref={!isDragOverlay ? setNodeRef : undefined}
        style={{
          ...dragStyle,
          backgroundColor: colors.bg,
          borderLeft: `3px solid ${colors.border}`,
          color: colors.text,
          borderRadius: '4px',
        }}
        {...(!isDragOverlay ? listeners : {})}
        {...(!isDragOverlay ? attributes : {})}
        className="group/card flex items-center gap-1 px-1.5 py-0.5 mb-0.5 mx-1 text-xs truncate cursor-grab active:cursor-grabbing transition-all relative"
      >
        <span
          className={`flex-shrink-0 w-1.5 h-1.5 rounded-full ${statusColors.dot}`}
        />
        <span className="truncate font-medium leading-tight">{title}</span>
        {onDelete && (
          <button
            onClick={(e) => { e.stopPropagation(); onDelete(assignment.id); }}
            onPointerDown={(e) => e.stopPropagation()}
            className="flex-shrink-0 ml-auto opacity-0 group-hover/card:opacity-100 transition-opacity p-0.5 rounded hover:bg-red-100 text-gray-400 hover:text-red-500"
          >
            <X size={12} />
          </button>
        )}
      </div>
    )
  }

  // Week / Day view
  return (
    <div
      ref={!isDragOverlay ? setNodeRef : undefined}
      style={{
        ...dragStyle,
        backgroundColor: colors.bg,
        borderLeft: `3px solid ${colors.border}`,
        color: colors.text,
        borderRadius: '6px',
      }}
      {...(!isDragOverlay ? listeners : {})}
      {...(!isDragOverlay ? attributes : {})}
      className="group/card flex flex-col gap-0.5 px-2 py-1 mb-1 mx-1 text-xs cursor-grab active:cursor-grabbing transition-all relative"
    >
      {onDelete && (
        <button
          onClick={(e) => { e.stopPropagation(); onDelete(assignment.id); }}
          onPointerDown={(e) => e.stopPropagation()}
          className="absolute top-1 right-1 opacity-0 group-hover/card:opacity-100 transition-opacity p-0.5 rounded hover:bg-red-100 text-gray-400 hover:text-red-500"
        >
          <X size={14} />
        </button>
      )}
      <div className="flex items-center justify-between gap-1 pr-5">
        <span className="font-semibold truncate leading-tight flex-1">{title}</span>
        <span
          className={`flex-shrink-0 inline-flex items-center gap-0.5 px-1 py-0.5 rounded text-[10px] font-medium ${statusColors.bg} ${statusColors.text}`}
        >
          <span className={`w-1.5 h-1.5 rounded-full flex-shrink-0 ${statusColors.dot}`} />
          {ASSIGNMENT_STATUS_OPTIONS[assignment.status]}
        </span>
      </div>
      {category && WORKOUT_CATEGORY_OPTIONS[category] && (
        <span className="text-[10px] opacity-70 truncate">
          {WORKOUT_CATEGORY_OPTIONS[category]}
        </span>
      )}
    </div>
  )
}
