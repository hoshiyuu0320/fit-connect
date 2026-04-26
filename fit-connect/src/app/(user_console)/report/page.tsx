'use client'

import { useState, useEffect, useMemo, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { getClients } from '@/lib/supabase/getClients'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getExerciseRecords } from '@/lib/supabase/getExerciseRecords'
import { getClientReportMetrics } from '@/lib/supabase/getClientReportMetrics'
import { getActivityHeatmapData } from '@/lib/supabase/getActivityHeatmapData'
import { ReportToolbar } from '@/components/report/ReportToolbar'
import { OverviewKPI } from '@/components/report/OverviewKPI'
import { ClientComparisonTable } from '@/components/report/ClientComparisonTable'
import { ActivityHeatmap } from '@/components/report/ActivityHeatmap'
import { ClientReportHeader } from '@/components/report/ClientReportHeader'
import { ActivityCalendar } from '@/components/report/ActivityCalendar'
import { GoalAchievementChart } from '@/components/report/GoalAchievementChart'
import { MealStatistics } from '@/components/report/MealStatistics'
import { ExerciseStatistics } from '@/components/report/ExerciseStatistics'
import { WeightChart } from '@/components/clients/WeightChart'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { exportCSV } from '@/lib/export/exportCSV'
import { exportPDF } from '@/lib/export/exportPDF'
import type { ReportMode, PeriodPreset, DateRange, OverviewKPIData, ClientReportRow, HeatmapRow, CalendarActivity } from '@/types/report'
import type { Client, WeightRecord, MealRecord, ExerciseRecord } from '@/types/client'
import { subWeeks, subMonths, subYears, format, differenceInDays } from 'date-fns'

