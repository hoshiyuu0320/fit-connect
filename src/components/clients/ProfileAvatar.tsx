import { cn } from '@/lib/utils'
import type { Client } from '@/types/client'

type ProfileAvatarProps = {
  client: Pick<Client, 'name' | 'gender' | 'profile_image_url'>
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

export function ProfileAvatar({ client, size = 'md', className }: ProfileAvatarProps) {
  // 名前からイニシャルを取得（最大2文字）
  const getInitials = (name: string): string => {
    if (!name) return '?'
    return name.slice(0, 2).toUpperCase()
  }

  const initials = getInitials(client.name)
  const bgColor = genderColors[client.gender]

  if (client.profile_image_url) {
    return (
      <div className={cn('relative rounded-full overflow-hidden', sizeClasses[size], className)}>
        <img
          src={client.profile_image_url}
          alt={client.name}
          className="w-full h-full object-cover"
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
