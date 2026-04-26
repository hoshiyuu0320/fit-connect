'use client'

import { useEffect, useState, useCallback } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { searchClients } from '@/lib/supabase/searchClients'
import { getClientWorkoutStatuses } from '@/lib/supabase/getClientWorkoutStatuses'
import { getClientListStats, type ClientListStats } from '@/lib/supabase/getClientListStats'
import { getClientListMetrics, type ClientMetrics } from '@/lib/supabase/getClientListMetrics'
import { ClientCard } from '@/components/clients/ClientCard'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import ClientInviteModal from '@/components/clients/ClientInviteModal'
import type { Client } from '@/types/client'
import { AGE_RANGE_OPTIONS, PURPOSE_OPTIONS, GENDER_OPTIONS } from '@/types/client'
import {
  QrCode,
  Users,
  Activity,
  Calendar,
  AlertTriangle,
  Search,
  LayoutGrid,
  List,
  X,
  MessageSquare,
} from 'lucide-react'

type SortBy = 'nameAsc' | 'lastActivity' | 'createdAt'

export default function ClientsPage() {
  const router = useRouter()
  const [clients, setClients] = useState<Client[]>([])
  const [loading, setLoading] = useState(true)
  const [trainerId, setTrainerId] = useState<string | null>(null)
  const [workoutStatuses, setWorkoutStatuses] = useState<Record<string, 'completed' | 'partial' | 'pending' | null>>({})
  const [stats, setStats] = useState<ClientListStats | null>(null)
  const [metricsMap, setMetricsMap] = useState<Map<string, ClientMetrics>>(new Map())
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')
  const [sortBy, setSortBy] = useState<SortBy>('nameAsc')

  const [inviteModalOpen, setInviteModalOpen] = useState(false)

  // フィルター状態
  const [searchQuery, setSearchQuery] = useState('')
  const [genderFilter, setGenderFilter] = useState<Client['gender'] | 'all'>('all')
  const [ageRangeFilter, setAgeRangeFilter] = useState(0)
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

      // メトリクス取得
      if (results.length > 0) {
        const clientIds = results.map((c) => c.client_id)
        try {
          const metricsArr = await getClientListMetrics(clientIds)
          const map = new Map<string, ClientMetrics>()
          for (const m of metricsArr) {
            map.set(m.clientId, m)
          }
          setMetricsMap(map)
        } catch (err) {
          console.error('メトリクス取得エラー:', err)
        }
      }
    } catch (error) {
      console.error('顧客取得エラー：', error)
    } finally {
      setLoading(false)
    }
  }, [searchQuery, genderFilter, ageRangeFilter, purposeFilter])

  // ワークアウトステータス取得
  const loadWorkoutStatuses = useCallback(async (userId: string) => {
    try {
      const statuses = await getClientWorkoutStatuses(userId)
      setWorkoutStatuses(statuses)
    } catch (error) {
      console.error('ワークアウトステータス取得エラー:', error)
    }
  }, [])

  // 初回データ取得
  useEffect(() => {
    const fetchClients = async () => {
      const {
        data: { user },
      } = await supabase.auth.getUser()

      if (user) {
        setTrainerId(user.id)
        await Promise.all([
          loadClients(user.id),
          loadWorkoutStatuses(user.id),
          getClientListStats(user.id)
            .then((s) => setStats(s))
            .catch((err) => console.error('統計取得エラー:', err)),
        ])
      }
      setLoading(false)
    }
    fetchClients()
  }, [loadClients, loadWorkoutStatuses])

  // フィルター変更時に再検索
  useEffect(() => {
    if (trainerId) {
      loadClients(trainerId)
    }
  }, [loadClients, trainerId])

  // ソート処理
  const sortedClients = [...clients].sort((a, b) => {
    if (sortBy === 'nameAsc') {
      return a.name.localeCompare(b.name, 'ja')
    }
    if (sortBy === 'lastActivity') {
      // メトリクスが存在しない場合はcreated_at降順にフォールバック
      return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
    }
    // createdAt: created_at降順
    return new Date(b.created_at).getTime() - new Date(a.created_at).getTime()
  })

  // アクティブフィルター判定
  const hasActiveFilters =
    genderFilter !== 'all' || ageRangeFilter !== 0 || purposeFilter !== 'all'

  const resetAllFilters = () => {
    setGenderFilter('all')
    setAgeRangeFilter(0)
    setPurposeFilter('all')
  }

  // ローディング中スケルトン
  if (loading) {
    return (
      <div className="h-[calc(100vh-56px)] overflow-y-auto bg-[#F8FAFC]">
        <div className="max-w-7xl mx-auto px-8 py-7 space-y-5">
          {/* stats スケルトン */}
          <div className="grid grid-cols-4 gap-3">
            {[...Array(4)].map((_, i) => (
              <div key={i} className="bg-white border border-[#E2E8F0] rounded-md p-3.5 animate-pulse">
                <div className="flex items-center gap-3">
                  <div className="w-9 h-9 rounded-md bg-gray-100 shrink-0" />
                  <div className="space-y-1.5 flex-1">
                    <div className="h-5 w-10 bg-gray-100 rounded" />
                    <div className="h-3 w-20 bg-gray-100 rounded" />
                  </div>
                </div>
              </div>
            ))}
          </div>
          {/* ツールバー スケルトン */}
          <div className="bg-white border border-[#E2E8F0] rounded-md p-4 animate-pulse">
            <div className="h-9 bg-gray-100 rounded-md" />
          </div>
          {/* カード スケルトン */}
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {[...Array(6)].map((_, i) => (
              <div key={i} className="bg-white border border-[#E2E8F0] rounded-md p-4 animate-pulse">
                <div className="flex items-center gap-3">
                  <div className="w-12 h-12 rounded-md bg-gray-100 shrink-0" />
                  <div className="space-y-2 flex-1">
                    <div className="h-4 w-24 bg-gray-100 rounded" />
                    <div className="h-3 w-32 bg-gray-100 rounded" />
                  </div>
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="h-[calc(100vh-56px)] overflow-y-auto bg-[#F8FAFC]">
      <div className="max-w-7xl mx-auto px-8 py-7 space-y-5">

        {/* ヘッダー */}
        <div className="flex items-center justify-between">
          <div>
            <h1 className="text-xl font-bold text-[#0F172A]">顧客管理</h1>
            <p className="text-xs text-[#94A3B8] mt-0.5">担当する顧客の一覧を表示しています</p>
          </div>
          <button
            onClick={() => setInviteModalOpen(true)}
            className="flex items-center gap-2 px-4 py-2 bg-[#14B8A6] text-white rounded-md hover:bg-[#0D9488] transition-colors text-sm font-medium"
          >
            <QrCode className="h-4 w-4" />
            クライアントを招待
          </button>
        </div>

        {/* 統計バー */}
        <div className="grid grid-cols-4 gap-3">
          {/* Total Clients */}
          <div className="bg-white border border-[#E2E8F0] rounded-md p-3.5">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-md bg-[#F0FDFA] flex items-center justify-center shrink-0">
                <Users className="w-4 h-4 text-[#14B8A6]" />
              </div>
              <div>
                <p className="text-[20px] font-bold text-[#0F172A] leading-none">
                  {stats?.totalClients ?? '-'}
                </p>
                <p className="text-[11px] text-[#94A3B8] mt-1">Total Clients</p>
              </div>
            </div>
          </div>

          {/* Active (7 days) */}
          <div className="bg-white border border-[#E2E8F0] rounded-md p-3.5">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-md bg-[#F0FDF4] flex items-center justify-center shrink-0">
                <Activity className="w-4 h-4 text-[#16A34A]" />
              </div>
              <div>
                <p className="text-[20px] font-bold text-[#0F172A] leading-none">
                  {stats?.activeClients ?? '-'}
                </p>
                <p className="text-[11px] text-[#94A3B8] mt-1">Active (7 days)</p>
              </div>
            </div>
          </div>

          {/* Today's Sessions */}
          <div className="bg-white border border-[#E2E8F0] rounded-md p-3.5">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-md bg-[#FFFBEB] flex items-center justify-center shrink-0">
                <Calendar className="w-4 h-4 text-[#D97706]" />
              </div>
              <div>
                <p className="text-[20px] font-bold text-[#0F172A] leading-none">
                  {stats?.todaySessions ?? '-'}
                </p>
                <p className="text-[11px] text-[#94A3B8] mt-1">Today&apos;s Sessions</p>
              </div>
            </div>
          </div>

          {/* Tickets Expiring */}
          <div className="bg-white border border-[#E2E8F0] rounded-md p-3.5">
            <div className="flex items-center gap-3">
              <div className="w-9 h-9 rounded-md bg-[#FEF2F2] flex items-center justify-center shrink-0">
                <AlertTriangle className="w-4 h-4 text-[#DC2626]" />
              </div>
              <div>
                <p className="text-[20px] font-bold text-[#0F172A] leading-none">
                  {stats?.expiringTickets ?? '-'}
                </p>
                <p className="text-[11px] text-[#94A3B8] mt-1">Tickets Expiring</p>
              </div>
            </div>
          </div>
        </div>

        {/* ツールバー */}
        <div className="bg-white border border-[#E2E8F0] rounded-md p-4">
          {/* 上段: 検索 + Grid/List切替 */}
          <div className="flex items-center gap-3">
            {/* 検索ボックス */}
            <div className="relative flex-1">
              <Search className="absolute left-2.5 top-1/2 -translate-y-1/2 w-4 h-4 text-[#94A3B8]" />
              <input
                type="text"
                value={searchQuery}
                onChange={(e) => setSearchQuery(e.target.value)}
                placeholder="名前で検索..."
                className="w-full pl-9 pr-3 py-2 text-sm border border-[#E2E8F0] rounded-md focus:outline-none focus:border-[#14B8A6] focus:ring-2 focus:ring-[#14B8A6]/10 text-[#0F172A] placeholder:text-[#94A3B8]"
              />
            </div>

            {/* Grid/List切替トグル */}
            <div className="bg-[#F8FAFC] border border-[#E2E8F0] rounded-md p-0.5 flex shrink-0">
              <button
                onClick={() => setViewMode('grid')}
                className={`p-1.5 rounded transition-colors ${
                  viewMode === 'grid'
                    ? 'bg-white shadow-sm text-[#0F172A]'
                    : 'text-[#94A3B8] hover:text-[#475569]'
                }`}
                title="グリッド表示"
              >
                <LayoutGrid className="w-4 h-4" />
              </button>
              <button
                onClick={() => setViewMode('list')}
                className={`p-1.5 rounded transition-colors ${
                  viewMode === 'list'
                    ? 'bg-white shadow-sm text-[#0F172A]'
                    : 'text-[#94A3B8] hover:text-[#475569]'
                }`}
                title="リスト表示"
              >
                <List className="w-4 h-4" />
              </button>
            </div>
          </div>

          {/* 下段: フィルター + ソート */}
          <div className="flex items-center gap-2 mt-3">
            {/* 性別フィルター */}
            <select
              value={genderFilter}
              onChange={(e) => setGenderFilter(e.target.value as typeof genderFilter)}
              className={`px-2.5 py-1.5 text-xs font-medium border rounded-md focus:outline-none focus:border-[#14B8A6] cursor-pointer ${
                genderFilter !== 'all'
                  ? 'border-[#14B8A6] bg-[#F0FDFA] text-[#14B8A6]'
                  : 'border-[#E2E8F0] text-[#475569]'
              }`}
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
              className={`px-2.5 py-1.5 text-xs font-medium border rounded-md focus:outline-none focus:border-[#14B8A6] cursor-pointer ${
                ageRangeFilter !== 0
                  ? 'border-[#14B8A6] bg-[#F0FDFA] text-[#14B8A6]'
                  : 'border-[#E2E8F0] text-[#475569]'
              }`}
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
              className={`px-2.5 py-1.5 text-xs font-medium border rounded-md focus:outline-none focus:border-[#14B8A6] cursor-pointer ${
                purposeFilter !== 'all'
                  ? 'border-[#14B8A6] bg-[#F0FDFA] text-[#14B8A6]'
                  : 'border-[#E2E8F0] text-[#475569]'
              }`}
            >
              <option value="all">すべての目的</option>
              {Object.entries(PURPOSE_OPTIONS).map(([key, label]) => (
                <option key={key} value={key}>
                  {label}
                </option>
              ))}
            </select>

            {/* ソートselect */}
            <div className="ml-auto">
              <select
                value={sortBy}
                onChange={(e) => setSortBy(e.target.value as SortBy)}
                className="px-2.5 py-1.5 text-xs font-medium border border-[#E2E8F0] rounded-md text-[#475569] focus:outline-none focus:border-[#14B8A6] cursor-pointer"
              >
                <option value="nameAsc">名前順 (A-Z)</option>
                <option value="lastActivity">最終アクティビティ順</option>
                <option value="createdAt">登録日順</option>
              </select>
            </div>
          </div>

          {/* アクティブフィルターバー */}
          {hasActiveFilters && (
            <div className="border-t border-[#E2E8F0] pt-3 mt-3 flex items-center gap-2 flex-wrap">
              <span className="text-xs text-[#94A3B8] font-medium shrink-0">Filters:</span>

              {genderFilter !== 'all' && (
                <span className="inline-flex items-center gap-1 bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded-md px-2 py-0.5 text-xs font-semibold">
                  {GENDER_OPTIONS[genderFilter]}
                  <button
                    onClick={() => setGenderFilter('all')}
                    className="hover:text-[#0D9488] ml-0.5"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              {ageRangeFilter !== 0 && (
                <span className="inline-flex items-center gap-1 bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded-md px-2 py-0.5 text-xs font-semibold">
                  {AGE_RANGE_OPTIONS[ageRangeFilter].label}
                  <button
                    onClick={() => setAgeRangeFilter(0)}
                    className="hover:text-[#0D9488] ml-0.5"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              {purposeFilter !== 'all' && (
                <span className="inline-flex items-center gap-1 bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded-md px-2 py-0.5 text-xs font-semibold">
                  {PURPOSE_OPTIONS[purposeFilter]}
                  <button
                    onClick={() => setPurposeFilter('all')}
                    className="hover:text-[#0D9488] ml-0.5"
                  >
                    <X className="w-3 h-3" />
                  </button>
                </span>
              )}

              <button
                onClick={resetAllFilters}
                className="text-xs text-[#94A3B8] underline hover:text-[#14B8A6] ml-1"
              >
                すべてリセット
              </button>
            </div>
          )}
        </div>

        {/* 結果件数 */}
        <p className="text-xs text-[#94A3B8]">{sortedClients.length}件のクライアント</p>

        {/* 顧客グリッド */}
        {sortedClients.length > 0 && viewMode === 'grid' && (
          <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-3">
            {sortedClients.map((client) => (
              <ClientCard
                key={client.client_id}
                client={client}
                workoutStatus={workoutStatuses[client.client_id] ?? null}
                metrics={metricsMap.get(client.client_id) ?? null}
              />
            ))}
          </div>
        )}

        {/* 顧客リスト */}
        {sortedClients.length > 0 && viewMode === 'list' && (
          <div className="space-y-1">
            {/* ヘッダー行 */}
            <div className="grid grid-cols-[2fr_80px_100px_80px_120px_100px_100px_80px] gap-3 px-4 py-2.5 text-[10px] font-semibold text-[#94A3B8] uppercase tracking-wider">
              <span>クライアント</span>
              <span>ステータス</span>
              <span>性別・年齢</span>
              <span>体重</span>
              <span>目的</span>
              <span>残チケット</span>
              <span>最終活動</span>
              <span>アクション</span>
            </div>

            {/* データ行 */}
            {sortedClients.map((client) => {
              const metrics = metricsMap.get(client.client_id) ?? null
              const workoutStatus = workoutStatuses[client.client_id] ?? null

              return (
                <div
                  key={client.client_id}
                  onClick={() => router.push(`/clients/${client.client_id}`)}
                  className="grid grid-cols-[2fr_80px_100px_80px_120px_100px_100px_80px] gap-3 items-center bg-white border border-[#E2E8F0] rounded-md px-4 py-3 cursor-pointer hover:border-[#14B8A6] hover:bg-[#F0FDFA] transition-colors"
                >
                  {/* クライアント名 */}
                  <div className="flex items-center gap-2.5 min-w-0">
                    <ProfileAvatar client={client} size="sm" />
                    <span className="text-sm font-medium text-[#0F172A] truncate">{client.name}</span>
                  </div>

                  {/* ステータス */}
                  <div>
                    {workoutStatus ? (
                      <span className={`inline-flex items-center px-1.5 py-0.5 rounded-md text-[10px] font-semibold ${
                        workoutStatus === 'completed'
                          ? 'bg-[#F0FDF4] text-[#16A34A] border border-[#BBF7D0]'
                          : workoutStatus === 'partial'
                          ? 'bg-[#FFFBEB] text-[#D97706] border border-[#FDE68A]'
                          : 'bg-[#F8FAFC] text-[#94A3B8] border border-[#E2E8F0]'
                      }`}>
                        {workoutStatus === 'completed' ? '完了' :
                         workoutStatus === 'partial' ? '一部完了' : '未実施'}
                      </span>
                    ) : (
                      <span className="text-[10px] text-[#94A3B8]">-</span>
                    )}
                  </div>

                  {/* 性別・年齢 */}
                  <div className="text-xs text-[#475569]">
                    {GENDER_OPTIONS[client.gender]} / {client.age}歳
                  </div>

                  {/* 体重 */}
                  <div className="text-xs text-[#475569]">
                    {metrics?.latestWeight != null ? `${metrics.latestWeight}kg` : '-'}
                  </div>

                  {/* 目的 */}
                  <div>
                    <span className="inline-block bg-[#F0FDFA] text-[#14B8A6] border border-[#CCFBF1] rounded-md px-1.5 py-0.5 text-[10px] font-semibold truncate max-w-full">
                      {PURPOSE_OPTIONS[client.purpose]}
                    </span>
                  </div>

                  {/* 残チケット */}
                  <div className={`text-xs font-medium ${
                    metrics?.remainingTickets === 0 ? 'text-[#DC2626] font-semibold' : 'text-[#475569]'
                  }`}>
                    {metrics != null ? `${metrics.remainingTickets}回` : '-'}
                  </div>

                  {/* 最終活動 */}
                  <div className="text-xs text-[#94A3B8]">
                    {/* メトリクスに最終活動日がないためcreated_atを表示 */}
                    {new Date(client.created_at).toLocaleDateString('ja-JP', { month: 'numeric', day: 'numeric' })}
                  </div>

                  {/* アクション */}
                  <div>
                    <button
                      onClick={(e) => {
                        e.stopPropagation()
                        router.push(`/message?clientId=${client.client_id}`)
                      }}
                      className="w-[30px] h-[30px] flex items-center justify-center border border-[#E2E8F0] rounded-md text-[#94A3B8] hover:border-[#14B8A6] hover:text-[#14B8A6] hover:bg-[#F0FDFA] transition-colors"
                      title="メッセージ"
                    >
                      <MessageSquare className="w-4 h-4" />
                    </button>
                  </div>
                </div>
              )
            })}
          </div>
        )}

        {/* 空の状態 */}
        {sortedClients.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 text-center">
            <div className="w-16 h-16 rounded-md bg-[#F0FDFA] flex items-center justify-center mb-4">
              <Users className="w-8 h-8 text-[#14B8A6]" />
            </div>
            <h3 className="text-base font-semibold text-[#475569] mb-1">顧客が見つかりませんでした</h3>
            <p className="text-sm text-[#94A3B8]">
              {searchQuery || hasActiveFilters
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
