'use client'

import { useMemo, useState } from 'react'
import { format } from 'date-fns'
import { AlertCircle, Banknote, Loader2, Wallet } from 'lucide-react'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
} from '@/components/ui/alert-dialog'
import type { Client } from '@/types/client'
import type { PaymentWithClient } from '@/types/payment'
import { PAYMENT_METHOD_LABELS } from '@/types/payment'
import { MarkPaidModal } from './MarkPaidModal'
import { AddPaymentModal } from './AddPaymentModal'

interface PaymentListProps {
  payments: PaymentWithClient[]
  clients: Client[]
  loadFailed: boolean
  onRefetch: () => void
}

type PaymentFilter = 'unpaid' | 'paid' | 'all'

type DisplayStatus = 'unpaid' | 'overdue' | 'paid' | 'refunded'

const STATUS_CONFIG: Record<
  DisplayStatus,
  { label: string; bg: string; text: string; border: string; dot: string }
> = {
  unpaid: {
    label: '未払い',
    bg: '#F8FAFC',
    text: '#64748B',
    border: '#E2E8F0',
    dot: '#94A3B8',
  },
  overdue: {
    label: '期限超過',
    bg: '#FFFBEB',
    text: '#B45309',
    border: '#FDE68A',
    dot: '#B45309',
  },
  paid: {
    label: '支払済み',
    bg: '#F0FDFA',
    text: '#14B8A6',
    border: '#CCFBF1',
    dot: '#14B8A6',
  },
  refunded: {
    label: '返金',
    bg: '#F1F5F9',
    text: '#475569',
    border: '#E2E8F0',
    dot: '#94A3B8',
  },
}

// 期日超過日数を計算（期日なし・未超過は0）
function getOverdueDays(dueDate: string | null): number {
  if (!dueDate) return 0
  const today = new Date()
  today.setHours(0, 0, 0, 0)
  const due = new Date(dueDate)
  due.setHours(0, 0, 0, 0)
  const diff = Math.floor((today.getTime() - due.getTime()) / (1000 * 60 * 60 * 24))
  return diff > 0 ? diff : 0
}

// 表示用ステータス（DBのstatusはunpaidのまま、期日超過はUI側で導出）
function getDisplayStatus(payment: PaymentWithClient): {
  status: DisplayStatus
  overdueDays: number
} {
  if (payment.status === 'paid') return { status: 'paid', overdueDays: 0 }
  if (payment.status === 'refunded') return { status: 'refunded', overdueDays: 0 }
  const overdueDays = getOverdueDays(payment.due_date)
  if (overdueDays > 0) return { status: 'overdue', overdueDays }
  return { status: 'unpaid', overdueDays: 0 }
}

function isUnpaidStatus(payment: PaymentWithClient): boolean {
  return payment.status === 'unpaid' || payment.status === 'overdue'
}

function formatYen(amount: number): string {
  return `¥${amount.toLocaleString('ja-JP')}`
}

