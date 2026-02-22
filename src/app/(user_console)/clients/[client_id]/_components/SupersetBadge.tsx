"use client"

type SupersetBadgeProps = {
  color?: string
}

export function SupersetBadge({ color = 'border-purple-400' }: SupersetBadgeProps) {
  return (
    <div className={`flex items-center gap-2 py-1 px-3 my-1 border-l-4 ${color}`}>
      <span className="text-xs font-medium text-purple-600">スーパーセット</span>
    </div>
  )
}
