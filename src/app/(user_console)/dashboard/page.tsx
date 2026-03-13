"use client"

import { useEffect, useState } from "react"
import { supabase } from '@/lib/supabase'
import { getTrainer } from '@/lib/supabase/getTrainer'
import { getClientCount } from '@/lib/supabase/getClientCount'
import { getRecentMessageCount } from '@/lib/supabase/getRecentMessageCount'
import { getRecentMessages } from '@/lib/supabase/getRecentMessages'
import { getActiveClientCount } from '@/lib/supabase/getActiveClientCount'
import { getExpiringTickets } from '@/lib/supabase/getExpiringTickets'
import { getInactiveClients } from '@/lib/supabase/getInactiveClients'
import { getTodaysSessions } from '@/lib/supabase/getTodaysSessions'
import { getUndonePlanCount } from '@/lib/supabase/getUndonePlanCount'
import { getRecentRecords } from '@/lib/supabase/getRecentRecords'
import { getRecordStats } from '@/lib/supabase/getRecordStats'
import { getSessionStats } from '@/lib/supabase/getSessionStats'
import { getDailyRecordTrend } from '@/lib/supabase/getDailyRecordTrend'
import { getClientActivityRanking } from '@/lib/supabase/getClientActivityRanking'
import { getGoalProgress } from '@/lib/supabase/getGoalProgress'
import { useUserStore } from '@/store/userStore'
import { StatCard } from '@/components/dashboard/StatCard'
import { MessagePreviewList } from '@/components/dashboard/MessagePreviewList'
import { QuickActions } from '@/components/dashboard/QuickActions'
import { AlertList } from '@/components/dashboard/AlertList'
import { TodaysSchedule } from '@/components/dashboard/TodaysSchedule'
import { DashboardSkeleton } from '@/components/dashboard/DashboardSkeleton'
import { RecentRecordsTimeline } from '@/components/dashboard/RecentRecordsTimeline'
import { ActivityOverview } from '@/components/dashboard/ActivityOverview'
import { GoalProgressCarousel } from '@/components/dashboard/GoalProgressCarousel'
import type { RecentMessage } from '@/lib/supabase/getRecentMessages'
import type { AlertItemProps } from '@/components/dashboard/AlertItem'
import type { TodaysSession } from '@/lib/supabase/getTodaysSessions'
import type { RecentRecord } from '@/lib/supabase/getRecentRecords'
import type { RecordStats } from '@/lib/supabase/getRecordStats'
import type { SessionStats } from '@/lib/supabase/getSessionStats'
import type { DailyRecordPoint } from '@/lib/supabase/getDailyRecordTrend'
import type { ClientActivityRank } from '@/lib/supabase/getClientActivityRanking'
import type { GoalProgressByCategory } from '@/lib/supabase/getGoalProgress'
import React from 'react'

function UsersIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
      />
    </svg>
  )
}

function ChatIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M8 12h.01M12 12h.01M16 12h.01M21 12c0 4.418-4.03 8-9 8a9.863 9.863 0 01-4.255-.949L3 20l1.395-3.72C3.512 15.042 3 13.574 3 12c0-4.418 4.03-8 9-8s9 3.582 9 8z"
      />
    </svg>
  )
}

function ChartIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M9 19v-6a2 2 0 00-2-2H5a2 2 0 00-2 2v6a2 2 0 002 2h2a2 2 0 002-2zm0 0V9a2 2 0 012-2h2a2 2 0 012 2v10m-6 0a2 2 0 002 2h2a2 2 0 002-2m0 0V5a2 2 0 012-2h2a2 2 0 012 2v14a2 2 0 01-2 2h-2a2 2 0 01-2-2z"
      />
    </svg>
  )
}

function TicketIcon() {
  return (
    <svg className="w-5 h-5" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path
        strokeLinecap="round"
        strokeLinejoin="round"
        strokeWidth={2}
        d="M15 5v2m0 4v2m0 4v2M5 5a2 2 0 00-2 2v3a2 2 0 110 4v3a2 2 0 002 2h14a2 2 0 002-2v-3a2 2 0 110-4V7a2 2 0 00-2-2H5z"
      />
    </svg>
  )
}

