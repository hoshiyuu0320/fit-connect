'use client'

import { useEffect, useState } from 'react'
import { useStorageUrl } from '@/lib/supabase/signedStorageUrls'
import type { StorageBucket } from '@/lib/supabase/storagePaths'

interface StorageImgProps
  extends Omit<React.ImgHTMLAttributes<HTMLImageElement>, 'src'> {
  /** Storage パス or フルURL（レガシー） or 外部URL。null なら fallback を表示 */
  value: string | null | undefined
  /** 値が属する Storage バケット */
  bucket: StorageBucket
  /** 解決前・解決失敗・読み込みエラー時に表示する要素 */
  fallback?: React.ReactNode
}

/**
 * Storage の値（パス/フルURL/外部URL）を署名URLへ解決して表示する <img> ラッパー。
 * 署名URLの解決は useStorageUrl（メモリキャッシュ付き）に委譲し、
 * 解決できない場合や画像読み込みエラー時は fallback を表示する。
 */
export function StorageImg({
  value,
  bucket,
  fallback = null,
  alt = '',
  onError,
  ...imgProps
}: StorageImgProps) {
  const url = useStorageUrl(value, bucket)
  const [failed, setFailed] = useState(false)

  // URLが変わったら（再発行含む）エラー状態をリセット
  useEffect(() => {
    setFailed(false)
  }, [url])

  if (!url || failed) {
    return <>{fallback}</>
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img
      src={url}
      alt={alt}
      onError={(e) => {
        setFailed(true)
        onError?.(e)
      }}
      {...imgProps}
    />
  )
}
