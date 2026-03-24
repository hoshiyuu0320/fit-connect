'use client'

import { useState, useEffect, useCallback } from 'react'
import { Newspaper, RefreshCw, ExternalLink } from 'lucide-react'
import { formatDistanceToNow } from 'date-fns'
import { ja } from 'date-fns/locale'

interface NewsItem {
  title: string
  link: string
  source: string
  publishedAt: string
  snippet: string
}

function SkeletonCard() {
  return (
    <div className="bg-white rounded-md p-5 animate-pulse" style={{ border: '1px solid #E2E8F0' }}>
      <div className="flex items-center gap-3 mb-3">
        <div className="h-5 w-16 rounded" style={{ backgroundColor: '#E2E8F0' }} />
        <div className="h-4 w-20 rounded" style={{ backgroundColor: '#E2E8F0' }} />
      </div>
      <div className="h-5 w-3/4 rounded mb-2" style={{ backgroundColor: '#E2E8F0' }} />
      <div className="h-4 w-full rounded mb-1" style={{ backgroundColor: '#E2E8F0' }} />
      <div className="h-4 w-5/6 rounded" style={{ backgroundColor: '#E2E8F0' }} />
    </div>
  )
}

export default function AiNewsPage() {
  const [news, setNews] = useState<NewsItem[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(false)
  const [lastUpdated, setLastUpdated] = useState<Date | null>(null)
  const [refreshing, setRefreshing] = useState(false)

  const fetchNews = useCallback(async (isRefresh = false) => {
    if (isRefresh) {
      setRefreshing(true)
    } else {
      setLoading(true)
    }
    setError(false)

    try {
      const response = await fetch('/api/ai-news')
      if (!response.ok) {
        throw new Error('Failed to fetch news')
      }
      const data = await response.json()
      setNews(data.items ?? [])
      setLastUpdated(new Date())
    } catch (err) {
      console.error('Error fetching AI news:', err)
      setError(true)
    } finally {
      setLoading(false)
      setRefreshing(false)
    }
  }, [])

  useEffect(() => {
    fetchNews()
  }, [fetchNews])

  const handleRefresh = () => {
    fetchNews(true)
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto" style={{ backgroundColor: '#F8FAFC' }}>
      <div className="max-w-3xl mx-auto p-6 space-y-6">

        {/* ヘッダー */}
        <div className="flex items-start justify-between gap-4">
          <div>
            <h1 className="text-2xl font-bold" style={{ color: '#0F172A', fontFamily: "'Plus Jakarta Sans', 'Noto Sans JP', sans-serif" }}>
              AI開発ニュース
            </h1>
            <p className="mt-1 text-sm" style={{ color: '#64748B' }}>
              過去24時間のAI駆動開発に関する最新ニュース
            </p>
            {lastUpdated && (
              <p className="mt-1 text-xs" style={{ color: '#94A3B8' }}>
                最終更新:{' '}
                {formatDistanceToNow(lastUpdated, { addSuffix: true, locale: ja })}
              </p>
            )}
          </div>
          <button
            onClick={handleRefresh}
            disabled={loading || refreshing}
            className="flex items-center gap-2 text-sm font-medium px-4 py-2 rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            style={{
              backgroundColor: '#0F172A',
              color: '#FFFFFF',
              border: 'none',
              flexShrink: 0,
            }}
            onMouseEnter={(e) => {
              if (!loading && !refreshing) {
                e.currentTarget.style.backgroundColor = '#1E293B'
              }
            }}
            onMouseLeave={(e) => {
              e.currentTarget.style.backgroundColor = '#0F172A'
            }}
          >
            <RefreshCw
              size={14}
              className={refreshing ? 'animate-spin' : ''}
            />
            更新
          </button>
        </div>

        {/* ローディング状態 */}
        {loading && (
          <div className="space-y-4">
            {Array.from({ length: 5 }).map((_, i) => (
              <SkeletonCard key={i} />
            ))}
          </div>
        )}

        {/* エラー状態 */}
        {!loading && error && (
          <div
            className="flex flex-col items-center justify-center py-16 rounded-md"
            style={{ backgroundColor: '#FFFFFF', border: '1px solid #E2E8F0' }}
          >
            <p className="text-sm font-medium" style={{ color: '#0F172A' }}>
              ニュースの取得に失敗しました。再度お試しください。
            </p>
            <button
              onClick={() => fetchNews()}
              className="mt-4 text-sm font-medium px-4 py-2 rounded-md transition-colors"
              style={{
                backgroundColor: '#14B8A6',
                color: '#FFFFFF',
                border: 'none',
              }}
              onMouseEnter={(e) => {
                e.currentTarget.style.backgroundColor = '#0D9488'
              }}
              onMouseLeave={(e) => {
                e.currentTarget.style.backgroundColor = '#14B8A6'
              }}
            >
              再試行
            </button>
          </div>
        )}

        {/* 空の状態 */}
        {!loading && !error && news.length === 0 && (
          <div
            className="flex flex-col items-center justify-center py-16 rounded-md"
            style={{ backgroundColor: '#FFFFFF', border: '1px solid #E2E8F0' }}
          >
            <Newspaper size={40} style={{ color: '#CBD5E1' }} />
            <p className="mt-4 text-sm font-medium" style={{ color: '#94A3B8' }}>
              現在表示できるニュースがありません
            </p>
          </div>
        )}

        {/* ニュースカード一覧 */}
        {!loading && !error && news.length > 0 && (
          <div className="space-y-4">
            {news.map((item, index) => (
              <div
                key={index}
                className="bg-white rounded-md p-5"
                style={{ border: '1px solid #E2E8F0' }}
              >
                {/* ソース + 時間 */}
                <div className="flex items-center gap-3 mb-3">
                  <span
                    className="text-xs font-medium px-2 py-0.5 rounded"
                    style={{
                      backgroundColor: '#F0FDFA',
                      color: '#14B8A6',
                    }}
                  >
                    {item.source}
                  </span>
                  <span className="text-xs" style={{ color: '#94A3B8' }}>
                    {formatDistanceToNow(new Date(item.publishedAt), {
                      addSuffix: true,
                      locale: ja,
                    })}
                  </span>
                </div>

                {/* タイトル（リンク） */}
                <a
                  href={item.link}
                  target="_blank"
                  rel="noopener noreferrer"
                  className="group flex items-start gap-1"
                >
                  <span
                    className="text-sm font-semibold leading-snug group-hover:underline"
                    style={{ color: '#0F172A' }}
                  >
                    {item.title}
                  </span>
                  <ExternalLink
                    size={14}
                    className="flex-shrink-0 mt-0.5"
                    style={{ color: '#94A3B8' }}
                  />
                </a>

                {/* スニペット */}
                <p
                  className="mt-2 text-sm leading-relaxed line-clamp-2"
                  style={{ color: '#64748B' }}
                >
                  {item.snippet}
                </p>
              </div>
            ))}
          </div>
        )}
      </div>
    </main>
  )
}