export default function ReportPage() {
  // ---- State ----
  const [userId, setUserId] = useState<string | null>(null)

  // モード
  const [mode, setMode] = useState<ReportMode>('overview')

  // 期間
  const [periodPreset, setPeriodPreset] = useState<PeriodPreset>('3M')
  const [dateRange, setDateRange] = useState<DateRange>(() => {
    const end = new Date()
    const start = subMonths(end, 3)
    return {
      startDate: format(start, 'yyyy-MM-dd'),
      endDate: format(end, 'yyyy-MM-dd'),
    }
  })

  // クライアント
  const [clients, setClients] = useState<Client[]>([])
  const [selectedClientId, setSelectedClientId] = useState<string | null>(null)

  // ローディング
  const [loading, setLoading] = useState(true)
  const [initialLoading, setInitialLoading] = useState(true)
  const [pdfLoading, setPdfLoading] = useState(false)

  // 全体概況データ
  const [overviewKPI, setOverviewKPI] = useState<OverviewKPIData>({
    totalClients: 0,
    activeRate: 0,
    avgRecordRate: 0,
    goalAchievers: 0,
    totalClientsGoal: 0,
    changes: { totalClients: 0, activeRate: 0, avgRecordRate: 0, goalAchievers: 0 },
  })
  const [overviewRows, setOverviewRows] = useState<ClientReportRow[]>([])
  const [heatmapData, setHeatmapData] = useState<HeatmapRow[]>([])

  // 個別分析データ
  const [weightRecords, setWeightRecords] = useState<WeightRecord[]>([])
  const [mealRecords, setMealRecords] = useState<MealRecord[]>([])
  const [exerciseRecords, setExerciseRecords] = useState<ExerciseRecord[]>([])

  // カレンダー月
  const [calendarYear, setCalendarYear] = useState(new Date().getFullYear())
  const [calendarMonth, setCalendarMonth] = useState(new Date().getMonth() + 1)

  // ---- 期間プリセット変更ハンドラ ----
  const handlePeriodPresetChange = useCallback((preset: PeriodPreset) => {
    setPeriodPreset(preset)
    const end = new Date()
    let start: Date
    switch (preset) {
      case '1W':
        start = subWeeks(end, 1)
        break
      case '1M':
        start = subMonths(end, 1)
        break
      case '3M':
        start = subMonths(end, 3)
        break
      case '6M':
        start = subMonths(end, 6)
        break
      case '1Y':
        start = subYears(end, 1)
        break
    }
    setDateRange({
      startDate: format(start, 'yyyy-MM-dd'),
      endDate: format(end, 'yyyy-MM-dd'),
    })
  }, [])

  // ---- データ取得 ----

  // ユーザーID取得 + クライアント一覧取得
  useEffect(() => {
    const initialize = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          setUserId(user.id)
          const data = await getClients(user.id)
          setClients(data)
        }
      } catch (error) {
        console.error('Error initializing:', error)
      } finally {
        setInitialLoading(false)
      }
    }
    initialize()
  }, [])

  // 全体概況データ取得（overviewモード時）
  useEffect(() => {
    if (!userId || mode !== 'overview' || clients.length === 0) {
      if (mode === 'overview' && clients.length === 0 && !initialLoading) {
        setLoading(false)
      }
      return
    }
    setLoading(true)
    const fetchOverview = async () => {
      try {
        const [metrics, heatmap] = await Promise.all([
          getClientReportMetrics(userId, clients, dateRange),
          getActivityHeatmapData(clients, dateRange),
        ])
        setOverviewKPI(metrics.kpi)
        setOverviewRows(metrics.rows)
        setHeatmapData(heatmap)
      } catch (error) {
        console.error('Error fetching overview data:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchOverview()
  }, [userId, mode, clients, dateRange, initialLoading])

  // 個別分析データ取得（individualモード + クライアント選択時）
  useEffect(() => {
    if (mode !== 'individual' || !selectedClientId) return
    setLoading(true)
    const fetchIndividual = async () => {
      try {
        const [weights, meals, exercises] = await Promise.all([
          getWeightRecords(selectedClientId),
          getMealRecords({ clientId: selectedClientId, limit: 10000 }),
          getExerciseRecords({ clientId: selectedClientId, limit: 10000 }),
        ])
        setWeightRecords(weights)
        setMealRecords(meals.data)
        setExerciseRecords(exercises.data)
      } catch (error) {
        console.error('Error fetching individual data:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchIndividual()
  }, [mode, selectedClientId])

  // ---- 選択中のクライアント ----
  const selectedClient = useMemo(
    () => clients.find((c) => c.client_id === selectedClientId) || null,
    [clients, selectedClientId]
  )

  // ---- 個別分析用の計算（useMemo） ----
  const filteredData = useMemo(() => {
    if (!dateRange.startDate || !dateRange.endDate) {
      return {
        weightRecords: [] as WeightRecord[],
        mealRecords: [] as MealRecord[],
        exerciseRecords: [] as ExerciseRecord[],
        totalDays: 0,
        latestWeight: null as number | null,
        weightChange: null as number | null,
        totalExerciseMinutes: 0,
        totalExerciseCount: 0,
        avgCaloriesPerDay: null as number | null,
        mealRecordRate: 0,
      }
    }

    const startDate = dateRange.startDate
    const endDate = dateRange.endDate

    // dateRange でフィルタ
    const filtered = {
      weightRecords: weightRecords.filter((r) => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
      mealRecords: mealRecords.filter((r) => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
      exerciseRecords: exerciseRecords.filter((r) => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
    }

    // 統計計算
    const totalDays = differenceInDays(new Date(endDate), new Date(startDate)) + 1

    // 体重統計
    const sortedWeights = [...filtered.weightRecords].sort(
      (a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime()
    )
    const latestWeight =
      sortedWeights.length > 0 ? sortedWeights[sortedWeights.length - 1].weight : null
    const firstWeight = sortedWeights.length > 0 ? sortedWeights[0].weight : null
    const weightChange =
      latestWeight !== null && firstWeight !== null ? latestWeight - firstWeight : null

    // 運動統計
    const totalExerciseMinutes = filtered.exerciseRecords
      .filter((r) => r.duration !== null)
      .reduce((sum, r) => sum + (r.duration || 0), 0)
    const totalExerciseCount = filtered.exerciseRecords.length

    // 食事カロリー統計（1日あたり平均）
    const recordedMealDates = new Set(
      filtered.mealRecords.map((r) => r.recorded_at.split('T')[0])
    )
    const recordedMealDaysCount = recordedMealDates.size
    const totalCalories = filtered.mealRecords
      .filter((r) => r.calories !== null)
      .reduce((sum, r) => sum + (r.calories || 0), 0)
    const avgCaloriesPerDay =
      recordedMealDaysCount > 0 ? Math.round(totalCalories / recordedMealDaysCount) : null

    // 食事記録率
    const mealRecordRate =
      totalDays > 0 ? Math.round((recordedMealDates.size / totalDays) * 100) : 0

    return {
      ...filtered,
      totalDays,
      latestWeight,
      weightChange,
      totalExerciseMinutes,
      totalExerciseCount,
      avgCaloriesPerDay,
      mealRecordRate,
    }
  }, [weightRecords, mealRecords, exerciseRecords, dateRange])

  // ---- 個別分析: 総合スコア計算 ----
  const individualScore = useMemo(() => {
    if (!selectedClient) return 0
    const { totalDays, mealRecordRate } = filteredData

    // 運動記録率
    const exerciseDates = new Set(
      filteredData.exerciseRecords.map((r) => r.recorded_at.split('T')[0])
    )
    const exerciseRecordRate =
      totalDays > 0 ? Math.round((exerciseDates.size / totalDays) * 100) : 0

    // 体重スコア
    let weightScore = 0
    if (
      selectedClient.target_weight &&
      filteredData.weightRecords.length > 0
    ) {
      const sortedW = [...filteredData.weightRecords].sort(
        (a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime()
      )
      const first = sortedW[0].weight
      const latest = sortedW[sortedW.length - 1].weight
      if (first !== selectedClient.target_weight) {
        const initialDiff = Math.abs(first - selectedClient.target_weight)
        const currentDiff = Math.abs(latest - selectedClient.target_weight)
        const progress = ((initialDiff - currentDiff) / initialDiff) * 100
        weightScore = Math.max(0, Math.min(100, progress))
      }
    }

    let score: number
    if (selectedClient.target_weight) {
      score = weightScore * 0.4 + mealRecordRate * 0.3 + exerciseRecordRate * 0.3
    } else {
      score = mealRecordRate * 0.6 + exerciseRecordRate * 0.4
    }
    return Math.round(score)
  }, [selectedClient, filteredData])

  // ---- カレンダー用アクティビティ計算（useMemo） ----
  const calendarActivities = useMemo((): CalendarActivity[] => {
    const activityMap = new Map<string, Set<'weight' | 'meal' | 'exercise'>>()

    for (const r of weightRecords) {
      const date = r.recorded_at.split('T')[0]
      if (!activityMap.has(date)) activityMap.set(date, new Set())
      activityMap.get(date)!.add('weight')
    }
    for (const r of mealRecords) {
      const date = r.recorded_at.split('T')[0]
      if (!activityMap.has(date)) activityMap.set(date, new Set())
      activityMap.get(date)!.add('meal')
    }
    for (const r of exerciseRecords) {
      const date = r.recorded_at.split('T')[0]
      if (!activityMap.has(date)) activityMap.set(date, new Set())
      activityMap.get(date)!.add('exercise')
    }

    return Array.from(activityMap.entries()).map(([date, types]) => ({
      date,
      types: Array.from(types),
    }))
  }, [weightRecords, mealRecords, exerciseRecords])

  // ---- エクスポート ----
  const handleExportCSV = useCallback(() => {
    if (!selectedClient) return
    exportCSV({
      clientName: selectedClient.name,
      weightRecords: filteredData.weightRecords,
      mealRecords: filteredData.mealRecords,
      exerciseRecords: filteredData.exerciseRecords,
      startDate: dateRange.startDate,
      endDate: dateRange.endDate,
    })
  }, [selectedClient, filteredData, dateRange])

  const handleExportPDF = useCallback(async () => {
    if (!selectedClient) return
    setPdfLoading(true)
    try {
      await exportPDF({
        clientName: selectedClient.name,
        startDate: dateRange.startDate,
        endDate: dateRange.endDate,
        stats: {
          latestWeight: filteredData.latestWeight,
          weightChange: filteredData.weightChange,
          mealCount: filteredData.mealRecords.length,
          exerciseCount: filteredData.exerciseRecords.length,
          totalExerciseMinutes: filteredData.totalExerciseMinutes,
          avgCaloriesPerDay: filteredData.avgCaloriesPerDay,
        },
        chartElementId: 'report-content',
      })
    } catch (error) {
      console.error('Error exporting PDF:', error)
    } finally {
      setPdfLoading(false)
    }
  }, [selectedClient, filteredData, dateRange])

  // ---- クライアント選択ハンドラ（テーブル行クリック時） ----
  const handleClientSelect = useCallback((clientId: string) => {
    setSelectedClientId(clientId)
    setMode('individual')
  }, [])

  // ---- 初期ローディング ----
  if (initialLoading) {
    return (
      <div className="min-h-screen flex items-center justify-center" style={{ backgroundColor: '#F8FAFC' }}>
        <div
          className="animate-spin rounded-full h-10 w-10 border-[3px]"
          style={{ borderColor: '#E2E8F0', borderTopColor: '#14B8A6' }}
        />
      </div>
    )
  }

  // ---- レンダリング ----
  return (
    <div className="min-h-screen" style={{ backgroundColor: '#F8FAFC' }}>
      {/* ツールバー */}
      <ReportToolbar
        mode={mode}
        onModeChange={setMode}
        periodPreset={periodPreset}
        onPeriodPresetChange={handlePeriodPresetChange}
        dateRange={dateRange}
        onDateRangeChange={setDateRange}
        clients={clients}
        selectedClientId={selectedClientId}
        onClientSelect={setSelectedClientId}
        onExportCSV={handleExportCSV}
        onExportPDF={handleExportPDF}
      />

      <div className="p-6" id="report-content">
        {mode === 'overview' ? (
          // ======== 全体概況モード ========
          clients.length === 0 ? (
            <div className="flex flex-col items-center justify-center py-24">
              <svg
                width="48"
                height="48"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#94A3B8"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2" />
                <circle cx="9" cy="7" r="4" />
                <path d="M23 21v-2a4 4 0 0 0-3-3.87" />
                <path d="M16 3.13a4 4 0 0 1 0 7.75" />
              </svg>
              <p className="mt-4 text-sm font-medium" style={{ color: '#94A3B8' }}>
                クライアントが登録されていません
              </p>
              <p className="mt-1 text-xs" style={{ color: '#CBD5E1' }}>
                クライアントを追加するとレポートが表示されます
              </p>
            </div>
          ) : (
            <div className="space-y-5">
              <OverviewKPI data={overviewKPI} loading={loading} />
              <ClientComparisonTable
                rows={overviewRows}
                loading={loading}
                onClientSelect={handleClientSelect}
              />
              <ActivityHeatmap
                data={heatmapData}
                loading={loading}
                startDate={dateRange.startDate}
                endDate={dateRange.endDate}
              />
            </div>
          )
        ) : (
          // ======== 個別分析モード ========
          selectedClient ? (
            loading ? (
              <div className="flex items-center justify-center py-24">
                <div
                  className="animate-spin rounded-full h-10 w-10 border-[3px]"
                  style={{ borderColor: '#E2E8F0', borderTopColor: '#14B8A6' }}
                />
              </div>
            ) : (
              <div className="space-y-5">
                {/* クライアントヘッダー + KPIバー */}
                <ClientReportHeader
                  client={selectedClient}
                  latestWeight={filteredData.latestWeight}
                  weightChange={filteredData.weightChange}
                  mealRecordRate={filteredData.mealRecordRate}
                  exerciseTotal={{
                    count: filteredData.totalExerciseCount,
                    minutes: filteredData.totalExerciseMinutes,
                  }}
                  score={individualScore}
                  scoreChange={0}
                />

                {/* 2カラムグラフ: 目標達成率推移 + 体重推移 */}
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <GoalAchievementChart
                    weightRecords={filteredData.weightRecords}
                    allWeightRecords={weightRecords}
                    mealRecords={filteredData.mealRecords}
                    exerciseRecords={filteredData.exerciseRecords}
                    startDate={dateRange.startDate}
                    endDate={dateRange.endDate}
                    targetWeight={selectedClient.target_weight || 0}
                  />
                  <Card className="border border-[#E2E8F0] rounded-md" style={{ boxShadow: 'none' }}>
                    <CardHeader>
                      <CardTitle style={{ color: '#0F172A' }}>体重推移</CardTitle>
                    </CardHeader>
                    <CardContent>
                      <WeightChart
                        weightRecords={filteredData.weightRecords}
                        targetWeight={selectedClient.target_weight || 0}
                        showPeriodFilter={false}
                      />
                    </CardContent>
                  </Card>
                </div>

                {/* 2カラム統計: 食事 + 運動 */}
                <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
                  <MealStatistics
                    mealRecords={filteredData.mealRecords}
                    totalDays={filteredData.totalDays}
                  />
                  <ExerciseStatistics
                    exerciseRecords={filteredData.exerciseRecords}
                    totalDays={filteredData.totalDays}
                  />
                </div>

                {/* アクティビティカレンダー */}
                <ActivityCalendar
                  year={calendarYear}
                  month={calendarMonth}
                  activities={calendarActivities}
                  onMonthChange={(y, m) => {
                    setCalendarYear(y)
                    setCalendarMonth(m)
                  }}
                />
              </div>
            )
          ) : (
            // クライアント未選択
            <div className="flex flex-col items-center justify-center py-24">
              <svg
                width="48"
                height="48"
                viewBox="0 0 24 24"
                fill="none"
                stroke="#94A3B8"
                strokeWidth="1.5"
                strokeLinecap="round"
                strokeLinejoin="round"
              >
                <circle cx="11" cy="11" r="8" />
                <path d="M21 21l-4.35-4.35" />
              </svg>
              <p className="mt-4 text-sm font-medium" style={{ color: '#94A3B8' }}>
                クライアントを選択してください
              </p>
              <p className="mt-1 text-xs" style={{ color: '#CBD5E1' }}>
                ツールバーからクライアントを選択すると詳細レポートが表示されます
              </p>
            </div>
          )
        )}
      </div>

      {/* PDF生成中のオーバーレイ */}
      {pdfLoading && (
        <div className="fixed inset-0 z-50 flex items-center justify-center" style={{ backgroundColor: 'rgba(15, 23, 42, 0.4)' }}>
          <div className="bg-white rounded-md p-6 flex flex-col items-center gap-3" style={{ border: '1px solid #E2E8F0' }}>
            <div
              className="animate-spin rounded-full h-8 w-8 border-[3px]"
              style={{ borderColor: '#E2E8F0', borderTopColor: '#14B8A6' }}
            />
            <p className="text-sm font-medium" style={{ color: '#0F172A' }}>
              PDF生成中...
            </p>
          </div>
        </div>
      )}
    </div>
  )
}
