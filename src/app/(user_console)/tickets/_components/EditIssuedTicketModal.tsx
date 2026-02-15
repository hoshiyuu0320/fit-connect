'use client'

import { useEffect } from 'react'
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
import type { TicketWithClient } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'

const editTicketSchema = z
  .object({
    ticket_name: z.string().min(1, 'チケット名を入力してください'),
    ticket_type: z.string().min(1, '種別を選択してください'),
    total_sessions: z.number({ invalid_type_error: '数値を入力してください' }).min(1, '1回以上を入力してください'),
    remaining_sessions: z.number({ invalid_type_error: '数値を入力してください' }).min(0, '0回以上を入力してください'),
    valid_from: z.string().min(1, '開始日を入力してください'),
    valid_until: z.string().min(1, '終了日を入力してください'),
  })
  .refine((data) => data.remaining_sessions <= data.total_sessions, {
    message: '残回数は合計回数以下にしてください',
    path: ['remaining_sessions'],
  })

type EditTicketFormData = z.infer<typeof editTicketSchema>

interface EditIssuedTicketModalProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  ticket: TicketWithClient | null
  onUpdated: () => void
}

export function EditIssuedTicketModal({
  open,
  onOpenChange,
  ticket,
  onUpdated,
}: EditIssuedTicketModalProps) {
  const {
    register,
    handleSubmit,
    reset,
    setValue,
    watch,
    formState: { errors, isSubmitting },
  } = useForm<EditTicketFormData>({
    resolver: zodResolver(editTicketSchema),
  })

  const ticketType = watch('ticket_type')

  // ticketが変更されたら、フォームをリセット
  useEffect(() => {
    if (ticket) {
      reset({
        ticket_name: ticket.ticket_name,
        ticket_type: ticket.ticket_type,
        total_sessions: ticket.total_sessions,
        remaining_sessions: ticket.remaining_sessions,
        valid_from: ticket.valid_from.split('T')[0],
        valid_until: ticket.valid_until.split('T')[0],
      })
    }
  }, [ticket, reset])

  const onSubmit = async (data: EditTicketFormData) => {
    if (!ticket) return

    try {
      const response = await fetch(`/api/tickets/${ticket.id}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          ticketName: data.ticket_name,
          ticketType: data.ticket_type,
          totalSessions: data.total_sessions,
          remainingSessions: data.remaining_sessions,
          validFrom: data.valid_from,
          validUntil: data.valid_until,
        }),
      })

      if (!response.ok) {
        throw new Error('チケット更新に失敗しました')
      }

      onUpdated()
    } catch (error) {
      console.error('チケット更新エラー:', error)
      alert('更新に失敗しました')
    }
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="max-w-md">
        <DialogHeader>
          <DialogTitle>チケット編集</DialogTitle>
        </DialogHeader>

        <form onSubmit={handleSubmit(onSubmit)} className="space-y-4">
          {/* チケット名 */}
          <div className="space-y-2">
            <Label htmlFor="ticket_name">チケット名</Label>
            <Input id="ticket_name" {...register('ticket_name')} />
            {errors.ticket_name && (
              <p className="text-sm text-rose-600">{errors.ticket_name.message}</p>
            )}
          </div>

          {/* 種別 */}
          <div className="space-y-2">
            <Label>種別</Label>
            <Select value={ticketType} onValueChange={(value) => setValue('ticket_type', value)}>
              <SelectTrigger>
                <SelectValue placeholder="種別を選択" />
              </SelectTrigger>
              <SelectContent className="bg-white">
                {Object.entries(TICKET_TYPE_OPTIONS).map(([key, label]) => (
                  <SelectItem key={key} value={key}>
                    {label}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
            {errors.ticket_type && (
              <p className="text-sm text-rose-600">{errors.ticket_type.message}</p>
            )}
          </div>

          {/* 合計回数 */}
          <div className="space-y-2">
            <Label htmlFor="total_sessions">合計回数</Label>
            <Input
              id="total_sessions"
              type="number"
              {...register('total_sessions', { valueAsNumber: true })}
            />
            {errors.total_sessions && (
              <p className="text-sm text-rose-600">{errors.total_sessions.message}</p>
            )}
          </div>

          {/* 残回数 */}
          <div className="space-y-2">
            <Label htmlFor="remaining_sessions">残回数</Label>
            <Input
              id="remaining_sessions"
              type="number"
              {...register('remaining_sessions', { valueAsNumber: true })}
            />
            {errors.remaining_sessions && (
              <p className="text-sm text-rose-600">{errors.remaining_sessions.message}</p>
            )}
          </div>

          {/* 開始日 */}
          <div className="space-y-2">
            <Label htmlFor="valid_from">開始日</Label>
            <Input id="valid_from" type="date" {...register('valid_from')} />
            {errors.valid_from && (
              <p className="text-sm text-rose-600">{errors.valid_from.message}</p>
            )}
          </div>

          {/* 終了日 */}
          <div className="space-y-2">
            <Label htmlFor="valid_until">終了日</Label>
            <Input id="valid_until" type="date" {...register('valid_until')} />
            {errors.valid_until && (
              <p className="text-sm text-rose-600">{errors.valid_until.message}</p>
            )}
          </div>

          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              キャンセル
            </Button>
            <Button type="submit" disabled={isSubmitting}>
              {isSubmitting ? '更新中...' : '更新'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
