import { useRouter } from 'next/navigation'
import { Card } from '@/components/ui/card'
import { ProfileAvatar } from './ProfileAvatar'
import type { Client } from '@/types/client'
import { GENDER_OPTIONS, PURPOSE_OPTIONS } from '@/types/client'

type ClientCardProps = {
  client: Client
}

const genderBorderColors = {
  male: 'border-l-blue-500',
  female: 'border-l-pink-500',
  other: 'border-l-yellow-500',
}

export function ClientCard({ client }: ClientCardProps) {
  const router = useRouter()

  const handleClick = () => {
    router.push(`/clients/${client.client_id}`)
  }

  const handleMessageClick = (e: React.MouseEvent) => {
    e.stopPropagation() // カード全体のクリックイベントを防ぐ
    router.push(`/message?clientId=${client.client_id}`)
  }

  return (
    <Card
      className={`border-l-4 ${genderBorderColors[client.gender]} cursor-pointer hover:shadow-lg transition-shadow`}
      onClick={handleClick}
    >
      <div className="p-4">
        <div className="flex items-center space-x-4">
          <ProfileAvatar client={client} size="md" />

          <div className="flex-1 min-w-0">
            <h3 className="text-lg font-semibold truncate">{client.name}</h3>
            <div className="flex items-center space-x-2 text-sm text-gray-600 mt-1">
              <span>{GENDER_OPTIONS[client.gender]}</span>
              <span>•</span>
              <span>{client.age}歳</span>
            </div>
            <div className="mt-1">
              <span className="inline-block px-2 py-1 text-xs rounded-full bg-gray-100 text-gray-700">
                {PURPOSE_OPTIONS[client.purpose]}
              </span>
            </div>
          </div>
        </div>

        <div className="flex space-x-2 mt-4">
          <button
            onClick={handleMessageClick}
            className="flex-1 px-4 py-2 text-sm bg-blue-600 text-white rounded-lg hover:bg-blue-700 transition-colors"
          >
            メッセージ
          </button>
        </div>
      </div>
    </Card>
  )
}
