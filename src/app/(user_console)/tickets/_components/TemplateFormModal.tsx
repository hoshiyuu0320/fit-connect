'use client'

import { useState, useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
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
import { TICKET_TYPE_OPTIONS, type TicketTemplate } from '@/types/client'

const templateFormSchema = z.object({
  template_name: z.string().min(1, 'テンプレート名を入力してください'),
  ticket_type: z.string().min(1, '種別を選択してください'),
  total_sessions: z.number({ invalid_type_error: '数値を入力してください' }).min(1, '1回以上を入力してください'),
  valid_months: z.number({ invalid_type_error: '数値を入力してください' }).min(1, '1ヶ月以上を入力してください'),
  is_recurring: z.boolean(),
})

type FormData = z.infer<typeof templateFormSchema>

interface TemplateFormModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  template: TicketTemplate | null
  trainerId: string
  onSaved: () => void
}

export function TemplateFormModal({
  open,
  onOpenChange,
  template,
  trainerId,
  onSaved,
}: TemplateFormModalProps) {
  const [submitting, setSubmitting] = useState(false)

  const form = useForm<FormData>({
    resolver: zodResolver(templateFormSchema),
    defaultValues: {
      template_name: '',
      ticket_type: '',
      total_sessions: 1,
      valid_months: 1,
      is_recurring: false,
    },
  })

  // テンプレートが変わった時にフォームをリセット
  useEffect(() => {
    if (template) {
      form.reset({
        template_name: template.template_name,
        ticket_type: template.ticket_type,
        total_sessions: template.total_sessions,
        valid_months: template.valid_months,
        is_recurring: template.is_recurring,
      })
    } else {
      form.reset({
        template_name: '',
        ticket_type: '',
        total_sessions: 1,
        valid_months: 1,
        is_recurring: false,
      })
    }
  }, [template, form])

  const onSubmit = async (data: FormData) => {
    setSubmitting(true)
    try {
      if (template) {
        // 編集モード
        const res = await fetch(`/api/ticket-templates/${template.id}`, {
          method: 'PUT',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            templateName: data.template_name,
            ticketType: data.ticket_type,
            totalSessions: data.total_sessions,
            validMonths: data.valid_months,
            isRecurring: data.is_recurring,
          }),
        })

        if (!res.ok) {
          throw new Error('テンプレートの更新に失敗しました')
        }
      } else {
        // 作成モード
        const res = await fetch('/api/ticket-templates', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            trainerId,
            templateName: data.template_name,
            ticketType: data.ticket_type,
            totalSessions: data.total_sessions,
            validMonths: data.valid_months,
            isRecurring: data.is_recurring,
          }),
        })

        if (!res.ok) {
          throw new Error('テンプレートの作成に失敗しました')
        }
      }

      onOpenChange(false)
      onSaved()
    } catch (error) {
      console.error('テンプレート保存エラー:', error)
      alert(template ? 'テンプレートの更新に失敗しました' : 'テンプレートの作成に失敗しました')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-lg">
        <DialogHeader>
          <DialogTitle>
            {template ? 'テンプレートを編集' : 'テンプレートを作成'}
          </DialogTitle>
        </DialogHeader>

        <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4 py-4">
          {/* テンプレート名 */}
          <div className="space-y-2">
            <Label htmlFor="template_name">
              テンプレート名 <span className="text-red-500">*</span>
            </Label>
            <Input
              id="template_name"
              {...form.register('template_name')}
              placeholder="例: パーソナル8回券"
              disabled={submitting}
            />
            {form.formState.errors.template_name && (
              <p className="text-sm text-red-500">
                {form.formState.errors.template_name.message}
              </p>
            )}
          </div>

          {/* 種別 */}
          <div className="space-y-2">
            <Label htmlFor="ticket_type">
              種別 <span className="text-red-500">*</span>
            </Label>
            <Select
              value={form.watch('ticket_type')}
              onValueChange={(value) => form.setValue('ticket_type', value)}
              disabled={submitting}
            >
              <SelectTrigger id="ticket_type">
                <SelectValue placeholder="種別を選択" />
              </SelectTrigger>
              <SelectContent>
                {Object.entries(TICKET_TYPE_OPTIONS).map(([key, label]) => (
                  <SelectItem key={key} value={key}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {form.formState.errors.ticket_type && (
              <p className="text-sm text-red-500">
                {form.formState.errors.ticket_type.message}
              </p>
            )}
          </div>

          {/* 合計回数 */}
          <div className="space-y-2">
            <Label htmlFor="total_sessions">
              合計回数 <span className="text-red-500">*</span>
            </Label>
            <Input
              id="total_sessions"
              type="number"
              min="1"
              {...form.register('total_sessions', { valueAsNumber: true })}
              placeholder="8"
              disabled={submitting}
            />
            {form.formState.errors.total_sessions && (
              <p className="text-sm text-red-500">
                {form.formState.errors.total_sessions.message}
              </p>
            )}
          </div>

          {/* 有効月数 */}
          <div className="space-y-2">
            <Label htmlFor="valid_months">
              有効月数 <span className="text-red-500">*</span>
            </Label>
            <Input
              id="valid_months"
              type="number"
              min="1"
              {...form.register('valid_months', { valueAsNumber: true })}
              placeholder="3"
              disabled={submitting}
            />
            {form.formState.errors.valid_months && (
              <p className="text-sm text-red-500">
                {form.formState.errors.valid_months.message}
              </p>
            )}
          </div>

          {/* 月契約チェックボックス */}
          <div className="flex items-center space-x-2">
            <input
              type="checkbox"
              id="is_recurring"
              {...form.register('is_recurring')}
              className="rounded border-gray-300"
              disabled={submitting}
            />
            <Label htmlFor="is_recurring" className="text-sm cursor-pointer">
              月契約（自動発行）にする
            </Label>
          </div>
        </form>

        <DialogFooter>
          <Button
            type="button"
            variant="outline"
            onClick={() => onOpenChange(false)}
            disabled={submitting}
          >
            キャンセル
          </Button>
          <Button
            type="button"
            onClick={form.handleSubmit(onSubmit)}
            disabled={submitting}
          >
            {submitting ? '保存中...' : template ? '更新' : '作成'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
