"use client"

import { useState } from 'react'
import { useDraggable } from '@dnd-kit/core'
import { CSS } from '@dnd-kit/utilities'
import { WORKOUT_CATEGORY_OPTIONS, PLAN_TYPE_COLORS, type WorkoutPlan } from '@/types/workout'
import { PlanFormModal } from './PlanFormModal'
import { ExerciseListModal } from './ExerciseListModal'

interface DraggableTemplateCardProps {
  template: WorkoutPlan
  onEdit: (plan: WorkoutPlan) => void
  onDelete: (planId: string) => void
  onViewExercises: (plan: WorkoutPlan) => void
}

function DraggableTemplateCard({
  template,
  onEdit,
  onDelete,
  onViewExercises,
}: DraggableTemplateCardProps) {
  const [menuOpen, setMenuOpen] = useState(false)
  const { attributes, listeners, setNodeRef, transform, isDragging } = useDraggable({
    id: `template-${template.id}`,
    data: { type: 'template', planId: template.id },
  })

  const style = {
    transform: CSS.Translate.toString(transform),
    opacity: isDragging ? 0.5 : 1,
  }

  const categoryLabel =
    template.category in WORKOUT_CATEGORY_OPTIONS
      ? WORKOUT_CATEGORY_OPTIONS[template.category as keyof typeof WORKOUT_CATEGORY_OPTIONS]
      : template.category

  return (
    <div
      ref={setNodeRef}
      style={style}
      className="relative p-3 bg-gray-50 border rounded-lg hover:shadow-md transition-shadow group"
    >
      {/* ドラッグハンドル部分 */}
      <div
        {...listeners}
        {...attributes}
        className="cursor-grab active:cursor-grabbing"
      >
        <div className="flex items-center gap-2 pr-6">
          <span className="font-bold text-gray-800 text-sm">{template.title}</span>
          {template.plan_type && (
            <span className={`inline-flex items-center px-1.5 py-0.5 rounded text-[10px] font-semibold ${PLAN_TYPE_COLORS[template.plan_type].bg} ${PLAN_TYPE_COLORS[template.plan_type].text}`}>
              {PLAN_TYPE_COLORS[template.plan_type].label}
            </span>
          )}
        </div>
        <div className="flex gap-2 mt-1 text-xs text-gray-500">
          <span className="bg-white border px-1.5 py-0.5 rounded">{categoryLabel}</span>
          <span>{template.exercise_count ?? 0} 種目</span>
          {template.estimated_minutes && <span>約 {template.estimated_minutes} 分</span>}
        </div>
      </div>

      {/* メニューボタン */}
      <div className="absolute top-2 right-2">
        <button
          onClick={() => setMenuOpen((v) => !v)}
          className="text-gray-400 hover:text-gray-600 text-base leading-none w-6 h-6 flex items-center justify-center rounded hover:bg-gray-200"
        >
          ...
        </button>
        {menuOpen && (
          <div className="absolute right-0 top-7 z-20 bg-white border rounded-lg shadow-lg py-1 w-36">
            <button
              onClick={() => {
                setMenuOpen(false)
                onViewExercises(template)
              }}
              className="w-full text-left px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50"
            >
              種目を見る
            </button>
            <button
              onClick={() => {
                setMenuOpen(false)
                onEdit(template)
              }}
              className="w-full text-left px-3 py-1.5 text-sm text-gray-700 hover:bg-gray-50"
            >
              編集
            </button>
            <button
              onClick={() => {
                setMenuOpen(false)
                onDelete(template.id)
              }}
              className="w-full text-left px-3 py-1.5 text-sm text-red-600 hover:bg-red-50"
            >
              削除
            </button>
          </div>
        )}
      </div>
    </div>
  )
}

interface TemplatePanelProps {
  trainerId: string
  templates: WorkoutPlan[]
  onRefetch: () => void
}

export function TemplatePanel({ trainerId, templates, onRefetch }: TemplatePanelProps) {
  const [searchQuery, setSearchQuery] = useState('')
  const [formModalOpen, setFormModalOpen] = useState(false)
  const [editingPlan, setEditingPlan] = useState<WorkoutPlan | null>(null)
  const [exerciseModalOpen, setExerciseModalOpen] = useState(false)
  const [viewingPlan, setViewingPlan] = useState<WorkoutPlan | null>(null)

  const filtered = templates.filter((t) =>
    t.title.toLowerCase().includes(searchQuery.toLowerCase())
  )

  const handleDelete = async (planId: string) => {
    if (!confirm('このテンプレートを削除しますか？')) return
    try {
      const res = await fetch(`/api/workout-plans/${planId}`, { method: 'DELETE' })
      if (res.ok) onRefetch()
    } catch (error) {
      console.error('削除エラー:', error)
    }
  }

  const handleEdit = (plan: WorkoutPlan) => {
    setEditingPlan(plan)
    setFormModalOpen(true)
  }

  const handleViewExercises = (plan: WorkoutPlan) => {
    setViewingPlan(plan)
    setExerciseModalOpen(true)
  }

  const handleCreateNew = () => {
    setEditingPlan(null)
    setFormModalOpen(true)
  }

  return (
    <>
      <aside className="w-80 bg-white border-r flex flex-col h-full">
        <div className="p-4 border-b space-y-2">
          <h2 className="text-sm font-bold text-gray-500">テンプレート</h2>
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="検索..."
            className="w-full p-2 border rounded-md text-sm focus:outline-none focus:ring-1 focus:ring-blue-400"
          />
          <button
            onClick={handleCreateNew}
            className="w-full py-1.5 text-sm rounded-md transition-colors font-medium"
            style={{ backgroundColor: '#fff', color: '#0F172A', border: '1px solid #0F172A' }}
            onMouseEnter={(e) => { e.currentTarget.style.backgroundColor = '#0F172A'; e.currentTarget.style.color = '#fff'; }}
            onMouseLeave={(e) => { e.currentTarget.style.backgroundColor = '#fff'; e.currentTarget.style.color = '#0F172A'; }}
          >
            + テンプレート追加
          </button>
        </div>

        <div className="flex-1 overflow-y-auto p-4 space-y-3">
          {filtered.length === 0 ? (
            <p className="text-sm text-gray-400 text-center py-4">
              {searchQuery ? '該当なし' : 'テンプレートがありません'}
            </p>
          ) : (
            filtered.map((template) => (
              <DraggableTemplateCard
                key={template.id}
                template={template}
                onEdit={handleEdit}
                onDelete={handleDelete}
                onViewExercises={handleViewExercises}
              />
            ))
          )}
        </div>
      </aside>

      <PlanFormModal
        open={formModalOpen}
        onClose={() => setFormModalOpen(false)}
        trainerId={trainerId}
        editingPlan={editingPlan}
        onSaved={onRefetch}
      />

      <ExerciseListModal
        open={exerciseModalOpen}
        onClose={() => setExerciseModalOpen(false)}
        plan={viewingPlan}
      />
    </>
  )
}
