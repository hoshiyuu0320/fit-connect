"use client"

import { useEffect } from 'react'
import { useForm, useFieldArray } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { toast } from 'sonner'
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
import {
  buildPlanPayload,
  planFormSchema,
  toOptionalNumber,
  type PlanFormValues,
} from '@/lib/workout/planForm'

interface PlanFormModalProps {
  open: boolean
  onClose: () => void
  editingPlan?: WorkoutPlan | null
  onSaved: () => void
}

export function PlanFormModal({
  open,
  onClose,
  editingPlan,
  onSaved,
}: PlanFormModalProps) {
  const isEditing = !!editingPlan

  const form = useForm<PlanFormValues>({
    resolver: zodResolver(planFormSchema),
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

  const onSubmit = async (data: PlanFormValues) => {
    try {
      const payload = buildPlanPayload(data)

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
      toast.error('プランを保存できませんでした。もう一度お試しください')
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
                {...form.register('estimatedMinutes', { setValueAs: toOptionalNumber })}
                placeholder="例: 45"
              />
              {form.formState.errors.estimatedMinutes && (
                <p className="text-xs text-red-500">
                  {form.formState.errors.estimatedMinutes.message}
                </p>
              )}
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
                      {...form.register(`exercises.${index}.sets`, { setValueAs: toOptionalNumber })}
                      placeholder="3"
                    />
                    {form.formState.errors.exercises?.[index]?.sets && (
                      <p className="text-xs text-red-500">
                        {form.formState.errors.exercises[index]?.sets?.message}
                      </p>
                    )}
                  </div>
                  <div className="space-y-1">
                    <Label>回数</Label>
                    <Input
                      type="number"
                      {...form.register(`exercises.${index}.reps`, { setValueAs: toOptionalNumber })}
                      placeholder="10"
                    />
                    {form.formState.errors.exercises?.[index]?.reps && (
                      <p className="text-xs text-red-500">
                        {form.formState.errors.exercises[index]?.reps?.message}
                      </p>
                    )}
                  </div>
                  <div className="space-y-1">
                    <Label>重量 (kg)</Label>
                    <Input
                      type="number"
                      step="0.5"
                      {...form.register(`exercises.${index}.weight`, { setValueAs: toOptionalNumber })}
                      placeholder="60"
                    />
                    {form.formState.errors.exercises?.[index]?.weight && (
                      <p className="text-xs text-red-500">
                        {form.formState.errors.exercises[index]?.weight?.message}
                      </p>
                    )}
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
