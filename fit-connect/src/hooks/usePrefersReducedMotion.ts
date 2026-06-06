'use client'

import { useEffect, useState } from 'react'

/**
 * OSの「視差効果を減らす / reduce motion」設定を検知する。
 * SSRでは false を返し、マウント後に実値へ同期する。
 */
export function usePrefersReducedMotion(): boolean {
  const [reduced, setReduced] = useState(false)

  useEffect(() => {
    const mq = window.matchMedia('(prefers-reduced-motion: reduce)')
    setReduced(mq.matches)
    const handler = (e: MediaQueryListEvent) => setReduced(e.matches)
    mq.addEventListener('change', handler)
    return () => mq.removeEventListener('change', handler)
  }, [])

  return reduced
}
