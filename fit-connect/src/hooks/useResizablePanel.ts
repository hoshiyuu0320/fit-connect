import { useCallback, useEffect, useRef, useState } from 'react'

type ResizeAxis = 'x' | 'y'
type ResizeEdge = 'left' | 'right' | 'top' | 'bottom'

interface UseResizablePanelOptions {
  /** リサイズ軸。'x'=幅 / 'y'=高さ */
  axis: ResizeAxis
  /** localStorage に保存するキー */
  storageKey: string
  /** SSR/初期描画で用いる既定サイズ(px) */
  defaultSize: number
  /** 下限サイズ(px) */
  min: number
  /** 上限サイズ(px) */
  max: number
  /**
   * ハンドルが置かれる辺。
   * axis 'x': 'right'（パネル右端）はマウスを右に動かすと拡大、'left'（パネル左端）は縮小。
   * axis 'y': 'bottom'（パネル下端）はマウスを下に動かすと拡大、'top'（パネル上端）は縮小。
   */
  edge: ResizeEdge
}

interface ResizeHandleProps {
  role: 'separator'
  'aria-orientation': 'vertical' | 'horizontal'
  tabIndex: number
  'aria-valuenow': number
  'aria-valuemin': number
  'aria-valuemax': number
  onMouseDown: (e: React.MouseEvent) => void
  onKeyDown: (e: React.KeyboardEvent) => void
  // ResizeHandle / RecordSidePanel が受け取る Record<string, unknown> へそのまま渡せるようにする
  [key: string]: unknown
}

interface UseResizablePanelResult {
  size: number
  isDragging: boolean
  handleProps: ResizeHandleProps
}

const KEYBOARD_STEP = 16
const KEYBOARD_STEP_LARGE = 48

/**
 * 1パネル分の「サイズ state ＋ localStorage 永続化 ＋ min/max クランプ
 * ＋ マウスドラッグ ＋ キーボード操作」を担う汎用フック（幅・高さ両対応）。
 *
 * SSR安全のため初期サイズは defaultSize 固定で、マウント後に localStorage を反映する。
 */
export function useResizablePanel({
  axis,
  storageKey,
  defaultSize,
  min,
  max,
  edge,
}: UseResizablePanelOptions): UseResizablePanelResult {
  const [size, setSize] = useState(defaultSize)
  const [isDragging, setIsDragging] = useState(false)

  // ドラッグ開始時のマウス座標・サイズ
  const startPosRef = useRef(0)
  const startSizeRef = useRef(defaultSize)
  // mousemove のたびに更新する「最新確定サイズ」。mouseup での保存に使う（stale closure 回避）
  const latestSizeRef = useRef(defaultSize)

  const isHorizontalAxis = axis === 'x'
  // 開始辺（'left'/'top'）はドラッグ方向の符号を反転する
  const isStartEdge = edge === 'left' || edge === 'top'
  const cursorStyle = isHorizontalAxis ? 'col-resize' : 'row-resize'

  const clamp = useCallback(
    (value: number) => Math.min(max, Math.max(min, value)),
    [min, max]
  )

  // min/max が動的に変わった時（例: ウィンドウリサイズで max が縮む）、現在 size を新しい範囲へ再クランプ
  useEffect(() => {
    setSize((prev) => clamp(prev))
  }, [clamp])

  const writeStorage = useCallback(
    (value: number) => {
      try {
        window.localStorage.setItem(storageKey, String(value))
      } catch {
        // localStorage 非対応・容量超過などは握りつぶしてデフォルト挙動を維持
      }
    },
    [storageKey]
  )

  // マウント後に localStorage から復元
  useEffect(() => {
    try {
      const stored = window.localStorage.getItem(storageKey)
      if (stored !== null) {
        const parsed = parseInt(stored, 10)
        if (Number.isFinite(parsed)) {
          const clamped = clamp(parsed)
          setSize(clamped)
          latestSizeRef.current = clamped
        }
      }
    } catch {
      // 読み取り失敗時は defaultSize を維持
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [storageKey])

  // ドラッグ用 window リスナーは ref 経由で常に最新ロジックを参照しつつ、
  // 登録/解除する関数参照は安定させる（後始末を確実に行うため）。
  const moveHandlerRef = useRef<(e: MouseEvent) => void>(() => {})
  const upHandlerRef = useRef<() => void>(() => {})

  const detach = useCallback(() => {
    window.removeEventListener('mousemove', moveHandlerRef.current)
    window.removeEventListener('mouseup', upHandlerRef.current)
    document.body.style.cursor = ''
    document.body.style.userSelect = ''
  }, [])

  const onMouseDown = useCallback(
    (e: React.MouseEvent) => {
      e.preventDefault()
      startPosRef.current = isHorizontalAxis ? e.clientX : e.clientY
      startSizeRef.current = size
      latestSizeRef.current = size
      setIsDragging(true)

      const handleMove = (ev: MouseEvent) => {
        const current = isHorizontalAxis ? ev.clientX : ev.clientY
        const delta = current - startPosRef.current
        const raw = isStartEdge
          ? startSizeRef.current - delta
          : startSizeRef.current + delta
        const clamped = clamp(raw)
        latestSizeRef.current = clamped
        setSize(clamped)
      }

      const handleUp = () => {
        window.removeEventListener('mousemove', handleMove)
        window.removeEventListener('mouseup', handleUp)
        document.body.style.cursor = ''
        document.body.style.userSelect = ''
        setIsDragging(false)
        // 確定サイズのみ保存（ドラッグ中は書かない）
        writeStorage(latestSizeRef.current)
      }

      moveHandlerRef.current = handleMove
      upHandlerRef.current = handleUp
      window.addEventListener('mousemove', handleMove)
      window.addEventListener('mouseup', handleUp)
      document.body.style.cursor = cursorStyle
      document.body.style.userSelect = 'none'
    },
    [size, isHorizontalAxis, isStartEdge, cursorStyle, clamp, writeStorage]
  )

  const onKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const positiveKey = isHorizontalAxis ? 'ArrowRight' : 'ArrowDown'
      const negativeKey = isHorizontalAxis ? 'ArrowLeft' : 'ArrowUp'
      if (e.key !== positiveKey && e.key !== negativeKey) return
      e.preventDefault()
      const step = e.shiftKey ? KEYBOARD_STEP_LARGE : KEYBOARD_STEP
      const dir = e.key === positiveKey ? 1 : -1
      const signed = isStartEdge ? -dir : dir
      const next = clamp(size + signed * step)
      latestSizeRef.current = next
      setSize(next)
      writeStorage(next)
    },
    [size, isHorizontalAxis, isStartEdge, clamp, writeStorage]
  )

  // ドラッグ途中でのアンマウントに備え、リスナー解除と body スタイル復元を保証
  useEffect(() => {
    return () => {
      detach()
    }
  }, [detach])

  return {
    size,
    isDragging,
    handleProps: {
      role: 'separator',
      'aria-orientation': isHorizontalAxis ? 'vertical' : 'horizontal',
      tabIndex: 0,
      'aria-valuenow': size,
      'aria-valuemin': min,
      'aria-valuemax': max,
      onMouseDown,
      onKeyDown,
    },
  }
}
