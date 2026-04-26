'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { ProfileAvatar } from '@/components/clients/ProfileAvatar'
import { ClientDetail, GENDER_OPTIONS } from '@/types/client'
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

  const genderLabel = GENDER_OPTIONS[client.gender]
  const attributeText = [
    genderLabel,
    client.age ? `${client.age}歳` : null,
    client.occupation || null,
  ]
    .filter(Boolean)
    .join(' / ')

  return (
    <>
      {/* Sticky Header */}
      <div className="sticky top-0 z-10 bg-[#F8FAFC] border-b border-[#E2E8F0] py-3 px-6">
        <div className="flex items-center">
          {/* Breadcrumb */}
          <div className="flex items-center gap-1.5 text-sm">
            <button
              onClick={() => router.push('/clients')}
              className="text-[#94A3B8] hover:text-[#64748B] transition-colors"
            >
              顧客一覧
            </button>
            <span className="text-[#94A3B8]">›</span>
            <span className="text-[#0F172A] font-semibold">{client.name}</span>
          </div>

          {/* Spacer */}
          <div className="flex-1" />

          {/* Right Controls */}
          <div className="flex items-center gap-3">
            {/* Mode Toggle */}
            <div className="inline-flex rounded-md border border-[#E2E8F0] overflow-hidden bg-[#F8FAFC]">
              <button
                onClick={() => onModeChange('info')}
                className={`px-3 py-1.5 text-sm font-medium transition-all ${
                  mode === 'info'
                    ? 'bg-white border-r border-[#E2E8F0] text-[#0F172A]'
                    : 'text-[#94A3B8] hover:text-[#64748B]'
                }`}
              >
                情報
              </button>
              <button
                onClick={() => onModeChange('session')}
                className={`px-3 py-1.5 text-sm font-medium transition-all ${
                  mode === 'session'
                    ? 'bg-[#14B8A6] text-white'
                    : 'text-[#94A3B8] hover:text-[#64748B]'
                }`}
              >
                {mode === 'session' ? 'セッション中' : 'セッション'}
              </button>
            </div>

            {/* Info mode buttons */}
            {mode === 'info' && (
              <>
                <button
                  onClick={() => setIsEditModalOpen(true)}
                  className="px-3 py-1.5 text-sm font-medium border border-[#E2E8F0] text-[#64748B] rounded-md hover:border-[#14B8A6] hover:text-[#14B8A6] transition-colors"
                >
                  編集
                </button>
                <button
                  onClick={() => router.push(`/message?clientId=${client.client_id}`)}
                  className="px-3 py-1.5 text-sm font-medium bg-[#14B8A6] text-white rounded-md hover:bg-[#0D9488] transition-colors"
                >
                  メッセージ
                </button>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Profile Row (scrolls with page) */}
      <div className="flex items-center gap-3 px-6 pt-4 pb-2">
        <ProfileAvatar client={client} size="sm" />
        <div>
          <p className="text-lg font-bold text-[#0F172A] leading-tight">{client.name}</p>
          {attributeText && (
            <p className="text-xs text-[#94A3B8] mt-0.5">{attributeText}</p>
          )}
        </div>
      </div>

      <EditClientModal
        open={isEditModalOpen}
        onOpenChange={setIsEditModalOpen}
        client={client}
        onUpdated={onClientUpdated}
      />
    </>
  )
}
