// ================================================
// 期間フィルター型定義
// ================================================

export type PeriodFilter = 'week' | 'month' | 'threeMonths' | 'all'

export const PERIOD_LABELS: Record<PeriodFilter, string> = {
  week: '週',
  month: '月',
  threeMonths: '3ヶ月',
  all: '全期間',
}
