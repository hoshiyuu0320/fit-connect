'use client'

import { useEffect, useMemo, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { getTicketTemplates } from '@/lib/supabase/getTicketTemplates'
import { getTicketsByTrainer } from '@/lib/supabase/getTicketsByTrainer'
import { getTicketSubscriptions } from '@/lib/supabase/getTicketSubscriptions'
import { getClients } from '@/lib/supabase/getClients'
import type { TicketTemplate, TicketWithClient, TicketSubscription, Client } from '@/types/client'
import { TemplateList } from './_components/TemplateList'
import { IssueTicketSection } from './_components/IssueTicketSection'
import { IssuedTicketList } from './_components/IssuedTicketList'
import { SubscriptionList } from './_components/SubscriptionList'
import { LayoutGrid, Ticket, Hash, AlertTriangle } from 'lucide-react'
import { TicketsSkeleton } from './_components/TicketsSkeleton'

type ActiveTab = 'templates' | 'issued' | 'subscriptions'

export default function TicketsPage() {
  const [trainerId, setTrainerId] = useState<string>('')
  const [templates, setTemplates] = useState<TicketTemplate[]>([])
  const [tickets, setTickets] = useState<TicketWithClient[]>([])
  const [subscriptions, setSubscriptions] = useState<TicketSubscription[]>([])
  const [clients, setClients] = useState<Client[]>([])
  const [loading, setLoading] = useState(true)
  const [activeTab, setActiveTab] = useState<ActiveTab>('templates')

  useEffect(() => {
    const fetchData = async () => {
      try {
        const { data: { user } } = await supabase.auth.getUser()
        if (!user) return
        setTrainerId(user.id)

        const [templatesData, ticketsData, subscriptionsData, clientsData] = await Promise.all([
          getTicketTemplates(user.id),
          getTicketsByTrainer(user.id),
          getTicketSubscriptions(user.id),
          getClients(user.id),
        ])
        setTemplates(templatesData)
        setTickets(ticketsData)
        setSubscriptions(subscriptionsData)
        setClients(clientsData)
      } catch (error) {
        console.error('データ取得エラー:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [])

  const refetchTemplates = async () => {
    if (!trainerId) return
    try {
      const templatesData = await getTicketTemplates(trainerId)
      setTemplates(templatesData)
    } catch (error) {
      console.error('テンプレート再取得エラー:', error)
    }
  }

  const refetchTickets = async () => {
    if (!trainerId) return
    try {
      const ticketsData = await getTicketsByTrainer(trainerId)
      setTickets(ticketsData)
    } catch (error) {
      console.error('チケット再取得エラー:', error)
    }
  }

  const refetchSubscriptions = async () => {
    if (!trainerId) return
    try {
      const subscriptionsData = await getTicketSubscriptions(trainerId)
      setSubscriptions(subscriptionsData)
    } catch (error) {
      console.error('月契約再取得エラー:', error)
    }
  }

  // KPI計算
  const kpi = useMemo(() => {
    const recurringCount = templates.filter((t) => t.is_recurring).length
    const singleCount = templates.filter((t) => !t.is_recurring).length

    const now = new Date()
    const in30Days = new Date(now.getTime() + 30 * 24 * 60 * 60 * 1000)
    // 期限切れ = 日付超過 OR 残回数0（getTicketStatusと同じロジック）
    const activeTickets = tickets.filter((t) => {
      const dateValid = !t.valid_until || new Date(t.valid_until) >= now
      return dateValid && t.remaining_sessions > 0
    })
    const expiredTickets = tickets.filter((t) => {
      const dateExpired = t.valid_until && new Date(t.valid_until) < now
      return dateExpired || t.remaining_sessions === 0
    })
    // 期限切れ間近 = 有効チケットのうち30日以内に期限切れ
    const nearExpiry = activeTickets.filter((t) => {
      if (!t.valid_until) return false
      const exp = new Date(t.valid_until)
      return exp <= in30Days
    })
    const totalRemaining = activeTickets.reduce((sum, t) => sum + (t.remaining_sessions ?? 0), 0)
    const clientsWithActive = new Set(activeTickets.map((t) => t.client_id)).size

    return {
      templateCount: templates.length,
      recurringCount,
      singleCount,
      issuedCount: tickets.length,
      activeCount: activeTickets.length,
      expiredCount: expiredTickets.length,
      totalRemaining,
      clientsWithActive,
      nearExpiryCount: nearExpiry.length,
    }
  }, [templates, tickets])

  const tabs: { key: ActiveTab; label: string; count: number }[] = [
    { key: 'templates', label: 'テンプレート', count: templates.length },
    { key: 'issued', label: '発行済みチケット', count: tickets.length },
    { key: 'subscriptions', label: '月契約', count: subscriptions.length },
  ]

  if (loading) {
    return <TicketsSkeleton />
  }

  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto" style={{ backgroundColor: '#F8FAFC' }}>
      <div className="max-w-6xl mx-auto p-6 space-y-6">

        {/* ページタイトル */}
        <div>
          <h1 className="text-2xl font-bold" style={{ color: '#0F172A' }}>チケット管理</h1>
          <p className="text-sm mt-1" style={{ color: '#94A3B8' }}>テンプレート作成・チケット発行・月契約管理</p>
        </div>

        {/* KPIサマリーバー */}
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4">
          {/* テンプレート数 */}
          <div
            className="bg-white border rounded-md p-4"
            style={{ borderColor: '#E2E8F0' }}
          >
            <div className="flex items-center gap-3 mb-2">
              <div
                className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
                style={{ backgroundColor: '#F0FDFA' }}
              >
                <LayoutGrid size={18} style={{ color: '#14B8A6' }} />
              </div>
              <span className="text-sm font-medium" style={{ color: '#475569' }}>テンプレート数</span>
            </div>
            <p className="text-2xl font-bold" style={{ color: '#0F172A' }}>{kpi.templateCount}</p>
            <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>都度 {kpi.singleCount} / 月契約 {kpi.recurringCount}</p>
          </div>

          {/* 発行済みチケット数 */}
          <div
            className="bg-white border rounded-md p-4"
            style={{ borderColor: '#E2E8F0' }}
          >
            <div className="flex items-center gap-3 mb-2">
              <div
                className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
                style={{ backgroundColor: '#EFF6FF' }}
              >
                <Ticket size={18} style={{ color: '#2563EB' }} />
              </div>
              <span className="text-sm font-medium" style={{ color: '#475569' }}>発行済みチケット</span>
            </div>
            <p className="text-2xl font-bold" style={{ color: '#0F172A' }}>{kpi.issuedCount}</p>
            <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>有効 {kpi.activeCount} / 期限切れ {kpi.expiredCount}</p>
          </div>

          {/* 総残回数 */}
          <div
            className="bg-white border rounded-md p-4"
            style={{ borderColor: '#E2E8F0' }}
          >
            <div className="flex items-center gap-3 mb-2">
              <div
                className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
                style={{ backgroundColor: '#F0FDF4' }}
              >
                <Hash size={18} style={{ color: '#16A34A' }} />
              </div>
              <span className="text-sm font-medium" style={{ color: '#475569' }}>総残回数</span>
            </div>
            <p className="text-2xl font-bold" style={{ color: '#0F172A' }}>{kpi.totalRemaining}</p>
            <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>{kpi.clientsWithActive}名分の有効チケット</p>
          </div>

          {/* 期限切れ間近 */}
          <div
            className="bg-white border rounded-md p-4"
            style={{ borderColor: kpi.nearExpiryCount > 0 ? '#FCD34D' : '#E2E8F0' }}
          >
            <div className="flex items-center gap-3 mb-2">
              <div
                className="w-9 h-9 rounded-md flex items-center justify-center flex-shrink-0"
                style={{ backgroundColor: kpi.nearExpiryCount > 0 ? '#FFFBEB' : '#F8FAFC' }}
              >
                <AlertTriangle
                  size={18}
                  style={{ color: kpi.nearExpiryCount > 0 ? '#F59E0B' : '#94A3B8' }}
                />
              </div>
              <span className="text-sm font-medium" style={{ color: '#475569' }}>期限切れ間近</span>
            </div>
            <p
              className="text-2xl font-bold"
              style={{ color: kpi.nearExpiryCount > 0 ? '#F59E0B' : '#0F172A' }}
            >
              {kpi.nearExpiryCount}
            </p>
            <p className="text-xs mt-1" style={{ color: '#94A3B8' }}>30日以内に期限切れ</p>
          </div>
        </div>

        {/* アンダーラインタブ */}
        <div>
          <div
            className="flex items-center gap-1 border-b"
            style={{ borderColor: '#E2E8F0' }}
          >
            {tabs.map((tab) => {
              const isActive = activeTab === tab.key
              return (
                <button
                  key={tab.key}
                  onClick={() => setActiveTab(tab.key)}
                  className="flex items-center gap-2 px-4 py-3 text-sm font-medium transition-colors relative"
                  style={{
                    color: isActive ? '#0F172A' : '#94A3B8',
                    borderBottom: isActive ? '2px solid #14B8A6' : '2px solid transparent',
                    marginBottom: '-1px',
                  }}
                >
                  {tab.label}
                  <span
                    className="inline-flex items-center justify-center text-xs font-medium px-2 py-0.5 rounded-md"
                    style={{
                      backgroundColor: isActive ? '#F0FDFA' : '#F1F5F9',
                      color: isActive ? '#14B8A6' : '#94A3B8',
                    }}
                  >
                    {tab.count}
                  </span>
                </button>
              )
            })}
          </div>

          {/* タブコンテンツ */}
          <div className="mt-6">
            {activeTab === 'templates' && (
              <TemplateList
                templates={templates}
                trainerId={trainerId}
                onRefetch={refetchTemplates}
              />
            )}

            {activeTab === 'issued' && (
              <div className="space-y-6">
                <IssueTicketSection
                  templates={templates}
                  clients={clients}
                  onIssued={refetchTickets}
                />
                <IssuedTicketList
                  tickets={tickets}
                  clients={clients}
                  onRefetch={refetchTickets}
                />
              </div>
            )}

            {activeTab === 'subscriptions' && (
              <SubscriptionList
                subscriptions={subscriptions}
                templates={templates}
                clients={clients}
                onRefetch={refetchSubscriptions}
              />
            )}
          </div>
        </div>

      </div>
    </div>
  )
}