export function PaymentList({ payments, clients, loadFailed, onRefetch }: PaymentListProps) {
  const [filter, setFilter] = useState<PaymentFilter>('unpaid')
  const [addOpen, setAddOpen] = useState(false)
  const [markPaidTarget, setMarkPaidTarget] = useState<PaymentWithClient | null>(null)
  const [revertTarget, setRevertTarget] = useState<PaymentWithClient | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<PaymentWithClient | null>(null)
  const [processing, setProcessing] = useState(false)

  // 集計（一覧データからclient-side計算）
  const summary = useMemo(() => {
    const unpaid = payments.filter(isUnpaidStatus)
    const unpaidTotalYen = unpaid.reduce((sum, p) => sum + p.amount_yen, 0)

    const now = new Date()
    const paidThisMonthYen = payments
      .filter((p) => {
        if (p.status !== 'paid' || !p.paid_at) return false
        const paidAt = new Date(p.paid_at)
        return (
          paidAt.getFullYear() === now.getFullYear() && paidAt.getMonth() === now.getMonth()
        )
      })
      .reduce((sum, p) => sum + p.amount_yen, 0)

    return { unpaidTotalYen, unpaidCount: unpaid.length, paidThisMonthYen }
  }, [payments])

  const filteredPayments = useMemo(() => {
    if (filter === 'unpaid') return payments.filter(isUnpaidStatus)
    if (filter === 'paid') return payments.filter((p) => p.status === 'paid')
    return payments
  }, [payments, filter])

  const filterOptions: { key: PaymentFilter; label: string; count: number }[] = [
    { key: 'unpaid', label: '未払い', count: payments.filter(isUnpaidStatus).length },
    { key: 'paid', label: '支払済み', count: payments.filter((p) => p.status === 'paid').length },
    { key: 'all', label: 'すべて', count: payments.length },
  ]

  const handleRevert = async () => {
    if (!revertTarget) return
    setProcessing(true)
    try {
      const res = await fetch(`/api/payments/${revertTarget.id}`, {
        method: 'PATCH',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: 'mark_unpaid' }),
      })
      if (!res.ok) {
        throw new Error('未払いへの変更に失敗しました')
      }
      setRevertTarget(null)
      onRefetch()
    } catch (error) {
      console.error('未払い変更エラー:', error)
      alert('未払いへの変更に失敗しました')
    } finally {
      setProcessing(false)
    }
  }

  const handleDelete = async () => {
    if (!deleteTarget) return
    setProcessing(true)
    try {
      const res = await fetch(`/api/payments/${deleteTarget.id}`, {
        method: 'DELETE',
      })
      if (!res.ok) {
        throw new Error('支払記録の削除に失敗しました')
      }
      setDeleteTarget(null)
      onRefetch()
    } catch (error) {
      console.error('支払記録削除エラー:', error)
      alert('削除に失敗しました')
    } finally {
      setProcessing(false)
    }
  }

  return (
    <div className="space-y-4">
      {/* 取得失敗時の控えめな通知 */}
      {loadFailed && (
        <div
          className="flex items-center gap-2 rounded-md border px-4 py-3"
          style={{ backgroundColor: '#FFFBEB', borderColor: '#FDE68A' }}
        >
          <AlertCircle size={16} style={{ color: '#B45309' }} className="flex-shrink-0" />
          <p className="text-[13px]" style={{ color: '#B45309' }}>
            支払いデータを取得できませんでした
          </p>
        </div>
      )}

      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-base font-semibold" style={{ color: '#0F172A' }}>
          支払い記録
        </h2>
        <button
          onClick={() => setAddOpen(true)}
          className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white rounded-md transition-colors"
          style={{ backgroundColor: '#14B8A6' }}
          onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#0D9488')}
          onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = '#14B8A6')}
        >
          + 手動記録を追加
        </button>
      </div>

      {/* 集計ヘッダ */}
      <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
        {/* 未収金合計 */}
        <div
          className="bg-white border rounded-md p-4"
          style={{ borderColor: summary.unpaidCount > 0 ? '#FCD34D' : '#E2E8F0' }}
        >
          <div className="flex items-center gap-3 mb-2">
            <div
              className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
              style={{ backgroundColor: summary.unpaidCount > 0 ? '#FFFBEB' : '#F8FAFC' }}
            >
              <Wallet
                size={18}
                style={{ color: summary.unpaidCount > 0 ? '#F59E0B' : '#94A3B8' }}
              />
            </div>
            <span className="text-sm font-medium" style={{ color: '#475569' }}>
              未収金合計
            </span>
          </div>
          <p className="text-2xl font-bold tabular-nums" style={{ color: '#0F172A' }}>
            {formatYen(summary.unpaidTotalYen)}
          </p>
          <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>
            未払い {summary.unpaidCount}件
          </p>
        </div>

        {/* 今月入金合計 */}
        <div className="bg-white border rounded-md p-4" style={{ borderColor: '#E2E8F0' }}>
          <div className="flex items-center gap-3 mb-2">
            <div
              className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
              style={{ backgroundColor: '#F0FDFA' }}
            >
              <Banknote size={18} style={{ color: '#14B8A6' }} />
            </div>
            <span className="text-sm font-medium" style={{ color: '#475569' }}>
              今月入金合計
            </span>
          </div>
          <p className="text-2xl font-bold tabular-nums" style={{ color: '#0F172A' }}>
            {formatYen(summary.paidThisMonthYen)}
          </p>
          <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>
            {format(new Date(), 'yyyy年M月')}の入金
          </p>
        </div>
      </div>

      {/* フィルタ */}
      <div
        className="inline-flex items-center rounded-md border bg-white p-0.5"
        style={{ borderColor: '#E2E8F0' }}
      >
        {filterOptions.map((option) => {
          const isActive = filter === option.key
          return (
            <button
              key={option.key}
              onClick={() => setFilter(option.key)}
              className="flex items-center gap-1.5 px-3 py-1.5 text-[12px] font-medium rounded-[4px] transition-colors"
              style={{
                backgroundColor: isActive ? '#F0FDFA' : 'transparent',
                color: isActive ? '#14B8A6' : '#94A3B8',
              }}
            >
              {option.label}
              <span className="tabular-nums">{option.count}</span>
            </button>
          )
        })}
      </div>

      {/* 一覧 */}
      {filteredPayments.length > 0 ? (
        <div className="bg-white rounded-md border border-[#E2E8F0]">
          <div className="overflow-x-auto">
            <table className="w-full">
              <thead className="bg-[#F8FAFC] border-b border-[#E2E8F0]">
                <tr>
                  <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    顧客名
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    対象
                  </th>
                  <th className="px-4 py-3 text-right text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    金額
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    期日
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    ステータス
                  </th>
                  <th className="px-4 py-3 text-left text-[11px] font-semibold text-[#94A3B8] tracking-wider">
                    操作
                  </th>
                </tr>
              </thead>
              <tbody>
                {filteredPayments.map((payment, index) => {
                  const { status, overdueDays } = getDisplayStatus(payment)
                  const config = STATUS_CONFIG[status]
                  const isLast = index === filteredPayments.length - 1
                  const cellBorder = isLast ? 'none' : '1px solid #E2E8F0'
                  const isRowProcessing =
                    processing &&
                    (revertTarget?.id === payment.id || deleteTarget?.id === payment.id)

                  return (
                    <tr key={payment.id} className="hover:bg-[#FAFBFC]">
                      {/* 顧客名 */}
                      <td
                        className="px-4 py-3 text-[13px] text-[#0F172A]"
                        style={{ borderBottom: cellBorder }}
                      >
                        {payment.client_name}
                      </td>

                      {/* 対象 */}
                      <td
                        className="px-4 py-3 text-[13px]"
                        style={{ borderBottom: cellBorder }}
                      >
                        {payment.ticket_name ? (
                          <span className="text-[#0F172A]">{payment.ticket_name}</span>
                        ) : (
                          <span className="text-[#94A3B8]">手動記録</span>
                        )}
                        {payment.note && (
                          <p className="text-[11px] text-[#94A3B8] mt-0.5">{payment.note}</p>
                        )}
                      </td>

                      {/* 金額 */}
                      <td
                        className="px-4 py-3 text-[13px] text-[#0F172A] text-right tabular-nums font-medium"
                        style={{ borderBottom: cellBorder }}
                      >
                        {formatYen(payment.amount_yen)}
                      </td>

                      {/* 期日 */}
                      <td
                        className="px-4 py-3 text-[13px] text-[#0F172A]"
                        style={{ borderBottom: cellBorder }}
                      >
                        {payment.due_date
                          ? format(new Date(payment.due_date), 'yyyy/MM/dd')
                          : '—'}
                        {status === 'paid' && payment.paid_at && (
                          <p className="text-[11px] text-[#94A3B8] mt-0.5">
                            入金 {format(new Date(payment.paid_at), 'yyyy/MM/dd')}
                            {payment.method && ` ・ ${PAYMENT_METHOD_LABELS[payment.method]}`}
                          </p>
                        )}
                      </td>

                      {/* ステータスバッジ */}
                      <td className="px-4 py-3" style={{ borderBottom: cellBorder }}>
                        <span
                          className="inline-flex items-center gap-1.5 rounded-md px-2 py-0.5 text-[11px] font-medium whitespace-nowrap"
                          style={{
                            backgroundColor: config.bg,
                            color: config.text,
                            border: `1px solid ${config.border}`,
                          }}
                        >
                          <span
                            className="w-1.5 h-1.5 rounded-full flex-shrink-0"
                            style={{ backgroundColor: config.dot }}
                          />
                          {status === 'overdue'
                            ? `${config.label} ${overdueDays}日`
                            : config.label}
                        </span>
                      </td>

                      {/* 操作 */}
                      <td className="px-4 py-3" style={{ borderBottom: cellBorder }}>
                        <div className="flex items-center gap-1">
                          {isRowProcessing && (
                            <Loader2
                              size={14}
                              className="animate-spin"
                              style={{ color: '#94A3B8' }}
                            />
                          )}
                          {(status === 'unpaid' || status === 'overdue') && (
                            <button
                              onClick={() => setMarkPaidTarget(payment)}
                              disabled={isRowProcessing}
                              className="text-[13px] whitespace-nowrap px-2 py-1 rounded-md transition-colors hover:bg-[#F0FDFA] disabled:opacity-50"
                              style={{ color: '#14B8A6' }}
                            >
                              支払済みにする
                            </button>
                          )}
                          {status === 'paid' && (
                            <button
                              onClick={() => setRevertTarget(payment)}
                              disabled={isRowProcessing}
                              className="text-[13px] whitespace-nowrap text-[#475569] hover:text-[#0F172A] hover:bg-[#F8FAFC] px-2 py-1 rounded-md transition-colors disabled:opacity-50"
                            >
                              未払いに戻す
                            </button>
                          )}
                          <button
                            onClick={() => setDeleteTarget(payment)}
                            disabled={isRowProcessing}
                            className="text-[13px] whitespace-nowrap text-[#DC2626] hover:text-[#B91C1C] hover:bg-[#FEF2F2] px-2 py-1 rounded-md transition-colors disabled:opacity-50"
                          >
                            削除
                          </button>
                        </div>
                      </td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          </div>
        </div>
      ) : (
        <div
          className="flex items-center justify-center h-48 bg-white border rounded-md"
          style={{ borderColor: '#E2E8F0', borderStyle: 'dashed' }}
        >
          <div className="text-center">
            <div
              className="w-12 h-12 rounded-full flex items-center justify-center mx-auto mb-3"
              style={{ backgroundColor: '#F0FDFA' }}
            >
              <Banknote size={24} style={{ color: '#14B8A6' }} />
            </div>
            <p className="text-sm" style={{ color: '#94A3B8' }}>
              {filter === 'unpaid'
                ? '未払いの記録はありません'
                : filter === 'paid'
                  ? '支払済みの記録はありません'
                  : '支払い記録がありません'}
            </p>
          </div>
        </div>
      )}

      {/* 手動記録の追加モーダル */}
      <AddPaymentModal
        open={addOpen}
        onOpenChange={setAddOpen}
        clients={clients}
        onSaved={onRefetch}
      />

      {/* 支払済みにするモーダル */}
      <MarkPaidModal
        open={!!markPaidTarget}
        onOpenChange={(open) => !open && setMarkPaidTarget(null)}
        payment={markPaidTarget}
        onSaved={() => {
          setMarkPaidTarget(null)
          onRefetch()
        }}
      />

      {/* 未払いに戻す確認ダイアログ */}
      <AlertDialog
        open={!!revertTarget}
        onOpenChange={(open) => !open && !processing && setRevertTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>未払いに戻しますか？</AlertDialogTitle>
            <AlertDialogDescription>
              {revertTarget?.client_name}の
              {formatYen(revertTarget?.amount_yen ?? 0)}
              （{revertTarget?.ticket_name ?? '手動記録'}）を未払いに戻します。
              入金日・支払方法・領収書番号はクリアされます。
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={processing}>キャンセル</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleRevert}
              disabled={processing}
              className="bg-[#0F172A] hover:bg-[#1E293B] text-white rounded-md"
            >
              {processing ? '変更中...' : '未払いに戻す'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>

      {/* 削除確認ダイアログ */}
      <AlertDialog
        open={!!deleteTarget}
        onOpenChange={(open) => !open && !processing && setDeleteTarget(null)}
      >
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>支払記録を削除しますか？</AlertDialogTitle>
            <AlertDialogDescription>
              {deleteTarget?.client_name}の
              {formatYen(deleteTarget?.amount_yen ?? 0)}
              （{deleteTarget?.ticket_name ?? '手動記録'}）を削除します。
              この操作は取り消せません。
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={processing}>キャンセル</AlertDialogCancel>
            <AlertDialogAction
              onClick={handleDelete}
              disabled={processing}
              className="bg-[#DC2626] hover:bg-[#B91C1C] text-white rounded-md"
            >
              {processing ? '削除中...' : '削除'}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}
