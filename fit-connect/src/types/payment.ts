// ================================================
// FIT-CONNECT 支払記録 TypeScript型定義
// ================================================

export type PaymentMethod = 'cash' | 'bank_transfer' | 'card_external' | 'stripe'

export type PaymentStatus = 'unpaid' | 'paid' | 'overdue' | 'refunded'

export interface Payment {
  id: string
  trainer_id: string
  client_id: string
  ticket_id: string | null
  ticket_subscription_id: string | null
  amount_yen: number
  method: PaymentMethod | null
  status: PaymentStatus
  due_date: string | null
  paid_at: string | null
  receipt_number: string | null
  note: string | null
  created_at: string
  updated_at: string
}

// 顧客名・チケット名付き支払記録（JOINで取得）
export interface PaymentWithClient extends Payment {
  client_name: string
  ticket_name: string | null
}

// 支払方法の表示ラベル
export const PAYMENT_METHOD_LABELS: Record<PaymentMethod, string> = {
  cash: '現金',
  bank_transfer: '銀行振込',
  card_external: 'カード（外部決済）',
  stripe: 'Stripe',
}
