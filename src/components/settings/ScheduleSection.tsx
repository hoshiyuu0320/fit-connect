'use client'

import { useEffect, useState } from 'react'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Clock } from 'lucide-react'
import type { Trainer } from '@/types/trainer'
import type { ScheduleFormItem } from '@/types/schedule'

const DAY_LABELS = ['日曜日', '月曜日', '火曜日', '水曜日', '木曜日', '金曜日', '土曜日']

const DISPLAY_ORDER = [1, 2, 3, 4, 5, 6, 0]

const TIME_OPTIONS = Array.from({ length: 24 }, (_, i) =>
  String(i).padStart(2, '0') + ':00'
)

const DEFAULT_SCHEDULE: ScheduleFormItem[] = DISPLAY_ORDER.map((dow) => ({
  dayOfWeek: dow,
  label: DAY_LABELS[dow],
  isAvailable: false,
  startTime: '09:00',
  endTime: '18:00',
}))

type Props = {
  trainer: Trainer
}

export function ScheduleSection({ trainer }: Props) {
  const [schedules, setSchedules] = useState<ScheduleFormItem[]>(DEFAULT_SCHEDULE)
  const [saving, setSaving] = useState(false)
  const [message, setMessage] = useState<string | null>(null)

  useEffect(() => {
    const fetchSchedules = async () => {
      try {
        const res = await fetch(`/api/trainer-schedules?trainerId=${trainer.id}`)
        const { data } = await res.json()

        if (data && data.length > 0) {
          setSchedules(
            DISPLAY_ORDER.map((dow) => {
              const existing = data.find(
                (s: { day_of_week: number }) => s.day_of_week === dow
              )
              return {
                dayOfWeek: dow,
                label: DAY_LABELS[dow],
                isAvailable: existing?.is_available ?? false,
                startTime: existing?.start_time?.substring(0, 5) ?? '09:00',
                endTime: existing?.end_time?.substring(0, 5) ?? '18:00',
              }
            })
          )
        }
      } catch (error) {
        console.error('スケジュール取得エラー:', error)
      }
    }

    fetchSchedules()
  }, [trainer.id])

  const handleToggle = (dayOfWeek: number) => {
    setSchedules((prev) =>
      prev.map((s) =>
        s.dayOfWeek === dayOfWeek ? { ...s, isAvailable: !s.isAvailable } : s
      )
    )
  }

  const handleTimeChange = (
    dayOfWeek: number,
    field: 'startTime' | 'endTime',
    value: string
  ) => {
    setSchedules((prev) =>
      prev.map((s) =>
        s.dayOfWeek === dayOfWeek ? { ...s, [field]: value } : s
      )
    )
  }

  const handleSave = async () => {
    setSaving(true)
    setMessage(null)

    // バリデーション
    const invalid = schedules.find(
      (s) => s.isAvailable && s.startTime >= s.endTime
    )
    if (invalid) {
      setMessage(`${invalid.label}の開始時刻は終了時刻より前にしてください`)
      setSaving(false)
      return
    }

    try {
      const payload = schedules.map((s) => ({
        day_of_week: s.dayOfWeek,
        start_time: s.startTime + ':00',
        end_time: s.endTime + ':00',
        is_available: s.isAvailable,
      }))

      const res = await fetch('/api/trainer-schedules', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          trainerId: trainer.id,
          schedules: payload,
        }),
      })

      if (!res.ok) throw new Error('保存に失敗しました')

      setMessage('スケジュールを保存しました')
      setTimeout(() => setMessage(null), 3000)
    } catch {
      setMessage('保存に失敗しました。再度お試しください。')
    } finally {
      setSaving(false)
    }
  }

  return (
    <Card>
      <CardHeader className="flex flex-row items-center justify-between">
        <div>
          <CardTitle className="flex items-center gap-2">
            <Clock className="h-5 w-5" />
            対応スケジュール
          </CardTitle>
          <p className="text-sm text-gray-500 mt-1">
            クライアントに表示される対応可能時間帯
          </p>
        </div>
        <Button onClick={handleSave} disabled={saving}>
          {saving ? '保存中...' : '保存'}
        </Button>
      </CardHeader>
      <CardContent className="space-y-3">
        {message && (
          <div className={`text-sm px-3 py-2 rounded ${
            message.includes('失敗') || message.includes('してください')
              ? 'bg-red-50 text-red-600'
              : 'bg-green-50 text-green-600'
          }`}>
            {message}
          </div>
        )}

        {schedules.map((schedule) => (
          <ScheduleRow
            key={schedule.dayOfWeek}
            schedule={schedule}
            onToggle={() => handleToggle(schedule.dayOfWeek)}
            onTimeChange={(field, value) =>
              handleTimeChange(schedule.dayOfWeek, field, value)
            }
          />
        ))}
      </CardContent>
    </Card>
  )
}

function ScheduleRow({
  schedule,
  onToggle,
  onTimeChange,
}: {
  schedule: ScheduleFormItem
  onToggle: () => void
  onTimeChange: (field: 'startTime' | 'endTime', value: string) => void
}) {
  return (
    <div className="flex items-center gap-4 py-2 border-b border-gray-100 last:border-0">
      <span className="w-16 text-sm font-medium text-gray-700">
        {schedule.label}
      </span>

      <button
        type="button"
        onClick={onToggle}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
          schedule.isAvailable ? 'bg-blue-600' : 'bg-gray-300'
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
            schedule.isAvailable ? 'translate-x-6' : 'translate-x-1'
          }`}
        />
      </button>

      <span className={`text-xs w-16 ${
        schedule.isAvailable ? 'text-blue-600' : 'text-gray-400'
      }`}>
        {schedule.isAvailable ? '対応可能' : '休み'}
      </span>

      {schedule.isAvailable ? (
        <div className="flex items-center gap-2">
          <select
            value={schedule.startTime}
            onChange={(e) => onTimeChange('startTime', e.target.value)}
            className="text-sm border border-gray-300 rounded px-2 py-1"
          >
            {TIME_OPTIONS.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
          <span className="text-gray-400">〜</span>
          <select
            value={schedule.endTime}
            onChange={(e) => onTimeChange('endTime', e.target.value)}
            className="text-sm border border-gray-300 rounded px-2 py-1"
          >
            {TIME_OPTIONS.map((t) => (
              <option key={t} value={t}>{t}</option>
            ))}
          </select>
        </div>
      ) : (
        <div className="text-sm text-gray-300">—</div>
      )}
    </div>
  )
}
