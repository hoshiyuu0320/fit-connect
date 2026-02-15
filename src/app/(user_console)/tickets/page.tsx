'use client'

import { useEffect, useState } from 'react'
import { Tabs, TabsList, TabsTrigger, TabsContent } from '@/components/ui/tabs'
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

export default function TicketsPage() {
  const [trainerId, setTrainerId] = useState<string>('')
  const [templates, setTemplates] = useState<TicketTemplate[]>([])
  const [tickets, setTickets] = useState<TicketWithClient[]>([])
  const [subscriptions, setSubscriptions] = useState<TicketSubscription[]>([])
  const [clients, setClients] = useState<Client[]>([])
  const [loading, setLoading] = useState(true)

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

  if (loading) {
    return (
      <div className="h-[calc(100vh-48px)] flex items-center justify-center bg-gray-50">
        <div className="text-gray-600">読み込み中...</div>
      </div>
    )
  }

  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-6xl mx-auto p-6 space-y-6">
        {/* ページタイトル */}
        <div>
          <h1 className="text-2xl font-bold text-gray-900">チケット管理</h1>
          <p className="text-sm text-gray-500 mt-1">テンプレート作成・チケット発行・月契約管理</p>
        </div>

        {/* 3タブ */}
        <Tabs defaultValue="templates" className="w-full">
          <TabsList className="grid w-full grid-cols-3">
            <TabsTrigger value="templates">テンプレート</TabsTrigger>
            <TabsTrigger value="issue">チケット発行</TabsTrigger>
            <TabsTrigger value="subscriptions">月契約</TabsTrigger>
          </TabsList>

          <TabsContent value="templates">
            <TemplateList
              templates={templates}
              trainerId={trainerId}
              onRefetch={refetchTemplates}
            />
          </TabsContent>

          <TabsContent value="issue">
            <div className="space-y-6">
              <IssueTicketSection
                templates={templates}
                clients={clients}
                onIssued={refetchTickets}
              />
              <IssuedTicketList
                tickets={tickets}
                onRefetch={refetchTickets}
              />
            </div>
          </TabsContent>

          <TabsContent value="subscriptions">
            <SubscriptionList
              subscriptions={subscriptions}
              templates={templates}
              clients={clients}
              onRefetch={refetchSubscriptions}
            />
          </TabsContent>
        </Tabs>
      </div>
    </div>
  )
}
