// ================================================
// Storage パス/署名URL 共通ヘルパー
// ================================================
// フェーズ8.2 Storage private化に伴い、DB には「バケット相対パス」を保存し、
// 表示時に署名URL（TTL 3600秒）へ解決する。
// レガシー行にはフルURL（/storage/v1/object/public/... 形式）や
// 外部URL（Google の lh3.googleusercontent.com 等）が共存するため、
// 値は「パス or フルURL or 外部URL」のどれが来ても扱えるようにする。
// 純関数（splitFragment / isExternalUrl / extractStoragePath）は
// サーバー側（API Route）からも共有 import される。
// そのため本モジュールはサーバーセーフな純関数と型のみを持ち、
// React フック等のクライアント専用コードは signedStorageUrls.ts に分離している。

/** カラム↔バケット対応で使用する Storage バケット名 */
export type StorageBucket =
  | 'message-photos'
  | 'client-avatars'
  | 'client-notes'
  | 'profile-images'

/**
 * `#` フラグメント（元ファイル名の埋め込み）を分離する。
 * notes/profile の値は `パス#encodeURIComponent(元ファイル名)` 形式のため、
 * 署名やパス判定の前に必ずフラグメントを除去する必要がある。
 * fragment はエンコードされたまま返す（表示時に decodeURIComponent する）。
 */
export function splitFragment(value: string): { base: string; fragment: string | null } {
  const hashIndex = value.indexOf('#')
  if (hashIndex === -1) {
    return { base: value, fragment: null }
  }
  return {
    base: value.substring(0, hashIndex),
    fragment: value.substring(hashIndex + 1),
  }
}

/**
 * Supabase Storage 以外の外部URL（Google OAuth の lh3.googleusercontent.com 等）か判定する。
 * 外部URLは署名対象外で、そのまま表示に使う。
 */
export function isExternalUrl(value: string): boolean {
  return /^https?:\/\//i.test(value) && !value.includes('/storage/v1/object/')
}

/**
 * 値（パス or フルURL）からバケット相対の Storage パスを抽出する。
 *
 * - null/空文字 → null
 * - http(s) URL: `/storage/v1/object/(public|sign)/<bucket>/` を含めばパス抽出
 *   （クエリ `?t=` 等・`#` フラグメントは除去、パーセントエンコードは復元）
 * - 外部URL・別バケットのURL → null
 * - それ以外はパスとみなしてそのまま返す（フラグメント・クエリは除去）
 */
export function extractStoragePath(
  value: string | null | undefined,
  bucket: StorageBucket,
): string | null {
  if (!value) return null

  const { base } = splitFragment(value)
  if (!base) return null

  // クエリ除去（Mobile レガシーのアバターURLには `?t=タイムスタンプ` が付く）
  const withoutQuery = base.split('?')[0]

  if (/^https?:\/\//i.test(withoutQuery)) {
    // フルURL: 同一プロジェクトの public / sign URL のみパス抽出対象
    for (const kind of ['public', 'sign'] as const) {
      const marker = `/storage/v1/object/${kind}/${bucket}/`
      const markerIndex = withoutQuery.indexOf(marker)
      if (markerIndex !== -1) {
        const encodedPath = withoutQuery.substring(markerIndex + marker.length)
        if (!encodedPath) return null
        try {
          return decodeURIComponent(encodedPath)
        } catch {
          // 不正なパーセントエンコードはそのまま返す
          return encodedPath
        }
      }
    }
    // 外部URL または別バケットのURL
    return null
  }

  return withoutQuery || null
}

/**
 * カルテ添付の値（パス or フルURL）から表示用のファイル名を取得する。
 * ハッシュフラグメントに元のファイル名が埋め込まれていればそちらを優先し、
 * なければパス末尾（`<タイムスタンプ>_` プレフィックス除去）から抽出する。
 */
export function noteFileName(value: string): string {
  // ハッシュフラグメントに元のファイル名がある場合はそちらを使用
  const { fragment } = splitFragment(value)
  if (fragment) {
    try {
      return decodeURIComponent(fragment)
    } catch {
      return fragment
    }
  }
  // フォールバック: パスから抽出
  const path = extractStoragePath(value, 'client-notes') ?? splitFragment(value).base
  const decoded = decodeURIComponent(path.split('/').pop() || '')
  const match = decoded.match(/^\d+_(.+)$/)
  return match ? match[1] : decoded
}

/**
 * カルテ添付の値が PDF か判定する。
 * 値はパス or フルURL（レガシー）の両対応。フラグメント分離後のパス部分で判定する。
 */
export function isNoteFilePdf(value: string): boolean {
  const path = extractStoragePath(value, 'client-notes') ?? splitFragment(value).base
  return path.toLowerCase().endsWith('.pdf')
}
