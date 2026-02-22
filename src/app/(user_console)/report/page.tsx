"use client"

import { useEffect, useState, useMemo } from 'react'
import { subMonths, format, differenceInDays } from 'date-fns'
import { supabase } from '@/lib/supabase'
import { getClients } from '@/lib/supabase/getClients'
import { getWeightRecords } from '@/lib/supabase/getWeightRecords'
import { getMealRecords } from '@/lib/supabase/getMealRecords'
import { getExerciseRecords } from '@/lib/supabase/getExerciseRecords'
import type { Client, WeightRecord, MealRecord, ExerciseRecord } from '@/types/client'
import { StatCards } from '@/components/report/StatCards'
import { MealStatistics } from '@/components/report/MealStatistics'
import { ExerciseStatistics } from '@/components/report/ExerciseStatistics'
import { WeightChart } from '@/components/clients/WeightChart'
import { GoalAchievementChart } from '@/components/report/GoalAchievementChart'
import { exportCSV } from '@/lib/export/exportCSV'
import { exportPDF } from '@/lib/export/exportPDF'
import { Select, SelectTrigger, SelectValue, SelectContent, SelectItem } from '@/components/ui/select'
import { Button } from '@/components/ui/button'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Input } from '@/components/ui/input'

export default function ReportPage() {
  const [clients, setClients] = useState<Client[]>([])
  const [selectedClientId, setSelectedClientId] = useState<string>('')
  const [startDate, setStartDate] = useState<string>('')
  const [endDate, setEndDate] = useState<string>('')
  const [loading, setLoading] = useState(true)
  const [dataLoading, setDataLoading] = useState(false)
  const [pdfLoading, setPdfLoading] = useState(false)
  const [weightRecords, setWeightRecords] = useState<WeightRecord[]>([])
  const [mealRecords, setMealRecords] = useState<MealRecord[]>([])
  const [exerciseRecords, setExerciseRecords] = useState<ExerciseRecord[]>([])

  // 初期化: トレーナーのクライアント一覧取得 & デフォルト期間設定
  useEffect(() => {
    const initialize = async () => {
      setLoading(true)
      try {
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          const clientsData = await getClients(user.id)
          setClients(clientsData)

          // デフォルト期間: 過去3ヶ月～今日
          const today = new Date()
          const threeMonthsAgo = subMonths(today, 3)
          setStartDate(format(threeMonthsAgo, 'yyyy-MM-dd'))
          setEndDate(format(today, 'yyyy-MM-dd'))
        }
      } catch (error) {
        console.error('Error initializing report page:', error)
      } finally {
        setLoading(false)
      }
    }
    initialize()
  }, [])

  // クライアント選択時: データ取得
  useEffect(() => {
    if (!selectedClientId) return

    const fetchData = async () => {
      setDataLoading(true)
      try {
        const [weights, meals, exercises] = await Promise.all([
          getWeightRecords(selectedClientId),
          getMealRecords({ clientId: selectedClientId, limit: 1000 }),
          getExerciseRecords({ clientId: selectedClientId, limit: 1000 }),
        ])

        setWeightRecords(weights)
        setMealRecords(meals.data)
        setExerciseRecords(exercises.data)
      } catch (error) {
        console.error('Error fetching client data:', error)
      } finally {
        setDataLoading(false)
      }
    }

    fetchData()
  }, [selectedClientId])

  // 期間フィルター & 統計計算
  const filteredData = useMemo(() => {
    if (!startDate || !endDate) {
      return {
        weightRecords: [],
        mealRecords: [],
        exerciseRecords: [],
        totalDays: 0,
        latestWeight: null,
        weightChange: null,
        totalExerciseMinutes: 0,
        avgCaloriesPerDay: null,
      }
    }

    // startDate, endDate でフィルター
    const filtered = {
      weightRecords: weightRecords.filter(r => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
      mealRecords: mealRecords.filter(r => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
      exerciseRecords: exerciseRecords.filter(r => {
        const date = r.recorded_at.split('T')[0]
        return date >= startDate && date <= endDate
      }),
    }

    // 統計計算
    const totalDays = differenceInDays(new Date(endDate), new Date(startDate)) + 1

    // 体重統計
    const sortedWeights = filtered.weightRecords.sort(
      (a, b) => new Date(a.recorded_at).getTime() - new Date(b.recorded_at).getTime()
    )
    const latestWeight = sortedWeights.length > 0
      ? sortedWeights[sortedWeights.length - 1].weight
      : null
    const firstWeight = sortedWeights.length > 0
      ? sortedWeights[0].weight
      : null
    const weightChange = (latestWeight !== null && firstWeight !== null)
      ? latestWeight - firstWeight
      : null

    // 運動統計
    const totalExerciseMinutes = filtered.exerciseRecords
      .filter(r => r.duration !== null)
      .reduce((sum, r) => sum + (r.duration || 0), 0)

    // 食事カロリー統計（1日あたり平均）
    const recordedDates = new Set(
      filtered.mealRecords.map(r => r.recorded_at.split('T')[0])
    )
    const recordedDaysCount = recordedDates.size
    const totalCalories = filtered.mealRecords
      .filter(r => r.calories !== null)
      .reduce((sum, r) => sum + (r.calories || 0), 0)
    const avgCaloriesPerDay = recordedDaysCount > 0
      ? Math.round(totalCalories / recordedDaysCount)
      : null

    return {
      ...filtered,
      totalDays,
      latestWeight,
      weightChange,
      totalExerciseMinutes,
      avgCaloriesPerDay,
    }
  }, [weightRecords, mealRecords, exerciseRecords, startDate, endDate])

  // 選択されたクライアント取得
  const selectedClient = clients.find(c => c.client_id === selectedClientId)

  // CSVエクスポート処理
  const handleExportCSV = () => {
    if (!selectedClient) return

    exportCSV({
      clientName: selectedClient.name,
      weightRecords: filteredData.weightRecords,
      mealRecords: filteredData.mealRecords,
      exerciseRecords: filteredData.exerciseRecords,
      startDate,
      endDate,
    })
  }

  // PDFエクスポート処理
  const handleExportPDF = async () => {
    if (!selectedClient) return

    setPdfLoading(true)
    try {
      await exportPDF({
        clientName: selectedClient.name,
        startDate,
        endDate,
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
  }

  // 初期ローディング
  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-6xl mx-auto p-6 space-y-6">
        {/* ページヘッダー */}
        <div>
          <h1 className="text-2xl font-bold text-gray-900">レポート・分析</h1>
          <p className="text-sm text-gray-600 mt-1">クライアントデータの統計・グラフ表示</p>
        </div>

        {/* 操作バー */}
        <div className="flex flex-col md:flex-row gap-4 items-start md:items-center">
          {/* 顧客選択 */}
          <div className="w-full md:w-64">
            <Select value={selectedClientId} onValueChange={setSelectedClientId}>
              <SelectTrigger>
                <SelectValue placeholder="顧客を選択" />
              </SelectTrigger>
              <SelectContent>
                {clients.map(client => (
                  <SelectItem key={client.client_id} value={client.client_id}>
                    {client.name}
                  </SelectItem>
                ))}
              </SelectContent>
            </Select>
          </div>

          {/* 期間選択 */}
          <div className="flex items-center gap-2">
            <Input
              type="date"
              value={startDate}
              onChange={(e) => setStartDate(e.target.value)}
              className="w-40"
            />
            <span className="text-gray-600">〜</span>
            <Input
              type="date"
              value={endDate}
              onChange={(e) => setEndDate(e.target.value)}
              className="w-40"
            />
          </div>

          {/* エクスポートボタン */}
          <div className="flex gap-2 ml-auto">
            <Button
              variant="outline"
              onClick={handleExportCSV}
              disabled={!selectedClientId || dataLoading}
            >
              CSV
            </Button>
            <Button
              variant="outline"
              onClick={handleExportPDF}
              disabled={!selectedClientId || dataLoading || pdfLoading}
            >
              {pdfLoading ? '生成中...' : 'PDF'}
            </Button>
          </div>
        </div>

        {/* コンテンツエリア */}
        {!selectedClientId ? (
          <div className="flex items-center justify-center h-64">
            <p className="text-gray-500">顧客を選択してください</p>
          </div>
        ) : dataLoading ? (
          <div className="flex items-center justify-center h-64">
            <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
          </div>
        ) : (
          <div id="report-content" className="space-y-6 bg-white p-6 rounded-lg">
            {/* 統計カード */}
            <StatCards
              weightChange={filteredData.weightChange}
              latestWeight={filteredData.latestWeight}
              mealCount={filteredData.mealRecords.length}
              exerciseCount={filteredData.exerciseRecords.length}
              totalExerciseMinutes={filteredData.totalExerciseMinutes}
            />

            {/* 目標達成率推移グラフ */}
            <GoalAchievementChart
              weightRecords={filteredData.weightRecords}
              allWeightRecords={weightRecords}
              mealRecords={filteredData.mealRecords}
              exerciseRecords={filteredData.exerciseRecords}
              startDate={startDate}
              endDate={endDate}
              targetWeight={selectedClient?.target_weight || 0}
            />

            {/* 体重推移グラフ */}
            <Card>
              <CardHeader>
                <CardTitle>体重推移</CardTitle>
              </CardHeader>
              <CardContent>
                <WeightChart
                  weightRecords={filteredData.weightRecords}
                  targetWeight={selectedClient?.target_weight || 0}
                  showPeriodFilter={false}
                />
              </CardContent>
            </Card>

            {/* 食事・運動統計（2カラム） */}
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
          </div>
        )}
      </div>
    </main>
  )
}
