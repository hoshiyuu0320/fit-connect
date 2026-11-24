import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import type { User } from '@supabase/supabase-js'

/**
 * Route Handler / Server Component 用の認証ヘルパー。
 *
 * リクエストの Cookie からセッションを復元し、Supabase Auth サーバーで
 * 検証済みのユーザーを返す（auth.getUser() は JWT をサーバー側で検証する）。
 * 未認証・検証失敗時は null。
 *
 * 課金系 API Route は必ずこのヘルパーで認証チェックを行うこと。
 */
export async function getAuthenticatedUser(): Promise<User | null> {
  const cookieStore = await cookies()
  const supabase = createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() {
          return cookieStore.getAll()
        },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options)
            )
          } catch {
            // Server Component から呼ばれた場合など、Cookie を書き込めない
            // コンテキストでは無視する（セッション読み取りには影響しない）
          }
        },
      },
    }
  )

  const {
    data: { user },
    error,
  } = await supabase.auth.getUser()

  if (error || !user) {
    return null
  }
  return user
}
