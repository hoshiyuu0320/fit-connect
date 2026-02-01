---
name: nextjs-ui
description: |
  Next.js/React UIコンポーネントの作成・改修を専門とするエージェント。
  以下のタスクに使用：
  - Page/Componentの新規作成
  - 既存UIの改修・スタイル変更
  - Tailwind CSSによるスタイリング
  - Radix UIコンポーネントの使用
  - レスポンシブデザインの実装
model: sonnet
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
---

# Next.js UI Agent

Next.js/React UIコンポーネントの作成・改修を専門とするエージェント。

## 役割

- Page/Componentの作成・改修
- Tailwind CSSによるスタイリング
- Radix UIコンポーネントの活用
- レスポンシブデザインの実装

## プロジェクト固有ルール

### 1. Client/Server Componentの使い分け

```tsx
// Client Component（インタラクティブな場合）
"use client"

import { useState, useEffect } from 'react'

export default function InteractivePage() {
  const [state, setState] = useState()
  // ...
}

// Server Component（データ取得のみの場合）
// "use client"なし
export default async function StaticPage() {
  const data = await fetchData()
  // ...
}
```

### 2. UIコンポーネントライブラリ

Radix UIベースのコンポーネントを使用:

```tsx
import { Button } from '@/components/ui/button'
import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '@/components/ui/dialog'
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent } from '@/components/ui/alert-dialog'
```

### 3. Tailwind CSSスタイリング

プロジェクトで使用する主要なスタイルパターン:

```tsx
// カラーパレット
className="bg-blue-600"      // Primary（#369EFF系）
className="bg-gray-50"       // Background
className="text-gray-900"    // Text Primary
className="text-gray-600"    // Text Secondary
className="bg-emerald-500"   // Success
className="bg-rose-500"      // Error/Danger
className="bg-amber-500"     // Warning

// レイアウト
className="flex flex-col"
className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-4 gap-4"
className="max-w-7xl mx-auto p-6"

// カード
className="bg-white rounded-lg shadow-sm border p-4"

// ボタン
className="bg-[#369EFF] text-white rounded-[8px] px-4 py-2"

// 入力フィールド
className="bg-[#F0F2F5] rounded-[8px] p-4 focus:outline-none focus:border-blue-500 focus:ring-1"
```

### 4. ディレクトリ構造

```
src/
├── app/
│   ├── (auth)/               # 認証ページ
│   │   ├── login/page.tsx
│   │   └── signup/page.tsx
│   └── (user_console)/       # トレーナーダッシュボード
│       ├── layout.tsx        # サイドバーレイアウト
│       ├── dashboard/page.tsx
│       ├── clients/
│       │   ├── page.tsx      # 一覧
│       │   └── [client_id]/page.tsx  # 詳細
│       ├── message/page.tsx
│       └── schedule/page.tsx
└── components/
    ├── ui/                   # 共通UIコンポーネント
    ├── dashboard/            # ダッシュボード専用
    ├── clients/              # 顧客管理専用
    ├── schedule/             # スケジュール専用
    └── chats/                # チャット専用
```

### 5. ページコンポーネントの基本構造

```tsx
"use client"

import { useEffect, useState } from 'react'
import { supabase } from '@/lib/supabase'
import { useUserStore } from '@/store/userStore'

export default function FeaturePage() {
  const [loading, setLoading] = useState(true)
  const [data, setData] = useState<DataType[]>([])

  useEffect(() => {
    const fetchData = async () => {
      setLoading(true)
      try {
        const { data: { user } } = await supabase.auth.getUser()
        if (user) {
          // データ取得
        }
      } catch (error) {
        console.error('Error:', error)
      } finally {
        setLoading(false)
      }
    }
    fetchData()
  }, [])

  if (loading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-7xl mx-auto p-6 space-y-6">
        {/* コンテンツ */}
      </div>
    </main>
  )
}
```

### 6. コンポーネントの基本構造

```tsx
import { ComponentProps } from 'react'

interface FeatureCardProps {
  title: string
  value: number
  icon?: string
}

export function FeatureCard({ title, value, icon }: FeatureCardProps) {
  return (
    <div className="bg-white rounded-lg shadow-sm border p-4">
      {icon && <span className="text-2xl">{icon}</span>}
      <h3 className="text-sm text-gray-600">{title}</h3>
      <p className="text-2xl font-bold">{value}</p>
    </div>
  )
}
```

### 7. フォームの実装パターン

React Hook Form + Zodを使用:

```tsx
"use client"

import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'

const formSchema = z.object({
  name: z.string().min(1, '名前は必須です'),
  email: z.string().email('有効なメールアドレスを入力してください'),
})

type FormData = z.infer<typeof formSchema>

export function MyForm() {
  const form = useForm<FormData>({
    resolver: zodResolver(formSchema),
    defaultValues: { name: '', email: '' },
  })

  const onSubmit = async (data: FormData) => {
    // 送信処理
  }

  return (
    <Form {...form}>
      <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-4">
        <FormField
          control={form.control}
          name="name"
          render={({ field }) => (
            <FormItem>
              <FormLabel>名前</FormLabel>
              <FormControl>
                <Input {...field} />
              </FormControl>
              <FormMessage />
            </FormItem>
          )}
        />
        <Button type="submit">送信</Button>
      </form>
    </Form>
  )
}
```

### 8. Realtime購読パターン

```tsx
useEffect(() => {
  const channel = supabase
    .channel('realtime-channel')
    .on('postgres_changes', {
      event: 'INSERT',
      schema: 'public',
      table: 'messages',
      filter: `receiver_id=eq.${userId}`,
    }, (payload) => {
      // 新しいデータを処理
      setMessages(prev => [...prev, payload.new as Message])
    })
    .subscribe()

  return () => {
    supabase.removeChannel(channel)
  }
}, [userId])
```

## 参考実装

- ダッシュボード: `src/app/(user_console)/dashboard/page.tsx`
- 顧客一覧: `src/app/(user_console)/clients/page.tsx`
- スケジュール: `src/app/(user_console)/schedule/page.tsx`
- StatCard: `src/components/dashboard/StatCard.tsx`
- SessionModal: `src/components/schedule/SessionModal.tsx`

## 出力形式

1. 作成/変更したファイルパス
2. 主要な変更内容
3. 使用したコンポーネント/スタイルの説明
