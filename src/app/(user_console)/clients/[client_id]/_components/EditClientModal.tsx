'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import * as z from 'zod'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Textarea } from '@/components/ui/textarea'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { ClientDetail, GENDER_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'

const editClientSchema = z.object({
  age: z.number().min(1, '年齢を入力してください').max(120, '120歳以下を入力してください'),
  gender: z.enum(['male', 'female', 'other']),
  occupation: z.string().optional(),
  height: z.number().min(50, '50cm以上を入力してください').max(250, '250cm以下を入力してください'),
  target_weight: z.number().min(20, '20kg以上を入力してください').max(300, '300kg以下を入力してください'),
  purpose: z.enum(['diet', 'contest', 'body_make', 'health_improvement', 'mental_improvement', 'performance_improvement']),
  goal_description: z.string().optional(),
  goal_deadline: z.string().optional(),
})

type EditClientFormValues = z.infer<typeof editClientSchema>

type EditClientModalProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  client: ClientDetail
  onUpdated: () => void
}

export default function EditClientModal({ open, onOpenChange, client, onUpdated }: EditClientModalProps) {
  const [isLoading, setIsLoading] = useState(false)

  const { register, handleSubmit, setValue, formState: { errors } } = useForm<EditClientFormValues>({
    resolver: zodResolver(editClientSchema),
    defaultValues: {
      age: client.age,
      gender: client.gender,
      occupation: client.occupation || '',
      height: client.height,
      target_weight: client.target_weight,
      purpose: client.purpose,
      goal_description: client.goal_description || '',
      goal_deadline: client.goal_deadline || '',
    },
  })

  const onSubmit = async (data: EditClientFormValues) => {
    setIsLoading(true)
    try {
      const res = await fetch(`/api/clients/${client.client_id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          age: data.age,
          gender: data.gender,
          occupation: data.occupation || null,
          height: data.height,
          target_weight: data.target_weight,
          purpose: data.purpose,
          goal_description: data.goal_description || null,
          goal_deadline: data.goal_deadline || null,
        }),
      })
      if (!res.ok) throw new Error('更新に失敗しました')
      onUpdated()
      onOpenChange(false)
    } catch (error) {
      console.error('クライアント更新エラー:', error)
      alert('更新に失敗しました')
    } finally {
      setIsLoading(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] bg-white">
        <DialogHeader>
          <DialogTitle>クライアント情報編集</DialogTitle>
        </DialogHeader>
        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* 基本情報 */}
          <div>
            <h3 className="text-sm font-semibold text-gray-700 mb-3">基本情報</h3>
            <div className="space-y-4">
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="age">年齢</Label>
                  <Input
                    id="age"
                    type="number"
                    {...register('age', { valueAsNumber: true })}
                  />
                  {errors.age && <p className="text-sm text-red-500">{errors.age.message}</p>}
                </div>
                <div className="space-y-2">
                  <Label htmlFor="gender">性別</Label>
                  <Select
                    onValueChange={(value) => setValue('gender', value as 'male' | 'female' | 'other')}
                    defaultValue={client.gender}
                  >
                    <SelectTrigger>
                      <SelectValue />
                    </SelectTrigger>
                    <SelectContent className="bg-white">
                      {Object.entries(GENDER_OPTIONS).map(([key, label]) => (
                        <SelectItem key={key} value={key}>
                          {label}
                        </SelectItem>
                      ))}
                    </SelectContent>
                  </Select>
                  {errors.gender && <p className="text-sm text-red-500">{errors.gender.message}</p>}
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="occupation">職業</Label>
                <Input
                  id="occupation"
                  type="text"
                  placeholder="例: 会社員"
                  {...register('occupation')}
                />
              </div>
            </div>
          </div>

          {/* 身体情報 */}
          <div className="border-t pt-4">
            <h3 className="text-sm font-semibold text-gray-700 mb-3">身体情報</h3>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="height">身長 (cm)</Label>
                <Input
                  id="height"
                  type="number"
                  step="0.1"
                  {...register('height', { valueAsNumber: true })}
                />
                {errors.height && <p className="text-sm text-red-500">{errors.height.message}</p>}
              </div>
              <div className="space-y-2">
                <Label htmlFor="target_weight">目標体重 (kg)</Label>
                <Input
                  id="target_weight"
                  type="number"
                  step="0.1"
                  {...register('target_weight', { valueAsNumber: true })}
                />
                {errors.target_weight && <p className="text-sm text-red-500">{errors.target_weight.message}</p>}
              </div>
            </div>
          </div>

          {/* 目標設定 */}
          <div className="border-t pt-4">
            <h3 className="text-sm font-semibold text-gray-700 mb-3">目標設定</h3>
            <div className="space-y-4">
              <div className="space-y-2">
                <Label htmlFor="purpose">目的</Label>
                <Select
                  onValueChange={(value) => setValue('purpose', value as EditClientFormValues['purpose'])}
                  defaultValue={client.purpose}
                >
                  <SelectTrigger>
                    <SelectValue />
                  </SelectTrigger>
                  <SelectContent className="bg-white">
                    {Object.entries(PURPOSE_OPTIONS).map(([key, label]) => (
                      <SelectItem key={key} value={key}>
                        {label}
                      </SelectItem>
                    ))}
                  </SelectContent>
                </Select>
                {errors.purpose && <p className="text-sm text-red-500">{errors.purpose.message}</p>}
              </div>
              <div className="space-y-2">
                <Label htmlFor="goal_description">目標説明</Label>
                <Textarea
                  id="goal_description"
                  placeholder="具体的な目標を入力してください"
                  className="min-h-[80px]"
                  {...register('goal_description')}
                />
              </div>
              <div className="space-y-2">
                <Label htmlFor="goal_deadline">目標期日</Label>
                <Input
                  id="goal_deadline"
                  type="date"
                  {...register('goal_deadline')}
                />
              </div>
            </div>
          </div>

          <DialogFooter>
            <div className="flex gap-2 pt-4">
              <Button type="button" variant="outline" onClick={() => onOpenChange(false)} disabled={isLoading}>
                キャンセル
              </Button>
              <Button type="submit" disabled={isLoading}>
                {isLoading ? '保存中...' : '保存'}
              </Button>
            </div>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
