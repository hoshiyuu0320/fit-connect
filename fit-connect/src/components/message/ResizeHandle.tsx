'use client'

import { cn } from '@/lib/utils'

interface ResizeHandleProps {
  /**
   * ハンドルを重ねる辺。
   * left/right=縦ハンドル（幅調整）、top/bottom=横ハンドル（高さ調整）。
   */
  side: 'left' | 'right' | 'top' | 'bottom'
  /** ドラッグ中かどうか（視覚ラインの強調に使用） */
  isDragging: boolean
  /** スクリーンリーダー用ラベル */
  ariaLabel: string
  /** useResizablePanel が返す handleProps（role/aria/tabIndex/onMouseDown/onKeyDown） */
  handleProps: Record<string, unknown>
}

/**
 * パネル境界に絶対配置で重ねる、全長の細いドラッグ用ハンドル。
 * 状態は持たず、見た目とイベント配線のみを担当する（親要素は relative 前提）。
 */
export function ResizeHandle({
  side,
  isDragging,
  ariaLabel,
  handleProps,
}: ResizeHandleProps) {
  const isVerticalHandle = side === 'left' || side === 'right'

  return (
    <div
      {...handleProps}
      aria-label={ariaLabel}
      className={cn(
        'absolute z-20 flex items-center justify-center group',
        'focus:outline-none focus-visible:ring-2 focus-visible:ring-inset focus-visible:ring-[#14B8A6]',
        isVerticalHandle
          ? 'top-0 h-full w-1.5 cursor-col-resize'
          : 'left-0 w-full h-1.5 cursor-row-resize',
        side === 'right' && 'right-0 translate-x-1/2',
        side === 'left' && 'left-0 -translate-x-1/2',
        side === 'bottom' && 'bottom-0 translate-y-1/2',
        side === 'top' && 'top-0 -translate-y-1/2'
      )}
    >
      {/* 視覚ライン。平常時は透明（既存の border が #E2E8F0 を担う） */}
      <div
        className={cn(
          'transition-colors duration-150 motion-reduce:transition-none',
          isVerticalHandle ? 'h-full' : 'w-full',
          isDragging
            ? cn('bg-[#0F172A]', isVerticalHandle ? 'w-0.5' : 'h-0.5')
            : cn(
                'bg-transparent group-hover:bg-[#14B8A6]',
                isVerticalHandle ? 'w-px' : 'h-px'
              )
        )}
      />
    </div>
  )
}
