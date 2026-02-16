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

const passwordSchema = z
  .object({
    currentPassword: z.string().min(1, '現在のパスワードを入力してください'),
    newPassword: z.string().min(6, '6文字以上で入力してください'),
    confirmPassword: z.string().min(6, '6文字以上で入力してください'),
  })
  .refine((data) => data.newPassword === data.confirmPassword, {
    message: 'パスワードが一致しません',
    path: ['confirmPassword'],
  })

type PasswordFormData = z.infer<typeof passwordSchema>

export default function PasswordChangePage() {
  const router = useRouter()
  const [userEmail, setUserEmail] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const form = useForm<PasswordFormData>({
    resolver: zodResolver(passwordSchema),
    defaultValues: {
      currentPassword: '',
      newPassword: '',
      confirmPassword: '',
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

        setUserEmail(user.email || null)
      } catch (error) {
        console.error('ユーザー情報取得エラー:', error)
        router.push('/login')
      } finally {
        setLoading(false)
      }
    }

    fetchUserEmail()
  }, [router])

  const onSubmit = async (data: PasswordFormData) => {
    setIsSubmitting(true)
    setMessage(null)

    try {
      if (!userEmail) {
        throw new Error('メールアドレスが取得できません')
      }

      // 現在のパスワードで再認証
      const { error: signInError } = await supabase.auth.signInWithPassword({
        email: userEmail,
        password: data.currentPassword,
      })

      if (signInError) {
        setMessage({ type: 'error', text: '現在のパスワードが正しくありません' })
        return
      }

      // 新しいパスワードに更新
      const { error } = await supabase.auth.updateUser({
        password: data.newPassword,
      })

      if (error) throw error

      setMessage({ type: 'success', text: 'パスワードを変更しました' })
      form.reset()
    } catch (error) {
      console.error('Error updating password:', error)
      setMessage({
        type: 'error',
        text: error instanceof Error ? error.message : 'パスワード変更に失敗しました',
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
          <h1 className="text-2xl font-bold text-gray-900">パスワード変更</h1>
        </div>

        {/* パスワード変更フォーム */}
        <Card>
          <CardHeader>
            <CardTitle className="text-lg">パスワード変更</CardTitle>
          </CardHeader>
          <CardContent>
            <Form {...form}>
              <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
                {/* Current Password */}
                <FormField
                  control={form.control}
                  name="currentPassword"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>現在のパスワード</FormLabel>
                      <FormControl>
                        <Input type="password" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {/* New Password */}
                <FormField
                  control={form.control}
                  name="newPassword"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>新しいパスワード</FormLabel>
                      <FormControl>
                        <Input type="password" {...field} />
                      </FormControl>
                      <FormMessage />
                    </FormItem>
                  )}
                />

                {/* Confirm Password */}
                <FormField
                  control={form.control}
                  name="confirmPassword"
                  render={({ field }) => (
                    <FormItem>
                      <FormLabel>新しいパスワード（確認）</FormLabel>
                      <FormControl>
                        <Input type="password" {...field} />
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
