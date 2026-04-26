import type { WeightRecord, MealRecord, ExerciseRecord } from '@/types/client'

interface ExportCSVParams {
  clientName: string
  weightRecords: WeightRecord[]
  mealRecords: MealRecord[]
  exerciseRecords: ExerciseRecord[]
  startDate: string  // YYYY-MM-DD
  endDate: string    // YYYY-MM-DD
}

interface DailyData {
  date: string
  weight: number | null
  mealCount: number
  mealCalories: number
  exerciseCount: number
  exerciseDuration: number
}

/**
 * レポートデータをCSV形式でエクスポートする関数
 * 日付ごとに体重、食事、運動データを集計してダウンロードする
 */
export function exportCSV(params: ExportCSVParams): void {
  const { clientName, weightRecords, mealRecords, exerciseRecords, startDate, endDate } = params

  // データがすべて空の場合は何もしない
  if (weightRecords.length === 0 && mealRecords.length === 0 && exerciseRecords.length === 0) {
    return
  }

  // 期間内の全日付を生成
  const dates = generateDateRange(startDate, endDate)

  // 日付ごとにデータを集計
  const dailyDataMap = new Map<string, DailyData>()

  // 初期化
  dates.forEach(date => {
    dailyDataMap.set(date, {
      date,
      weight: null,
      mealCount: 0,
      mealCalories: 0,
      exerciseCount: 0,
      exerciseDuration: 0,
    })
  })

  // 体重データを集計
  weightRecords.forEach(record => {
    const date = record.recorded_at.split('T')[0] // YYYY-MM-DD
    const data = dailyDataMap.get(date)
    if (data) {
      data.weight = record.weight
    }
  })

  // 食事データを集計
  mealRecords.forEach(record => {
    const date = record.recorded_at.split('T')[0]
    const data = dailyDataMap.get(date)
    if (data) {
      data.mealCount++
      if (record.calories !== null) {
        data.mealCalories += record.calories
      }
    }
  })

  // 運動データを集計
  exerciseRecords.forEach(record => {
    const date = record.recorded_at.split('T')[0]
    const data = dailyDataMap.get(date)
    if (data) {
      data.exerciseCount++
      if (record.duration !== null) {
        data.exerciseDuration += record.duration
      }
    }
  })

  // CSV生成
  const csvRows: string[] = []

  // ヘッダー
  csvRows.push('日付,体重(kg),食事回数,食事カロリー(kcal),運動回数,運動時間(分)')

  // データ行（日付順）
  const sortedDates = Array.from(dailyDataMap.keys()).sort()
  sortedDates.forEach(date => {
    const data = dailyDataMap.get(date)!
    const weightValue = data.weight !== null ? data.weight.toString() : ''
    csvRows.push(
      `${date},${weightValue},${data.mealCount},${data.mealCalories},${data.exerciseCount},${data.exerciseDuration}`
    )
  })

  const csvString = csvRows.join('\n')

  // UTF-8 BOMを付加（Excel文字化け防止）
  const bom = '\uFEFF'
  const blob = new Blob([bom + csvString], { type: 'text/csv;charset=utf-8;' })

  // ダウンロード処理
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = `レポート_${clientName}_${startDate}_${endDate}.csv`

  // クリックしてダウンロード
  document.body.appendChild(link)
  link.click()

  // クリーンアップ
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

/**
 * 開始日から終了日までの日付配列を生成（YYYY-MM-DD形式）
 */
function generateDateRange(startDate: string, endDate: string): string[] {
  const dates: string[] = []
  const current = new Date(startDate)
  const end = new Date(endDate)

  while (current <= end) {
    dates.push(formatDate(current))
    current.setDate(current.getDate() + 1)
  }

  return dates
}

/**
 * Date オブジェクトを YYYY-MM-DD 形式の文字列に変換
 */
function formatDate(date: Date): string {
  const year = date.getFullYear()
  const month = String(date.getMonth() + 1).padStart(2, '0')
  const day = String(date.getDate()).padStart(2, '0')
  return `${year}-${month}-${day}`
}
