'use client'

// ================================================
// Storage 署名URL 解決（クライアント専用）
// ================================================
// フェーズ8.2 Storage private化に伴い、DB には「バケット相対パス」を保存し、
// 表示時に署名URL（TTL 3600秒）へ解決する。
// 純関数（splitFragment / isExternalUrl / extractStoragePath）と型は
// サーバー側と共有の storagePaths.ts に分離しており、本モジュールは
// React フックとブラウザクライアントを使うクライアント専用コードのみを持つ。

import { useEffect, useState } from 'react'
import {
  type StorageBucket,
  splitFragment,
  isExternalUrl,
  extractStoragePath,
} from './storagePaths'

/** 署名URLの有効期限（秒） */
const SIGNED_URL_TTL_SECONDS = 3600

/** 残り有効期限がこの値を切ったら再発行する（5分） */
const REFRESH_MARGIN_MS = 5 * 60 * 1000

// 署名URLのメモリキャッシュ（キー = `bucket/path`）。
// モジュールレベルで保持し、同一パスの再署名リクエストを抑止する。
type SignedUrlCacheEntry = { url: string; expiresAt: number }
const signedUrlCache = new Map<string, SignedUrlCacheEntry>()
// 同一キーへの並行リクエストをまとめる in-flight マップ
const pendingSignRequests = new Map<string, Promise<string | null>>()

/**
 * 値（パス or フルURL or 外部URL）を表示可能なURLへ解決する。
 *
 * - null/空 → null
 * - 外部URL → そのまま返す（署名しない）
 * - Storage パス/フルURL → ブラウザクライアントで createSignedUrl(TTL 3600秒)。
 *   キャッシュ済みで残り約5分以上あれば再利用する。
 * - 存在しないオブジェクト（Seed の架空パス等）や署名失敗 → null（例外は投げない）
 */
export async function getSignedStorageUrl(
  value: string | null | undefined,
  bucket: StorageBucket,
): Promise<string | null> {
  if (!value) return null

  const { base } = splitFragment(value)
  if (!base) return null

  // 外部URL（Google 等）は署名せずそのまま通す
  if (isExternalUrl(base)) return base

  const path = extractStoragePath(value, bucket)
  if (!path) return null

  const cacheKey = `${bucket}/${path}`

  const cached = signedUrlCache.get(cacheKey)
  if (cached && cached.expiresAt - Date.now() > REFRESH_MARGIN_MS) {
    return cached.url
  }

  const pending = pendingSignRequests.get(cacheKey)
  if (pending) return pending

  const request = (async (): Promise<string | null> => {
    try {
      // モジュールロード時の副作用（クライアント生成）を避けるため動的 import
      const { supabase } = await import('../supabase')
      const { data, error } = await supabase.storage
        .from(bucket)
        .createSignedUrl(path, SIGNED_URL_TTL_SECONDS)

      if (error || !data?.signedUrl) {
        // 存在しないオブジェクト等。呼び出し側でフォールバック表示する
        return null
      }

      signedUrlCache.set(cacheKey, {
        url: data.signedUrl,
        expiresAt: Date.now() + SIGNED_URL_TTL_SECONDS * 1000,
      })
      return data.signedUrl
    } catch (err) {
      console.error('署名URL発行エラー:', err)
      return null
    } finally {
      pendingSignRequests.delete(cacheKey)
    }
  })()

  pendingSignRequests.set(cacheKey, request)
  return request
}

/**
 * 値（パス or フルURL or 外部URL）を表示用URLへ解決する React フック。
 * 解決前・解決失敗時は null を返す（呼び出し側でフォールバック表示する）。
 */
export function useStorageUrl(
  value: string | null | undefined,
  bucket: StorageBucket,
): string | null {
  const [url, setUrl] = useState<string | null>(() => {
    // 外部URLは同期解決してチラつきを防ぐ
    if (!value) return null
    const { base } = splitFragment(value)
    return isExternalUrl(base) ? base : null
  })

  useEffect(() => {
    let cancelled = false

    if (!value) {
      setUrl(null)
      return
    }

    // value/bucket 変更時に前の値のURLを表示し続けないよう、
    // まず「同期解決できる値（外部URL）ならそれ、そうでなければ null」にリセットする
    const { base } = splitFragment(value)
    setUrl(isExternalUrl(base) ? base : null)

    getSignedStorageUrl(value, bucket).then((resolved) => {
      if (!cancelled) setUrl(resolved)
    })

    return () => {
      cancelled = true
    }
  }, [value, bucket])

  return url
}
