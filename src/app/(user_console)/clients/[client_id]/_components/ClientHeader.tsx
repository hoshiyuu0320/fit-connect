'use client'

import { useRouter } from 'next/navigation'
import { Card, CardContent } from '@/components/ui/card'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import { ClientDetail, GENDER_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'

type ClientHeaderProps = {
  client: ClientDetail
}

export function ClientHeader({ client }: ClientHeaderProps) {
  const router = useRouter()

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
        <button
          onClick={() => router.push(`/message?clientId=${client.client_id}`)}
          className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
        >
          メッセージ
        </button>
      </div>

      {/* Profile Card */}
      <Card>
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
      </Card>
    </div>
  )
}