export default function DashboardPage() {
  const [loading, setLoading] = useState(true)
  const userName = useUserStore((state) => state.userName)
  const setUserName = useUserStore((state) => state.setUserName)

  // KPIデータ
  const [clientCount, setClientCount] = useState(0)
  const [messageCount, setMessageCount] = useState(0)
  const [activeClientCount, setActiveClientCount] = useState(0)
  const [expiringTicketCount, setExpiringTicketCount] = useState(0)

  // メッセージデータ
  const [recentMessages, setRecentMessages] = useState<RecentMessage[]>([])

  // アラートデータ
  const [alerts, setAlerts] = useState<AlertItemProps[]>([])

  // 本日の予定データ
  const [todaysSessions, setTodaysSessions] = useState<TodaysSession[]>([])

  // 最近の記録データ
  const [recentRecords, setRecentRecords] = useState<RecentRecord[]>([])
  const [recordStats, setRecordStats] = useState<RecordStats>({
    mealCount: 0, mealCountLastWeek: 0,
    weightCount: 0, weightCountLastWeek: 0,
    exerciseCount: 0, exerciseCountLastWeek: 0,
    activeRecordingClients: 0, totalActiveClients: 0,
  })

  // チャート・プログレスデータ
  const [sessionStats, setSessionStats] = useState<SessionStats>({
    completed: 0, scheduled: 0, cancelled: 0, total: 0, completionRate: 0,
  })
  const [dailyTrend, setDailyTrend] = useState<DailyRecordPoint[]>([])
  const [clientRanking, setClientRanking] = useState<ClientActivityRank[]>([])
  const [goalCategories, setGoalCategories] = useState<GoalProgressByCategory[]>([])

  // 日付フォーマット
  const today = new Date()
  const formatted = today.toLocaleDateString('ja-JP', {
    month: 'long',
    day: 'numeric',
    weekday: 'short',
  })

  // 時間帯による挨拶
  const getGreeting = () => {
    const hour = today.getHours()
    if (hour < 12) return 'おはようございます'
    if (hour < 18) return 'こんにちは'
    return 'こんばんは'
  }

  useEffect(() => {
    const fetchDashboardData = async () => {
      setLoading(true)

      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        try {
          // トレーナー情報取得
          const profile = await getTrainer(user.id)
          if (profile?.name) {
            setUserName(profile.name)
          }

          // KPIデータとアラートデータを並列取得
          const [
            clients,
            messages,
            recentMsgs,
            activeClients,
            expiringTickets,
            inactiveClients,
            sessions,
            undonePlans,
            records,
            stats,
            sessStats,
            trend,
            ranking,
            goals,
          ] = await Promise.all([
            getClientCount(user.id),
            getRecentMessageCount(user.id),
            getRecentMessages(user.id, 5),
            getActiveClientCount(user.id),
            getExpiringTickets(user.id),
            getInactiveClients(user.id),
            getTodaysSessions(user.id),
            getUndonePlanCount(user.id),
            getRecentRecords(user.id, { limit: 20 }),
            getRecordStats(user.id),
            getSessionStats(user.id),
            getDailyRecordTrend(user.id),
            getClientActivityRanking(user.id),
            getGoalProgress(user.id),
          ])

          setClientCount(clients)
          setMessageCount(messages)
          setRecentMessages(recentMsgs)
          setActiveClientCount(activeClients)
          setExpiringTicketCount(expiringTickets.length)
          setTodaysSessions(sessions)
          setRecentRecords(records)
          setRecordStats(stats)
          setSessionStats(sessStats)
          setDailyTrend(trend)
          setClientRanking(ranking)
          setGoalCategories(goals)

          // アラートリストを作成
          const alertList: AlertItemProps[] = []

          // 非アクティブ顧客のアラート（最大3件）
          inactiveClients.slice(0, 3).forEach((client) => {
            alertList.push({
              type: 'inactive',
              clientId: client.client_id,
              clientName: client.client_name,
              message: `${client.days_inactive}日間記録なし`,
              severity: 'high',
            })
          })

          // 期限切れ間近チケットのアラート
          expiringTickets.forEach((ticket) => {
            alertList.push({
              type: 'ticket_expiring',
              clientId: ticket.client_id,
              clientName: ticket.client_name,
              message: `チケット残り${ticket.remaining_sessions}回（期限: ${ticket.days_until_expiry}日後）`,
              severity: 'medium',
            })
          })

          // 未実施プランのアラート
          if (undonePlans > 0) {
            alertList.push({
              type: 'workout_undone',
              message: `今週 ${undonePlans} 件のワークアウトプランが未実施です`,
              severity: 'medium',
            })
          }

          setAlerts(alertList)
        } catch (err) {
          console.error('ダッシュボードデータ取得エラー:', err)
        }
      }

      setLoading(false)
    }

    fetchDashboardData()
  }, [setUserName])

  if (loading) {
    return <DashboardSkeleton />
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-7xl mx-auto p-6 space-y-6">
        {/* ヘッダー */}
        <div className="mb-8">
          <h1 className="text-3xl font-bold text-gray-900 mb-2">
            {getGreeting()}、{userName}さん！
          </h1>
          <p className="text-gray-600">{formatted}</p>
        </div>

        {/* KPI カード */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          <StatCard
            icon={<UsersIcon />}
            label="担当顧客数"
            value={clientCount}
            suffix="人"
            color="teal"
            href="/clients"
          />
          <StatCard
            icon={<ChatIcon />}
            label="今週のメッセージ"
            value={messageCount}
            suffix="件"
            color="teal"
            href="/message"
          />
          <StatCard
            icon={<ChartIcon />}
            label="アクティブ顧客"
            value={activeClientCount}
            suffix="人"
            color="green"
          />
          <StatCard
            icon={<TicketIcon />}
            label="要対応チケット"
            value={expiringTicketCount}
            suffix="件"
            color="red"
            href="/clients"
          />
        </div>

        {/* 本日の予定 */}
        <TodaysSchedule sessions={todaysSessions} />

        {/* 最近の記録 */}
        <RecentRecordsTimeline records={recentRecords} stats={recordStats} />

        {/* アクティビティ概況チャート */}
        <ActivityOverview
          sessionStats={sessionStats}
          recordStats={recordStats}
          dailyTrend={dailyTrend}
          clientRanking={clientRanking}
        />

        {/* 目標達成プログレス */}
        <GoalProgressCarousel categories={goalCategories} />

        {/* メインコンテンツエリア */}
        <div className="grid grid-cols-1 lg:grid-cols-2 gap-6">
          {/* 最近のメッセージ */}
          <MessagePreviewList messages={recentMessages} />

          {/* 要確認エリア */}
          <AlertList alerts={alerts} />
        </div>

        {/* クイックアクション */}
        <QuickActions />
      </div>
    </main>
  )
}
