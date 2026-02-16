'use client'

import { useEffect, useState } from 'react'
import { useRouter } from 'next/navigation'
import { supabase } from '@/lib/supabase'
import { getTrainerDetail } from '@/lib/supabase/getTrainerDetail'
import { useUserStore } from '@/store/userStore'
import { ProfileSection } from '@/components/settings/ProfileSection'
import { NotificationSection } from '@/components/settings/NotificationSection'
import { AccountSection } from '@/components/settings/AccountSection'
import type { Trainer } from '@/types/trainer'

export default function SettingsPage() {
  const router = useRouter()
  const [trainer, setTrainer] = useState<Trainer | null>(null)
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    const fetchTrainerData = async () => {
      setLoading(true)

      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()

        if (!user) {
          router.push('/login')
          return
        }

        const trainerData = await getTrainerDetail(user.id)
        setTrainer(trainerData)
      } catch (error) {
        console.error('設定ページデータ取得エラー:', error)
        router.push('/login')
      } finally {
        setLoading(false)
      }
    }

    fetchTrainerData()
  }, [router])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
  }

  if (!trainer) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="text-gray-600">設定情報を読み込めませんでした</div>
      </div>
    )
  }

  const handleUpdate = async () => {
    const {
      data: { user },
    } = await supabase.auth.getUser()
    if (user) {
      const trainerData = await getTrainerDetail(user.id)
      setTrainer(trainerData)
    }
  }

  const handleLogout = async () => {
    await supabase.auth.signOut()
    useUserStore.getState().clearUser()
    router.push('/login')
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-2xl mx-auto p-6 space-y-6">
        {/* ヘッダー */}
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-gray-900">設定</h1>
        </div>

        {/* プロフィール情報 */}
        <ProfileSection trainer={trainer} onUpdate={handleUpdate} />

        {/* 通知設定 */}
        <NotificationSection />

        {/* アカウント管理 */}
        <AccountSection onLogout={handleLogout} />
      </div>
    </main>
  )
}
