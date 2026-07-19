import { supabase } from '@/lib/supabase'
import { getJstMonthRange } from '@/lib/payments/jstDate'

export type PaymentSummary = {
  paidThisMonthYen: number // 今月（JST暦月・paid_at 基準）の入金合計
  unpaidTotalYen: number // 未払い（status='unpaid'）合計
  unpaidCount: number // 未払い件数
}

const sumAmountYen = (rows: { amount_yen: number | null }[] | null): number =>
  (rows ?? []).reduce((total, row) => total + (row.amount_yen ?? 0), 0)

/**
 * ダッシュボード用の支払サマリーを取得する（browser client + RLS）。
 * - paidThisMonthYen: JST 暦月の paid_at を持つ status='paid' の合計
 * - unpaidTotalYen / unpaidCount: status='unpaid' 全件
 */
export const getPaymentSummary = async (trainerId: string): Promise<PaymentSummary> => {
  const { startIso, endIso } = getJstMonthRange(new Date())

  const [paidRes, unpaidRes] = await Promise.all([
    supabase
      .from('payments')
      .select('amount_yen')
      .eq('trainer_id', trainerId)
      .eq('status', 'paid')
      .gte('paid_at', startIso)
      .lt('paid_at', endIso),
    supabase
      .from('payments')
      .select('amount_yen')
      .eq('trainer_id', trainerId)
      .eq('status', 'unpaid'),
  ])

  if (paidRes.error) {
    throw paidRes.error
  }
  if (unpaidRes.error) {
    throw unpaidRes.error
  }

  return {
    paidThisMonthYen: sumAmountYen(paidRes.data),
    unpaidTotalYen: sumAmountYen(unpaidRes.data),
    unpaidCount: (unpaidRes.data ?? []).length,
  }
}
