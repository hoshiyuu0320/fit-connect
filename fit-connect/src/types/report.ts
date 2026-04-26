// ================================================
// FIT-CONNECT レポート機能 TypeScript型定義
// ================================================

// レポートモード
export type ReportMode = 'overview' | 'individual'

// 期間プリセット
export type PeriodPreset = '1W' | '1M' | '3M' | '6M' | '1Y'

// 日付範囲
export interface DateRange {
  startDate: string // YYYY-MM-DD
  endDate: string   // YYYY-MM-DD
}

// ================================================
// 全体概況モード用
// ================================================

// クライアント進捗行（比較テーブル用）
export interface ClientReportRow {
  client_id: string
  name: string
  age: number | null
  gender: string | null
  purpose: string | null
  latestWeight: number | null
  targetWeight: number | null
  weightChange: number | null      // 期間内の体重変動
  mealRecordRate: number           // 食事記録率 0-100
  exerciseRecordRate: number       // 運動記録率 0-100
  score: number                    // 総合スコア 0-100
  status: 'good' | 'warning' | 'danger'
}

// 全体概況KPI
export interface OverviewKPIData {
  totalClients: number
  activeRate: number               // アクティブ率 0-100
  avgRecordRate: number            // 平均記録率 0-100
  goalAchievers: number            // 目標達成者数
  totalClientsGoal: number         // 目標設定者数
  // 前月比
  changes: {
    totalClients: number
    activeRate: number
    avgRecordRate: number
    goalAchievers: number
  }
}

// ヒートマップ行（1クライアント分）
export interface HeatmapRow {
  clientId: string
  clientName: string
  dailyCounts: { date: string; count: number }[]
}

// ================================================
// 個別分析モード用
// ================================================

// カレンダーアクティビティ
export interface CalendarActivity {
  date: string // YYYY-MM-DD
  types: ('weight' | 'meal' | 'exercise')[]
}

// 食事区分別集計
export interface MealTypeBreakdown {
  type: string
  label: string
  count: number
  rate: number // 0-100
}

// 運動種目別集計
export interface ExerciseTypeBreakdown {
  type: string
  label: string
  count: number
}
