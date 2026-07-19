import { supabase } from '@/lib/supabase'
import type { PaymentWithClient } from '@/types/payment'

/**
 * トレーナーの支払記録一覧を顧客名・チケット名付きで取得する（browser client + RLS）。
 * 並び順: due_date 昇順（NULL は末尾）→ created_at 降順
 */
export const getPayments = async (trainerId: string): Promise<PaymentWithClient[]> => {
  const { data, error } = await supabase
    .from('payments')
    .select('*, clients(name), tickets(ticket_name)')
    .eq('trainer_id', trainerId)
    .order('due_date', { ascending: true, nullsFirst: false })
    .order('created_at', { ascending: false })

  if (error) {
    throw error
  }

  // 顧客名・チケット名を平坦化してレスポンス
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const payments: PaymentWithClient[] = (data ?? []).map((payment: any) => ({
    id: payment.id,
    trainer_id: payment.trainer_id,
    client_id: payment.client_id,
    ticket_id: payment.ticket_id,
    ticket_subscription_id: payment.ticket_subscription_id,
    amount_yen: payment.amount_yen,
    method: payment.method,
    status: payment.status,
    due_date: payment.due_date,
    paid_at: payment.paid_at,
    receipt_number: payment.receipt_number,
    note: payment.note,
    created_at: payment.created_at,
    updated_at: payment.updated_at,
    client_name: payment.clients?.name ?? '',
    ticket_name: payment.tickets?.ticket_name ?? null,
  }))

  return payments
}
