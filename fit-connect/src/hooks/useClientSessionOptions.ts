'use client'

import { useCallback, useEffect, useState } from 'react'
import { getClientSessions, type ClientSessionOption } from '@/lib/supabase/getClientSessions'

/** 選択肢の取得状態。'idle' は取得対象のクライアントが未確定 */
export type ClientSessionOptionsStatus = 'idle' | 'loading' | 'ready' | 'error'

export type UseClientSessionOptions = {
  sessions: ClientSessionOption[]
  status: ClientSessionOptionsStatus
  /** カルテの作成・更新・削除のあとに呼ぶ（「カルテ作成済み」ラベルを追随させる） */
  refetch: () => void
}

/**
 * カルテの「対象セッション」選択肢を取得する
 *
 * 取得状態を返すのは、読み込み中／失敗を黙って「紐づけない」に見せないため
 * （紐づけ忘れ防止という機能の目的が無言で無効化されるのを防ぐ）。
 */
export function useClientSessionOptions(clientId: string | null | undefined): UseClientSessionOptions {
  const [sessions, setSessions] = useState<ClientSessionOption[]>([])
  const [status, setStatus] = useState<ClientSessionOptionsStatus>(clientId ? 'loading' : 'idle')
  // 再取得のトリガー（カルテ側の変更を選択肢へ反映させる）
  const [reloadKey, setReloadKey] = useState(0)

  const refetch = useCallback(() => setReloadKey((key) => key + 1), [])

  useEffect(() => {
    if (!clientId) {
      setSessions([])
      setStatus('idle')
      return
    }

    let cancelled = false
    setStatus('loading')

    getClientSessions(clientId)
      .then((data) => {
        if (cancelled) return
        setSessions(data)
        setStatus('ready')
      })
      .catch((error) => {
        console.error('カルテ用セッション一覧取得エラー:', error)
        if (cancelled) return
        setSessions([])
        setStatus('error')
      })

    return () => {
      cancelled = true
    }
  }, [clientId, reloadKey])

  return { sessions, status, refetch }
}
