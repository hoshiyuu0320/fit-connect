'use client'

import { useRouter } from 'next/navigation'
import {
  RadialBarChart,
  RadialBar,
  PieChart,
  Pie,
  Cell,
  AreaChart,
  Area,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  ResponsiveContainer,
  BarChart,
  Bar,
} from 'recharts'
import type { SessionStats } from '@/lib/supabase/getSessionStats'
import type { RecordStats } from '@/lib/supabase/getRecordStats'
import type { DailyRecordPoint } from '@/lib/supabase/getDailyRecordTrend'
import type { ClientActivityRank } from '@/lib/supabase/getClientActivityRanking'

interface ActivityOverviewProps {
  sessionStats: SessionStats
  recordStats: RecordStats
  dailyTrend: DailyRecordPoint[]
  clientRanking: ClientActivityRank[]
}

// --- カスタムTooltip ---
interface TooltipPayloadItem {
  name: string
  value: number
  color: string
}

interface CustomTooltipProps {
  active?: boolean
  label?: string
  payload?: TooltipPayloadItem[]
}

function LineChartTooltip({ active, label, payload }: CustomTooltipProps) {
  if (!active || !payload || payload.length === 0) return null
  return (
    <div
      style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
      className="bg-white border border-[#E2E8F0] rounded-[6px] px-3 py-2 text-xs shadow-sm"
    >
      <p className="text-[#475569] font-medium mb-1">{label}</p>
      {payload.map((item) => (
        <p key={item.name} style={{ color: item.color }} className="leading-5">
          {item.name}: <span className="font-semibold">{item.value}件</span>
        </p>
      ))}
    </div>
  )
}

