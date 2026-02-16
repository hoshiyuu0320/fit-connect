'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import Link from 'next/link'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { supabase } from '@/lib/supabase'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'

const emailSchema = z.object({
  newEmail: z.string().email('有効なメールアドレスを入力してください'),
})

type EmailFormData = z.infer<typeof emailSchema>

export default function EmailChangePage() {
  const router = useRouter()
  const [currentEmail, setCurrentEmail] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const form = useForm<EmailFormData>({
    resolver: zodResolver(emailSchema),
    defaultValues: {
      newEmail: '',
    },
  })

  useEffect(() => {
    const fetchUserEmail = async () => {
      setLoading(true)

      try {
        const {
          data: { user },
        } = await supabase.auth.getUser()

        if (!user) {
          router.push('/login')
          return
        }

        setCurrentEmail(user.email || null)
      } catch (error) {
        console.error('ユーザー情報取得エラー:', error)
        router.push('/login')
      } finally {
        setLoading(false)
      }
    }

    fetchUserEmail()
  }, [router])

  const onSubmit = async (data: EmailFormData) => {
    setIsSubmitting(true)
    setMessage(null)

    try {
      const { error } = await supabase.auth.updateUser({
        email: data.newEmail,
      })

      if (error) {
        throw error
      }

      setMessage({
        type: 'success',
        text: '確認メールを送信しました。新しいメールアドレスに届いたリンクをクリックして変更を完了してください。',
      })
      form.reset()
    } catch (error) {
      console.error('Error updating email:', error)
      let errorText = 'メールアドレスの変更に失敗しました'
      if (error instanceof Error) {
        if (error.message.includes('already been registered')) {
          errorText = 'このメールアドレスはすでに登録されています'
        } else if (error.message.includes('rate limit')) {
          errorText = 'リクエスト回数の上限に達しました。しばらく時間を置いてから再度お試しください。'
        } else {
          errorText = error.message
        }
      }
      setMessage({
        type: 'error',
        text: errorText,
      })
    } finally {
      setIsSubmitting(false)
    }
  }

  if (loading) {
    return (
      <div className="flex items-center justify-center h-[calc(100vh-48px)]">
        <div className="animate-spin rounded-full h-12 w-12 border-4 border-blue-600 border-t-transparent"></div>
      </div>
    )
  }

  return (
    <main className="h-[calc(100vh-48px)] overflow-y-auto bg-gray-50">
      <div className="max-w-2xl mx-auto p-6 space-y-6">
        {/* 戻るリンク */}
        <Link
          href="/settings"
          className="inline-flex items-center text-sm text-gray-600 hover:text-gray-900 mb-6"
        >
          <svg className="w-4 h-4 mr-1" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M15 19l-7-7 7-7" />
          </svg>
          設定に戻る
        </Link>

        {/* ページタイトル */}
        <div className="mb-8">
          <h1 className="text-2xl font-bold text-gray-900">メールアドレス変更</h1>
        </div>

        {/* 現在のメールアドレス表示 */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">現在のメールアドレス</CardTitle>
          </CardHeader>
          <CardContent>
            <div className="bg-gray-50 rounded-md p-3 text-gray-700">{currentEmail || '-'}</div>
          </CardContent>
        </Card>

        {/* メールアドレス変更フォーム */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">新しいメールアドレス</CardTitle>
          </CardHeader>
          <CardContent>
            <Form {...form}>
              <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
                {/* New Email */}
                <FormField
                  control={form.control}
                  name="newEmail"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>新しいメールアドレス</FormLabel>
                      <FormControl>
                        <Input type="email" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {/* Message */}
                {message && (
                  <div
                    className={`p-3 rounded-md text-sm ${
                      message.type === 'success'
                        ? 'bg-emerald-50 text-emerald-700'
                        : 'bg-rose-50 text-rose-700'
                    }`}
                  >
                    {message.text}
                  </div>
                )}

                {/* Submit Button */}
                <Button type="submit" disabled={isSubmitting}>
                  {isSubmitting ? '変更中...' : '変更'}
                </Button>
              </form>
            </Form>
          </CardContent>
        </Card>
      </div>
    </main>
  )
}
