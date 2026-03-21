import { NextResponse } from 'next/server'
import { createServerClient } from '@supabase/ssr'
import { cookies } from 'next/headers'
import { supabaseAdmin } from '@/lib/supabaseAdmin'

export async function GET(request: Request) {
  const { searchParams, origin } = new URL(request.url)
  const code = searchParams.get('code')
  const next = searchParams.get('next') ?? '/dashboard'

  if (code) {
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
              // The `setAll` method was called from a Server Component.
            }
          },
        },
      }
    )

    const { data, error } = await supabase.auth.exchangeCodeForSession(code)

    if (!error && data.user) {
      const user = data.user

      // トレーナーレコードの upsert（ON CONFLICT DO NOTHING）
      let isNewUser = false
      try {
        const name =
          user.user_metadata?.full_name ||
          user.email?.split('@')[0] ||
          'Unknown'
        const email = user.email || ''
        const profileImageUrl = user.user_metadata?.avatar_url || null

        const { data: upsertData } = await supabaseAdmin
          .from('trainers')
          .upsert(
            {
              id: user.id,
              name,
              email,
              profile_image_url: profileImageUrl,
            },
            { onConflict: 'id', ignoreDuplicates: true }
          )
          .select('created_at')
          .maybeSingle()

        // ignoreDuplicates: true の場合、既存レコードは返らない（null）
        // データが返れば新規作成されたことを意味する
        isNewUser = upsertData !== null
      } catch (upsertError) {
        console.error('トレーナーレコード作成エラー:', upsertError)
        // セッションは有効なのでリダイレクトは続行
      }

      // リダイレクト先を構築
      const redirectPath = isNewUser
        ? `${next}${next.includes('?') ? '&' : '?'}welcome=true`
        : next

      const forwardedHost = request.headers.get('x-forwarded-host')
      const isLocalEnv = process.env.NODE_ENV === 'development'

      if (isLocalEnv) {
        return NextResponse.redirect(`${origin}${redirectPath}`)
      } else if (forwardedHost) {
        return NextResponse.redirect(`https://${forwardedHost}${redirectPath}`)
      } else {
        return NextResponse.redirect(`${origin}${redirectPath}`)
      }
    }
  }

  return NextResponse.redirect(`${origin}/auth/auth-code-error`)
}
