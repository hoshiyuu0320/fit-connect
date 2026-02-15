'use client'

import { useEffect, useState, useCallback } from 'react'
import { supabase } from '@/lib/supabase'
import { searchClients } from '@/lib/supabase/searchClients'
import { ClientCard } from '@/components/clients/ClientCard'
import ClientInviteModal from '@/components/clients/ClientInviteModal'
import type { Client } from '@/types/client'
import { AGE_RANGE_OPTIONS, PURPOSE_OPTIONS, GENDER_OPTIONS } from '@/types/client'
import { QrCode } from 'lucide-react'

export default function ClientsPage() {
  const [clients, setClients] = useState<Client[]>([])
  const [loading, setLoading] = useState(true)
  const [trainerId, setTrainerId] = useState<string | null>(null)

  const [inviteModalOpen, setInviteModalOpen] = useState(false)

  // フィルター状態
  const [searchQuery, setSearchQuery] = useState('')
  const [genderFilter, setGenderFilter] = useState<Client['gender'] | 'all'>('all')
  const [ageRangeFilter, setAgeRangeFilter] = useState(0) // AGE_RANGE_OPTIONSのindex
  const [purposeFilter, setPurposeFilter] = useState<Client['purpose'] | 'all'>('all')

  // 検索・フィルター実行
  const loadClients = useCallback(async (userId: string) => {
    setLoading(true)
    try {
      const ageRange = AGE_RANGE_OPTIONS[ageRangeFilter]

      const results = await searchClients({
        trainerId: userId,
        searchQuery: searchQuery || undefined,
        gender: genderFilter === 'all' ? undefined : genderFilter,
        ageRange: ageRangeFilter === 0 ? undefined : { min: ageRange.min, max: ageRange.max },
        purpose: purposeFilter === 'all' ? undefined : purposeFilter,
      })

      setClients(results)
    } catch (error) {
      console.error('顧客取得エラー：', error)
    } finally {
      setLoading(false)
    }
  }, [searchQuery, genderFilter, ageRangeFilter, purposeFilter])

  // 初回データ取得
  useEffect(() => {
    const fetchClients = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        setTrainerId(user.id)
        await loadClients(user.id)
      }
      setLoading(false)
    }
    fetchClients()
  }, [loadClients])

  // フィルター変更時に再検索
  useEffect(() => {
    if (trainerId) {
      loadClients(trainerId)
    }
  }, [loadClients, trainerId])

  return (
    <div className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-7xl mx-auto p-6">
        {/* ヘッダー */}
        <div className="mb-6 flex items-center justify-between">
          <div>
            <h1 className="text-2xl font-bold text-gray-900">顧客管理</h1>
            <p className="text-gray-600 mt-1">担当する顧客の一覧を表示しています</p>
          </div>
          <button
            onClick={() => setInviteModalOpen(true)}
            className="flex items-center gap-2 px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors text-sm font-medium"
          >
            <QrCode className="h-4 w-4" />
            クライアントを招待
          </button>
        </div>

        {/* 検索バー */}
        <div className="mb-4">
          <input
            type="text"
            value={searchQuery}
            onChange={(e) => setSearchQuery(e.target.value)}
            placeholder="名前で検索..."
            className="w-full px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          />
        </div>

        {/* フィルター */}
        <div className="flex flex-wrap gap-3 mb-6">
          {/* 性別フィルター */}
          <select
            value={genderFilter}
            onChange={(e) => setGenderFilter(e.target.value as typeof genderFilter)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          >
            <option value="all">すべての性別</option>
            {Object.entries(GENDER_OPTIONS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>

          {/* 年齢層フィルター */}
          <select
            value={ageRangeFilter}
            onChange={(e) => setAgeRangeFilter(Number(e.target.value))}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          >
            {AGE_RANGE_OPTIONS.map((range, index) => (
              <option key={index} value={index}>
                {range.label}
              </option>
            ))}
          </select>

          {/* 目的フィルター */}
          <select
            value={purposeFilter}
            onChange={(e) => setPurposeFilter(e.target.value as typeof purposeFilter)}
            className="px-4 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-transparent outline-none"
          >
            <option value="all">すべての目的</option>
            {Object.entries(PURPOSE_OPTIONS).map(([key, label]) => (
              <option key={key} value={key}>
                {label}
              </option>
            ))}
          </select>
        </div>

        {/* ローディング */}
        {loading && (
          <div className="flex justify-center items-center py-12">
            <div className="text-gray-600">読み込み中...</div>
          </div>
        )}

        {/* 顧客カードグリッド */}
        {!loading && clients.length > 0 && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
            {clients.map((client) => (
              <ClientCard key={client.client_id} client={client} />
            ))}
          </div>
        )}

        {/* 空の状態 */}
        {!loading && clients.length === 0 && (
          <div className="flex flex-col items-center justify-center py-12 text-center">
            <svg
              xmlns="http://www.w3.org/2000/svg"
              className="h-24 w-24 text-gray-400 mb-4"
              fill="none"
              viewBox="0 0 24 24"
              stroke="currentColor"
            >
              <path
                strokeLinecap="round"
                strokeLinejoin="round"
                strokeWidth={1.5}
                d="M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z"
              />
            </svg>
            <h3 className="text-xl font-semibold text-gray-700 mb-2">顧客が見つかりませんでした</h3>
            <p className="text-gray-500">
              {searchQuery || genderFilter !== 'all' || ageRangeFilter !== 0 || purposeFilter !== 'all'
                ? '検索条件を変更してみてください'
                : 'まだ顧客が登録されていません'}
            </p>
          </div>
        )}
      </div>

      {trainerId && (
        <ClientInviteModal
          open={inviteModalOpen}
          onOpenChange={setInviteModalOpen}
          trainerId={trainerId}
        />
      )}
    </div>
  )
}