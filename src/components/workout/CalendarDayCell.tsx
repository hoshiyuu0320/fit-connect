"use client"

import { useDroppable, useDraggable } from '@dnd-kit/core'
import { CSS } from '@dnd-kit/utilities'
import { format, isToday } from 'date-fns'
import { ja } from 'date-fns/locale'
import { ASSIGNMENT_STATUS_COLORS, ASSIGNMENT_STATUS_OPTIONS, PLAN_TYPE_COLORS, WORKOUT_CATEGORY_OPTIONS, type WorkoutAssignment } from '@/types/workout'

interface AssignmentCardProps {
  assignment: WorkoutAssignment
  onDelete: (id: string) => void
}

function AssignmentCard({ assignment, onDelete }: AssignmentCardProps) {
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `assignment-${assignment.id}`,
    data: { type: 'assignment', assignmentId: assignment.id },
  })

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.4 : 1,
  }

  const isSession = assignment.plan?.plan_type === 'session'
  const planType = assignment.plan?.plan_type || 'session'
  const typeColors = PLAN_TYPE_COLORS[planType]
  const status = assignment.status
  const statusColors = ASSIGNMENT_STATUS_COLORS[status]
  const statusLabel = ASSIGNMENT_STATUS_OPTIONS[status]

  const categoryLabel = assignment.plan?.category
    ? WORKOUT_CATEGORY_OPTIONS[assignment.plan.category as keyof typeof WORKOUT_CATEGORY_OPTIONS] || assignment.plan.category
    : null

  return (
    <div
      ref={setNodeRef}
      style={style}
      {...listeners}
      {...attributes}
      className={`group bg-white rounded-lg border ${typeColors.borderColor} ${typeColors.hoverBorder} shadow-sm hover:shadow-md transition-all overflow-hidden cursor-grab active:cursor-grabbing`}
    >
      {/* ヘッダー */}
      <div className={`${typeColors.headerBg} text-white px-3 py-1.5 flex items-center justify-between`}>
        <div className="flex items-center gap-1.5">
          <span className="text-xs font-bold leading-none">{typeColors.label}</span>
        </div>
        <button
          onPointerDown={(e) => e.stopPropagation()}
          onClick={() => onDelete(assignment.id)}
          className="text-white/70 hover:text-white w-5 h-5 flex items-center justify-center rounded transition-colors text-sm"
        >
          ✕
        </button>
      </div>

      {/* ボディ */}
      <div className="p-3">
        {!isSession && (
          <span className={`inline-flex items-center gap-1 mb-1.5 px-2 py-0.5 rounded text-[11px] font-medium ${statusColors.bg} ${statusColors.text}`}>
            {statusColors.icon} {statusLabel}
          </span>
        )}
        <h3 className="font-bold text-gray-800 text-sm mb-1 line-clamp-2">
          {assignment.plan?.title ?? 'プラン'}
        </h3>
        {!isSession && assignment.plan?.estimated_minutes && (
          <div className="text-xs text-gray-500 mt-1">
            約{assignment.plan.estimated_minutes}分
          </div>
        )}
      </div>

      {/* フッター（タグ） */}
      {categoryLabel && (
        <div className="px-3 pb-2 flex flex-wrap gap-1">
          <span className="text-[10px] text-gray-500 bg-gray-100 px-1.5 py-0.5 rounded border border-gray-200">
            #{categoryLabel}
          </span>
        </div>
      )}
    </div>
  )
}

interface CalendarDayCellProps {
  date: Date
  assignments: WorkoutAssignment[]
  onDeleteAssignment: (id: string) => void
}

export function CalendarDayCell({
  date,
  assignments,
  onDeleteAssignment,
}: CalendarDayCellProps) {
  const dateStr = format(date, 'yyyy-MM-dd')
  const { isOver, setNodeRef } = useDroppable({
    id: `day-${dateStr}`,
    data: { type: 'day', date: dateStr },
  })

  const dayLabel = format(date, 'E', { locale: ja })
  const dateLabel = format(date, 'd')
  const today = isToday(date)

  return (
    <div
      ref={setNodeRef}
      className={`flex flex-col bg-gray-100/50 rounded-xl p-2 border-2 transition-colors min-h-[200px] ${
        isOver ? 'border-blue-400 bg-blue-50' : 'border-transparent hover:border-gray-200'
      }`}
    >
      {/* 日付ヘッダー */}
      <div className="text-center mb-3 pb-2 border-b border-gray-200">
        <p className="text-xs text-gray-500 font-medium">{dayLabel}</p>
        <p
          className={`text-lg font-bold leading-tight ${
            today
              ? 'text-blue-600 bg-blue-100 rounded-full w-8 h-8 flex items-center justify-center mx-auto'
              : 'text-gray-700'
          }`}
        >
          {dateLabel}
        </p>
      </div>

      {/* アサインメントカード */}
      <div className="flex-1 space-y-2">
        {assignments.map((assignment) => (
          <AssignmentCard
            key={assignment.id}
            assignment={assignment}
            onDelete={onDeleteAssignment}
          />
        ))}

        {assignments.length === 0 && (
          <div className="flex-1 flex items-center justify-center min-h-[80px]">
            <p className="text-xs text-gray-300 text-center">
              ドロップして<br />追加
            </p>
          </div>
        )}
      </div>
    </div>
  )
}
