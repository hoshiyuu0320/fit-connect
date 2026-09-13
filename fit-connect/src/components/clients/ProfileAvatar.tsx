'use client'

import Image from 'next/image'
import { cn } from '@/lib/utils'
import { useStorageUrl } from '@/lib/supabase/signedStorageUrls'
import type { Client } from '@/types/client'

type ProfileAvatarProps = {
  // gender を渡さない呼び出し元（「今日の対応」など）は中立色のイニシャルになる
  client: Pick<Client, 'name' | 'profile_image_url'> & { gender?: Client['gender'] }
  size?: 'sm' | 'md' | 'lg'
  className?: string
}

const sizeClasses = {
  sm: 'w-10 h-10 text-sm',
  md: 'w-16 h-16 text-lg',
  lg: 'w-24 h-24 text-2xl',
}

const genderColors = {
  male: 'bg-blue-500',
  female: 'bg-pink-500',
  other: 'bg-yellow-500',
}

// 性別を渡さないときの色。赤・黄を重要度の表示に使う画面で、アバターの色と紛れないようにする
const neutralColors = 'bg-[#F1F5F9] text-[#475569]'

export function ProfileAvatar({ client, size = 'md', className }: ProfileAvatarProps) {
  // 値はパス or フルURL（レガシー）の両対応。署名URLへ解決してから表示する
  const avatarUrl = useStorageUrl(client.profile_image_url, 'client-avatars')

  // 名前からイニシャルを取得（最大2文字）
  const getInitials = (name: string): string => {
    if (!name) return '?'
    return name.slice(0, 2).toUpperCase()
  }

  const initials = getInitials(client.name)
  const bgColor = client.gender ? genderColors[client.gender] : neutralColors

  if (avatarUrl) {
    return (
      <div className={cn('relative rounded-full overflow-hidden', sizeClasses[size], className)}>
        <Image
          src={avatarUrl}
          alt={client.name}
          fill
          className="object-cover"
          unoptimized
        />
      </div>
    )
  }

  return (
    <div
      className={cn(
        'rounded-full flex items-center justify-center text-white font-bold',
        sizeClasses[size],
        bgColor,
        className
      )}
    >
      {initials}
    </div>
  )
}
