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
import { useUserStore } from '@/store/userStore'
import { StatCard } from '@/components/dashboard/StatCard'
import { MessagePreviewList } from '@/components/dashboard/MessagePreviewList'
import { QuickActions } from '@/components/dashboard/QuickActions'
import { AlertList } from '@/components/dashboard/AlertList'
import { TodaysSchedule } from '@/components/dashboard/TodaysSchedule'
import type { RecentMessage } from '@/lib/supabase/getRecentMessages'
import type { AlertItemProps } from '@/components/dashboard/AlertItem'
import type { TodaysSession } from '@/lib/supabase/getTodaysSessions'
import React from 'react'

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
          ] = await Promise.all([
            getClientCount(user.id),
            getRecentMessageCount(user.id),
            getRecentMessages(user.id, 5),
            getActiveClientCount(user.id),
            getExpiringTickets(user.id),
            getInactiveClients(user.id),
            getTodaysSessions(user.id),
          ])

          setClientCount(clients)
          setMessageCount(messages)
          setRecentMessages(recentMsgs)
          setActiveClientCount(activeClients)
          setExpiringTicketCount(expiringTickets.length)
          setTodaysSessions(sessions)

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
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
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
          <StatCard icon="👥" label="担当顧客数" value={clientCount} suffix="人" />
          <StatCard icon="💬" label="今週のメッセージ" value={messageCount} suffix="件" />
          <StatCard icon="✅" label="アクティブ顧客" value={activeClientCount} suffix="人" />
          <StatCard icon="⏰" label="要対応チケット" value={expiringTicketCount} suffix="件" />
        </div>

        {/* 本日の予定 */}
        <TodaysSchedule sessions={todaysSessions} />

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
