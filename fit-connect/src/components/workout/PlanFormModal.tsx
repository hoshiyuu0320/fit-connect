"use client"

import { useEffect } from 'react'
import { useForm, useFieldArray } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import {
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
} from '@/components/ui/select'
import { WORKOUT_CATEGORY_OPTIONS, PLAN_TYPE_OPTIONS, type WorkoutPlan } from '@/types/workout'

const exerciseSchema = z.object({
  name: z.string().min(1, '種目名は必須です'),
  sets: z.number().min(1, 'セット数は1以上'),
  reps: z.number().optional(),
  weight: z.number().optional(),
  memo: z.string().optional(),
})

const formSchema = z.object({
  title: z.string().min(1, 'タイトルは必須です'),
  description: z.string().optional(),
  category: z.string().optional(),
  planType: z.enum(['session', 'self_guided']),
  estimatedMinutes: z.number().optional(),
  exercises: z.array(exerciseSchema).min(1, '種目を1つ以上追加してください'),
})

type FormData = z.infer<typeof formSchema>

interface PlanFormModalProps {
  open: boolean
  onClose: () => void
  trainerId: string
  editingPlan?: WorkoutPlan | null
  onSaved: () => void
}

export function PlanFormModal({
  open,
  onClose,
  trainerId,
  editingPlan,
  onSaved,
}: PlanFormModalProps) {
  const isEditing = !!editingPlan

  const form = useForm<FormData>({
    resolver: zodResolver(formSchema),
    defaultValues: {
      title: '',
      description: '',
      category: 'other',
      planType: 'session' as const,
      estimatedMinutes: undefined,
      exercises: [{ name: '', sets: 3, reps: undefined, weight: undefined, memo: '' }],
    },
  })

  const { fields, append, remove } = useFieldArray({
    control: form.control,
    name: 'exercises',
  })

  useEffect(() => {
    if (open && editingPlan) {
      form.reset({
        title: editingPlan.title,
        description: editingPlan.description ?? '',
        category: editingPlan.category,
        planType: editingPlan.plan_type || 'session',
        estimatedMinutes: editingPlan.estimated_minutes ?? undefined,
        exercises:
          editingPlan.exercises && editingPlan.exercises.length > 0
            ? editingPlan.exercises.map((ex) => ({
                name: ex.name,
                sets: ex.sets,
                reps: ex.reps ?? undefined,
                weight: ex.weight ?? undefined,
                memo: ex.memo ?? '',
              }))
            : [{ name: '', sets: 3, reps: undefined, weight: undefined, memo: '' }],
      })
    } else if (open && !editingPlan) {
      form.reset({
        title: '',
        description: '',
        category: 'other',
        planType: 'session' as const,
        estimatedMinutes: undefined,
        exercises: [{ name: '', sets: 3, reps: undefined, weight: undefined, memo: '' }],
      })
    }
  }, [open, editingPlan, form])

  const onSubmit = async (data: FormData) => {
    try {
      const payload = {
        trainerId,
        title: data.title,
        description: data.description || undefined,
        category: data.category,
        planType: data.planType,
        estimatedMinutes: data.estimatedMinutes,
        exercises: data.exercises.map((ex, index) => ({
          name: ex.name,
          sets: ex.sets,
          reps: ex.reps,
          weight: ex.weight,
          memo: ex.memo,
          orderIndex: index,
        })),
      }

      const url = isEditing
        ? `/api/workout-plans/${editingPlan!.id}`
        : '/api/workout-plans'
      const method = isEditing ? 'PUT' : 'POST'

      const res = await fetch(url, {
        method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload),
      })

      if (!res.ok) throw new Error('保存に失敗しました')

      onSaved()
      onClose()
    } catch (error) {
      console.error('プラン保存エラー:', error)
    }
  }

  return (
    <Dialog open={open} onOpenChange={(v) => !v && onClose()}>
      <DialogContent className="max-w-2xl max-h-[90vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>
            {isEditing ? 'テンプレート編集' : '新規テンプレート作成'}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-5">
          {/* タイトル */}
          <div className="space-y-1">
            <Label htmlFor="title">タイトル *</Label>
            <Input
              id="title"
              {...form.register('title')}
              placeholder="例: 胸・三頭筋 (初心者)"
            />
            {form.formState.errors.title && (
              <p className="text-xs text-red-500">{form.formState.errors.title.message}</p>
            )}
          </div>

          {/* 説明 */}
          <div className="space-y-1">
            <Label htmlFor="description">説明</Label>
            <Input
              id="description"
              {...form.register('description')}
              placeholder="任意の説明"
            />
          </div>

          {/* プラン種別 */}
          <div className="space-y-1">
            <Label>プラン種別 *</Label>
            <div className="flex gap-3">
              {Object.entries(PLAN_TYPE_OPTIONS).map(([key, label]) => {
                const isSelected = form.watch('planType') === key
                return (
                  <button
                    key={key}
                    type="button"
                    onClick={() => form.setValue('planType', key as 'session' | 'self_guided')}
                    className={`flex-1 py-2 px-3 rounded-lg border-2 text-sm font-medium transition-colors ${
                      isSelected
                        ? key === 'session'
                          ? 'border-blue-500 bg-blue-50 text-blue-700'
                          : 'border-teal-500 bg-teal-50 text-teal-700'
                        : 'border-gray-200 bg-white text-gray-600 hover:border-gray-300'
                    }`}
                  >
                    {key === 'session' ? '🏋️ ' : '📱 '}{label}
                  </button>
                )
              })}
            </div>
          </div>

          {/* カテゴリ + 推定時間 */}
          <div className="grid grid-cols-2 gap-4">
            <div className="space-y-1">
              <Label>カテゴリ</Label>
              <Select
                value={form.watch('category')}
                onValueChange={(v) => form.setValue('category', v)}
              >
                <SelectTrigger>
                  <SelectValue placeholder="カテゴリ選択" />
                </SelectTrigger>
                <SelectContent>
                  {Object.entries(WORKOUT_CATEGORY_OPTIONS).map(([key, label]) => (
                    <SelectItem key={key} value={key}>
                      {label}
                    </SelectItem>
                  ))}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1">
              <Label htmlFor="estimatedMinutes">推定時間（分）</Label>
              <Input
                id="estimatedMinutes"
                type="number"
                {...form.register('estimatedMinutes', { valueAsNumber: true })}
                placeholder="例: 45"
              />
            </div>
          </div>

          {/* 種目リスト */}
          <div className="space-y-3">
            <Label>種目</Label>

            {fields.map((field, index) => (
              <div
                key={field.id}
                className="bg-gray-50 rounded-lg p-4 space-y-3 relative"
              >
                <button
                  type="button"
                  onClick={() => remove(index)}
                  className="absolute top-3 right-3 text-gray-400 hover:text-red-500 text-sm"
                >
                  x
                </button>
                <div className="space-y-1">
                  <Label>種目名 *</Label>
                  <Input
                    {...form.register(`exercises.${index}.name`)}
                    placeholder="例: ベンチプレス"
                  />
                  {form.formState.errors.exercises?.[index]?.name && (
                    <p className="text-xs text-red-500">
                      {form.formState.errors.exercises[index]?.name?.message}
                    </p>
                  )}
                </div>
                <div className="grid grid-cols-3 gap-3">
                  <div className="space-y-1">
                    <Label>セット数 *</Label>
                    <Input
                      type="number"
                      {...form.register(`exercises.${index}.sets`, { valueAsNumber: true })}
                      placeholder="3"
                    />
                  </div>
                  <div className="space-y-1">
                    <Label>回数</Label>
                    <Input
                      type="number"
                      {...form.register(`exercises.${index}.reps`, { valueAsNumber: true })}
                      placeholder="10"
                    />
                  </div>
                  <div className="space-y-1">
                    <Label>重量 (kg)</Label>
                    <Input
                      type="number"
                      step="0.5"
                      {...form.register(`exercises.${index}.weight`, { valueAsNumber: true })}
                      placeholder="60"
                    />
                  </div>
                </div>
                <div className="space-y-1">
                  <Label>メモ</Label>
                  <Input
                    {...form.register(`exercises.${index}.memo`)}
                    placeholder="フォームのポイントなど"
                  />
                </div>
              </div>
            ))}

            <button
              type="button"
              onClick={() =>
                append({ name: '', sets: 3, reps: undefined, weight: undefined, memo: '' })
              }
              className="w-full py-2.5 border-2 border-dashed border-gray-300 rounded-lg text-sm text-blue-600 hover:border-blue-400 hover:bg-blue-50 transition-colors"
            >
              + 種目追加
            </button>

            {form.formState.errors.exercises?.root && (
              <p className="text-xs text-red-500">
                {form.formState.errors.exercises.root.message}
              </p>
            )}
          </div>

          <div className="flex justify-end gap-3 pt-2">
            <Button type="button" variant="outline" onClick={onClose}>
              キャンセル
            </Button>
            <Button
              type="submit"
              disabled={form.formState.isSubmitting}
              className="bg-blue-600 text-white hover:bg-blue-700"
            >
              {form.formState.isSubmitting ? '保存中...' : '保存'}
            </Button>
          </div>
        </form>
      </DialogContent>
    </Dialog>
  )
}