// --- セクションカードの共通ラッパー ---
function ChartCard({
  title,
  subtitle,
  children,
  headerRight,
}: {
  title: string
  subtitle: string
  children: React.ReactNode
  headerRight?: React.ReactNode
}) {
  return (
    <div className="bg-[#F8FAFC] border border-[#F1F5F9] rounded-[6px] p-5">
      <div className="flex items-start justify-between mb-4">
        <div>
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[12px] font-semibold text-[#475569]"
          >
            {title}
          </p>
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[11px] text-[#94A3B8] mt-0.5"
          >
            {subtitle}
          </p>
        </div>
        {headerRight && <div>{headerRight}</div>}
      </div>
      {children}
    </div>
  )
}

// --- 凡例アイテム ---
function LegendItem({ color, label, value }: { color: string; label: string; value?: string }) {
  return (
    <div className="flex items-center gap-1.5">
      <span
        className="inline-block w-2 h-2 rounded-full flex-shrink-0"
        style={{ backgroundColor: color }}
      />
      <span
        style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
        className="text-[12px] text-[#475569]"
      >
        {label}
        {value !== undefined && (
          <span className="text-[#94A3B8] ml-1">{value}</span>
        )}
      </span>
    </div>
  )
}

// --- 1. セッション消化率リングゲージ ---
function SessionCompletionGauge({ sessionStats }: { sessionStats: SessionStats }) {
  const rate = sessionStats.completionRate
  const gaugeData = [{ value: rate, fill: '#14B8A6' }]

  return (
    <ChartCard title="セッション消化率" subtitle="今月の進捗">
      <div className="flex flex-col items-center">
        <div className="relative">
          <ResponsiveContainer width={120} height={120}>
            <RadialBarChart
              cx="50%"
              cy="50%"
              innerRadius="70%"
              outerRadius="90%"
              startAngle={90}
              endAngle={-270}
              data={gaugeData}
              barSize={10}
            >
              <RadialBar
                background={{ fill: '#F1F5F9' }}
                dataKey="value"
                cornerRadius={5}
                isAnimationActive={true}
              />
            </RadialBarChart>
          </ResponsiveContainer>
          <div className="absolute inset-0 flex items-center justify-center">
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[28px] font-bold text-[#0F172A] leading-none"
            >
              {rate}
              <span className="text-[14px] font-semibold text-[#475569]">%</span>
            </span>
          </div>
        </div>

        <div className="mt-4 space-y-1.5 w-full">
          <div className="flex items-center justify-between">
            <LegendItem color="#14B8A6" label="完了" />
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[12px] font-medium text-[#0F172A]"
            >
              {sessionStats.completed}回
            </span>
          </div>
          <div className="flex items-center justify-between">
            <LegendItem color="#CBD5E1" label="予定" />
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[12px] font-medium text-[#0F172A]"
            >
              {sessionStats.scheduled}回
            </span>
          </div>
          <div className="flex items-center justify-between">
            <LegendItem color="#DC262699" label="キャンセル" />
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[12px] font-medium text-[#0F172A]"
            >
              {sessionStats.cancelled}回
            </span>
          </div>
        </div>
      </div>
    </ChartCard>
  )
}

// --- 2. 記録種別ドーナツチャート ---
function RecordTypeDonut({ recordStats }: { recordStats: RecordStats }) {
  const totalRecords = recordStats.mealCount + recordStats.exerciseCount + recordStats.weightCount

  const donutData = [
    { name: '食事', value: recordStats.mealCount, color: '#F97316' },
    { name: '運動', value: recordStats.exerciseCount, color: '#A855F7' },
    { name: '体重', value: recordStats.weightCount, color: '#14B8A6' },
  ].filter((d) => d.value > 0)

  const emptyData = [{ name: 'データなし', value: 1, color: '#F1F5F9' }]
  const isEmpty = totalRecords === 0

  return (
    <ChartCard title="記録種別の割合" subtitle="今週の内訳">
      <div className="flex flex-col items-center">
        <div className="relative">
          <ResponsiveContainer width={120} height={120}>
            <PieChart>
              <Pie
                data={isEmpty ? emptyData : donutData}
                cx="50%"
                cy="50%"
                innerRadius={35}
                outerRadius={50}
                dataKey="value"
                strokeWidth={0}
                isAnimationActive={!isEmpty}
              >
                {(isEmpty ? emptyData : donutData).map((entry, idx) => (
                  <Cell key={idx} fill={entry.color} />
                ))}
              </Pie>
            </PieChart>
          </ResponsiveContainer>
          <div className="absolute inset-0 flex items-center justify-center">
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[22px] font-bold text-[#0F172A] leading-none"
            >
              {totalRecords}
              <span className="text-[11px] font-medium text-[#94A3B8] ml-0.5">件</span>
            </span>
          </div>
        </div>

        {isEmpty ? (
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="mt-4 text-[12px] text-[#94A3B8]"
          >
            今週の記録はありません
          </p>
        ) : (
          <div className="mt-4 space-y-1.5 w-full">
            {[
              { name: '食事', value: recordStats.mealCount, color: '#F97316' },
              { name: '運動', value: recordStats.exerciseCount, color: '#A855F7' },
              { name: '体重', value: recordStats.weightCount, color: '#14B8A6' },
            ].map((item) => {
              const pct =
                totalRecords > 0 ? Math.round((item.value / totalRecords) * 100) : 0
              return (
                <div key={item.name} className="flex items-center justify-between">
                  <LegendItem color={item.color} label={item.name} />
                  <span
                    style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
                    className="text-[12px] font-medium text-[#0F172A]"
                  >
                    {item.value}件{' '}
                    <span className="text-[#94A3B8]">({pct}%)</span>
                  </span>
                </div>
              )
            })}
          </div>
        )}
      </div>
    </ChartCard>
  )
}

// --- 3. 顧客記録率ゲージ ---
function ClientRecordRateGauge({ recordStats }: { recordStats: RecordStats }) {
  const { activeRecordingClients, totalActiveClients } = recordStats
  const rate =
    totalActiveClients > 0
      ? Math.round((activeRecordingClients / totalActiveClients) * 100)
      : 0

  const gaugeData = [{ value: rate, fill: '#0F172A' }]

  return (
    <ChartCard title="顧客記録率" subtitle="今週記録した顧客の割合">
      <div className="flex flex-col items-center">
        <div className="relative">
          <ResponsiveContainer width={120} height={120}>
            <RadialBarChart
              cx="50%"
              cy="50%"
              innerRadius="70%"
              outerRadius="90%"
              startAngle={90}
              endAngle={-270}
              data={gaugeData}
              barSize={10}
            >
              <RadialBar
                background={{ fill: '#F1F5F9' }}
                dataKey="value"
                cornerRadius={5}
                isAnimationActive={true}
              />
            </RadialBarChart>
          </ResponsiveContainer>
          <div className="absolute inset-0 flex items-center justify-center">
            <span
              style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
              className="text-[28px] font-bold text-[#0F172A] leading-none"
            >
              {rate}
              <span className="text-[14px] font-semibold text-[#475569]">%</span>
            </span>
          </div>
        </div>

        <div className="mt-4 text-center">
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[#0F172A]"
          >
            <span className="text-[13px] font-bold">{activeRecordingClients}</span>
            <span className="text-[12px] text-[#94A3B8]"> / {totalActiveClients} 人が記録</span>
          </p>
        </div>
      </div>
    </ChartCard>
  )
}

// --- 4. 7日間推移折れ線グラフ ---
function DailyTrendChart({ dailyTrend }: { dailyTrend: DailyRecordPoint[] }) {
  const isEmpty = dailyTrend.length === 0

  const legendRight = (
    <div className="flex items-center gap-3">
      <LegendItem color="#F97316" label="食事" />
      <LegendItem color="#14B8A6" label="体重" />
      <LegendItem color="#A855F7" label="運動" />
    </div>
  )

  return (
    <ChartCard
      title="記録数の推移（過去7日間）"
      subtitle="日別の食事・体重・運動記録件数"
      headerRight={legendRight}
    >
      {isEmpty ? (
        <div className="h-[180px] flex items-center justify-center">
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[12px] text-[#94A3B8]"
          >
            データなし
          </p>
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={180}>
          <AreaChart data={dailyTrend} margin={{ top: 4, right: 4, left: -20, bottom: 0 }}>
            <defs>
              <linearGradient id="mealGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#F97316" stopOpacity={0.06} />
                <stop offset="95%" stopColor="#F97316" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="weightGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#14B8A6" stopOpacity={0.06} />
                <stop offset="95%" stopColor="#14B8A6" stopOpacity={0} />
              </linearGradient>
              <linearGradient id="exerciseGrad" x1="0" y1="0" x2="0" y2="1">
                <stop offset="5%" stopColor="#A855F7" stopOpacity={0.06} />
                <stop offset="95%" stopColor="#A855F7" stopOpacity={0} />
              </linearGradient>
            </defs>
            <CartesianGrid stroke="#F1F5F9" strokeDasharray="0" vertical={false} />
            <XAxis
              dataKey="label"
              tick={{
                fontSize: 10,
                fill: '#94A3B8',
                fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif",
              }}
              axisLine={false}
              tickLine={false}
            />
            <YAxis
              allowDecimals={false}
              tick={{
                fontSize: 10,
                fill: '#94A3B8',
                fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif",
              }}
              axisLine={false}
              tickLine={false}
            />
            <Tooltip content={<LineChartTooltip />} />
            <Area
              type="monotone"
              dataKey="meal"
              name="食事"
              stroke="#F97316"
              strokeWidth={1.5}
              fill="url(#mealGrad)"
              dot={false}
              activeDot={{ r: 3, fill: '#F97316' }}
            />
            <Area
              type="monotone"
              dataKey="weight"
              name="体重"
              stroke="#14B8A6"
              strokeWidth={1.5}
              fill="url(#weightGrad)"
              dot={false}
              activeDot={{ r: 3, fill: '#14B8A6' }}
            />
            <Area
              type="monotone"
              dataKey="exercise"
              name="運動"
              stroke="#A855F7"
              strokeWidth={1.5}
              fill="url(#exerciseGrad)"
              dot={false}
              activeDot={{ r: 3, fill: '#A855F7' }}
            />
          </AreaChart>
        </ResponsiveContainer>
      )}
    </ChartCard>
  )
}

// --- 5. 顧客アクティビティランキング横棒グラフ ---
const BAR_OPACITIES = [1, 0.85, 0.7, 0.55, 0.4]

interface RankingBarLabelProps {
  x?: number
  y?: number
  width?: number
  height?: number
  value?: number
}

function RankingBarLabel(props: RankingBarLabelProps) {
  const { x = 0, y = 0, width = 0, height = 0, value = 0 } = props
  return (
    <text
      x={x + width + 6}
      y={y + height / 2}
      dy={1}
      textAnchor="start"
      fontSize={11}
      fill="#475569"
      fontFamily="'Plus Jakarta Sans', 'Noto Sans JP', sans-serif"
    >
      {value}件
    </text>
  )
}

function ClientActivityRankingChart({
  clientRanking,
}: {
  clientRanking: ClientActivityRank[]
}) {
  const router = useRouter()
  const isEmpty = clientRanking.length === 0
  const chartHeight = Math.max(clientRanking.length * 44 + 16, 80)

  // BarChartのonClickは全体でのみ機能するため、独自クリックハンドリング用データを付与
  const data = clientRanking.map((item, idx) => ({
    name: item.clientName,
    value: item.totalCount,
    clientId: item.clientId,
    opacity: BAR_OPACITIES[idx] ?? 0.4,
  }))

  return (
    <ChartCard title="顧客アクティビティランキング" subtitle="今週の記録件数 TOP5">
      {isEmpty ? (
        <div className="h-[80px] flex items-center justify-center">
          <p
            style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
            className="text-[12px] text-[#94A3B8]"
          >
            データなし
          </p>
        </div>
      ) : (
        <ResponsiveContainer width="100%" height={chartHeight}>
          <BarChart
            layout="vertical"
            data={data}
            margin={{ top: 0, right: 48, left: 0, bottom: 0 }}
            onClick={(chartData) => {
              const params = chartData as unknown as { activePayload?: Array<{ payload: { clientId: string } }> }
              if (params?.activePayload && params.activePayload.length > 0) {
                const clientId = params.activePayload[0]?.payload?.clientId
                if (clientId) {
                  router.push(`/clients/${clientId}`)
                }
              }
            }}
            className="cursor-pointer"
          >
            <XAxis type="number" hide />
            <YAxis
              type="category"
              dataKey="name"
              width={80}
              tick={{
                fontSize: 11,
                fill: '#475569',
                fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif",
              }}
              axisLine={false}
              tickLine={false}
            />
            <Bar
              dataKey="value"
              radius={[0, 3, 3, 0]}
              isAnimationActive={true}
              label={<RankingBarLabel />}
            >
              {data.map((entry, idx) => (
                <Cell
                  key={idx}
                  fill={`rgba(20, 184, 166, ${entry.opacity})`}
                />
              ))}
            </Bar>
          </BarChart>
        </ResponsiveContainer>
      )}
    </ChartCard>
  )
}

// --- メインコンポーネント ---
export function ActivityOverview({
  sessionStats,
  recordStats,
  dailyTrend,
  clientRanking,
}: ActivityOverviewProps) {
  return (
    <section className="bg-white border border-[#E2E8F0] rounded-[6px] p-6">
      {/* セクションタイトル */}
      <h2
        style={{ fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}
        className="text-[15px] font-bold text-[#0F172A] mb-5"
      >
        アクティビティ概況
      </h2>

      {/* 上段: 3カラム */}
      <div className="grid grid-cols-1 lg:grid-cols-3 gap-4 mb-4">
        <SessionCompletionGauge sessionStats={sessionStats} />
        <RecordTypeDonut recordStats={recordStats} />
        <ClientRecordRateGauge recordStats={recordStats} />
      </div>

      {/* 下段1: 7日間推移 */}
      <div className="mb-4">
        <DailyTrendChart dailyTrend={dailyTrend} />
      </div>

      {/* 下段2: 顧客アクティビティランキング */}
      <div>
        <ClientActivityRankingChart clientRanking={clientRanking} />
      </div>
    </section>
  )
}
