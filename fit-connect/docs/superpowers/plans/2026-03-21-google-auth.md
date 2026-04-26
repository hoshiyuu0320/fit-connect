# Google認証機能 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Google OAuthでの新規登録・ログインを可能にし、初回ログイン時にトレーナーレコードを自動作成する

**Architecture:** `/auth/callback` Route Handlerを拡張し、セッション交換後にtrainersテーブルへのupsertを行う。新規ユーザーにはダッシュボードでトースト通知を表示。トーストライブラリとしてsonnerを導入。

**Tech Stack:** Next.js 15 (App Router), Supabase Auth (OAuth), supabaseAdmin, sonner (toast)

**Spec:** `docs/superpowers/specs/2026-03-21-google-auth-design.md`

---

## ファイル構成

| 操作 | ファイル | 責務 |
|------|---------|------|
| 修正 | `src/app/auth/callback/route.ts` | セッション交換 + trainer upsert |
| 修正 | `src/app/(user_console)/layout.tsx` | `<Toaster />` 配置 |
| 修正 | `src/app/(user_console)/dashboard/page.tsx` | welcome トースト表示 |
| 新規なし | ログイン/サインアップページ | Googleボタン既存。変更不要 |

---

## Task 1: sonner インストール

**Files:**
- Modify: `package.json`

- [ ] **Step 1: sonner をインストール**

```bash
npm install sonner
```

- [ ] **Step 2: インストール確認**

```bash
npm ls sonner
```

Expected: `sonner@x.x.x` が表示される

- [ ] **Step 3: Commit**

```bash
git add package.json package-lock.json
git commit -m "chore: sonner をインストール（トースト通知ライブラリ）"
```

---

## Task 2: Toaster をレイアウトに配置

**Files:**
- Modify: `src/app/(user_console)/layout.tsx`

- [ ] **Step 1: Toaster を layout.tsx に追加**

`src/app/(user_console)/layout.tsx` の `Sidebar` コンポーネント内で `{children}` の隣に `<Toaster />` を配置する。

```tsx
// import 追加
import { Toaster } from 'sonner'

// return 内の </main> の直前に追加
<Toaster
  position="top-right"
  toastOptions={{
    style: {
      fontFamily: "'Noto Sans JP', 'Plus Jakarta Sans', sans-serif",
    },
  }}
/>
```

配置場所: `return` の `<main>` タグの閉じタグ直前（`{children}` を含む `<section>` の外側）。

- [ ] **Step 2: ビルド確認**

```bash
npm run build
```

Expected: エラーなし

- [ ] **Step 3: Commit**

```bash
git add src/app/\(user_console\)/layout.tsx
git commit -m "feat: Toaster コンポーネントを user_console レイアウトに配置"
```

---

## Task 3: コールバックにトレーナー自動作成ロジックを追加

**Files:**
- Modify: `src/app/auth/callback/route.ts`

- [ ] **Step 1: callback/route.ts を書き換え**

以下の内容で `src/app/auth/callback/route.ts` を更新する。既存のコード交換ロジックの後に、trainer upsert を追加。

```typescript
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
```

重要なポイント:
- `supabaseAdmin` を import（サーバーサイドのみ。RLS バイパス）
- `upsert` に `ignoreDuplicates: true` を使用（`ON CONFLICT DO NOTHING` 相当）
- `.maybeSingle()` を使用（`.single()` だと既存ユーザー時に0行エラーが発生するため）
- `ignoreDuplicates: true` の場合、既存レコードは `.select()` で返らない。`upsertData !== null` なら新規ユーザー
- エラー時は `console.error` で記録しリダイレクト続行
- 既存の `next` パラメータを維持

- [ ] **Step 2: ビルド確認**

```bash
npm run build
```

Expected: エラーなし

- [ ] **Step 3: Commit**

```bash
git add src/app/auth/callback/route.ts
git commit -m "feat: OAuth コールバックでトレーナーレコードを自動作成（upsert）"
```

---

## Task 4: ダッシュボードにウェルカムトーストを追加

**Files:**
- Modify: `src/app/(user_console)/dashboard/page.tsx`

- [ ] **Step 1: dashboard/page.tsx にトースト表示ロジックを追加**

以下の変更を加える:

1. import を追加:

```tsx
import { useSearchParams, useRouter } from 'next/navigation'
import { toast } from 'sonner'
```

2. `DashboardPage` コンポーネント内に追加（既存の `useEffect` の前）:

```tsx
const searchParams = useSearchParams()
const router = useRouter()

useEffect(() => {
  if (searchParams.get('welcome') === 'true') {
    toast.success('Googleアカウントの名前で登録しました。設定画面から変更できます', {
      duration: 6000,
    })
    // URL からパラメータを除去
    router.replace('/dashboard')
  }
}, [searchParams, router])
```

注意: `useRouter` は `next/navigation` から import。`dashboard/page.tsx` は `"use client"` なので `useSearchParams` が使える。

- [ ] **Step 2: ビルド確認**

```bash
npm run build
```

Expected: エラーなし

- [ ] **Step 3: Commit**

```bash
git add src/app/\(user_console\)/dashboard/page.tsx
git commit -m "feat: Google新規登録時にウェルカムトーストを表示"
```

---

## Task 5: 手動設定ガイド & 動作確認

- [ ] **Step 1: Google Cloud Console + Supabase の設定確認**

ユーザーに以下の手動設定を依頼:

1. **Google Cloud Console:**
   - プロジェクト作成 or 既存使用
   - OAuth 同意画面を設定（外部ユーザータイプ）
   - OAuth 2.0 クライアントID を作成
     - 承認済み JavaScript オリジン: `http://localhost:3000`
     - 承認済みリダイレクト URI: `https://<supabase-project-ref>.supabase.co/auth/v1/callback`
   - Client ID / Client Secret を控える

2. **Supabase Dashboard:**
   - Authentication → Providers → Google を有効化
   - Client ID / Client Secret を入力して保存
   - Authentication → Settings → User Identity Linking を確認（推奨: Automatic linking）

- [ ] **Step 2: 動作確認（手動テスト）**

以下のシナリオを確認:

1. **新規 Google ユーザー**: ログインページ → Google ボタン → Google 認証 → ダッシュボード + ウェルカムトースト表示
2. **既存 Google ユーザー（2回目以降）**: ログインページ → Google ボタン → ダッシュボード（トーストなし）
3. **既存メール/パスワードユーザー**: 従来通りログインできること
4. **サインアップページからの Google 登録**: サインアップ → Google ボタン → 同じフロー

- [ ] **Step 3: Commit（もし設定変更があれば）**

```bash
git add -A
git commit -m "docs: Google認証の設定完了"
```
