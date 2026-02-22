'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { Card, CardContent } from '@/components/ui/card'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import { ClientDetail, GENDER_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'
import EditClientModal from './EditClientModal'

type ClientHeaderProps = {
  client: ClientDetail
  onClientUpdated: () => void
  mode: 'info' | 'session'
  onModeChange: (mode: 'info' | 'session') => void
}

export function ClientHeader({ client, onClientUpdated, mode, onModeChange }: ClientHeaderProps) {
  const router = useRouter()
  const [isEditModalOpen, setIsEditModalOpen] = useState(false)

  return (
    <div className="space-y-4">
      {/* Navigation Buttons */}
      <div className="flex items-center justify-between">
        <button
          onClick={() => router.push('/clients')}
          className="text-blue-600 hover:text-blue-700 flex items-center space-x-1 transition-colors"
        >
          <span>←</span>
          <span>顧客リストに戻る</span>
        </button>

        {/* モード切替トグル */}
        <div className="inline-flex rounded-lg border p-1 bg-gray-100">
          <button
            onClick={() => onModeChange('info')}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-all ${
              mode === 'info'
                ? 'bg-white shadow-sm text-gray-900'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            情報
          </button>
          <button
            onClick={() => onModeChange('session')}
            className={`px-4 py-1.5 rounded-md text-sm font-medium transition-all ${
              mode === 'session'
                ? 'bg-white shadow-sm text-gray-900'
                : 'text-gray-500 hover:text-gray-700'
            }`}
          >
            セッション
          </button>
        </div>

        {mode === 'info' ? (
          <div className="flex items-center space-x-2">
            <button
              onClick={() => setIsEditModalOpen(true)}
              className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-50 transition-colors"
            >
              編集
            </button>
            <button
              onClick={() => router.push(`/message?clientId=${client.client_id}`)}
              className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
            >
              メッセージ
            </button>
          </div>
        ) : (
          <div className="w-[180px]" />
        )}
      </div>

      {/* Profile Card - 情報モードのみ表示 */}
      {mode === 'info' && <Card>
        <CardContent className="pt-6">
          <div className="flex items-start space-x-6">
            {/* Avatar */}
            <ProfileAvatar client={client} size="lg" />

            {/* Profile Information */}
            <div className="flex-1 space-y-4">
              {/* Name and Basic Info */}
              <div>
                <h2 className="text-2xl font-bold text-gray-900">{client.name}</h2>
                <div className="flex items-center space-x-2 text-sm text-gray-600 mt-1">
                  <span>{GENDER_OPTIONS[client.gender]}</span>
                  <span>•</span>
                  <span>{client.age}歳</span>
                  {client.occupation && (
                    <>
                      <span>•</span>
                      <span>{client.occupation}</span>
                    </>
                  )}
                </div>
              </div>

              {/* Stats Grid */}
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4 text-sm">
                <div>
                  <div className="text-gray-500 text-xs mb-1">身長</div>
                  <div className="font-semibold text-gray-900">{client.height} cm</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs mb-1">目標体重</div>
                  <div className="font-semibold text-gray-900">{client.target_weight} kg</div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs mb-1">現在の体重</div>
                  <div className="font-semibold text-gray-900">
                    {client.current_weight ? `${client.current_weight} kg` : '記録なし'}
                  </div>
                </div>
                <div>
                  <div className="text-gray-500 text-xs mb-1">目的</div>
                  <div className="font-semibold text-gray-900">{PURPOSE_OPTIONS[client.purpose]}</div>
                </div>
              </div>

              {/* Goal Description */}
              {client.goal_description && (
                <div className="pt-4 border-t border-gray-200">
                  <div className="text-xs text-gray-500 mb-1">目標</div>
                  <div className="text-sm text-gray-800 leading-relaxed">{client.goal_description}</div>
                </div>
              )}
            </div>
          </div>
        </CardContent>
      </Card>}

      <EditClientModal
        open={isEditModalOpen}
        onOpenChange={setIsEditModalOpen}
        client={client}
        onUpdated={onClientUpdated}
      />
    </div>
  )
}
