'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'
import { supabase } from '@/lib/supabase'

const passwordSchema = z
  .object({
    newPassword: z.string().min(6, '6文字以上で入力してください'),
    confirmPassword: z.string().min(6, '6文字以上で入力してください'),
  })
  .refine((data) => data.newPassword === data.confirmPassword, {
    message: 'パスワードが一致しません',
    path: ['confirmPassword'],
  })

type PasswordFormData = z.infer<typeof passwordSchema>

export function PasswordSection() {
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const form = useForm<PasswordFormData>({
    resolver: zodResolver(passwordSchema),
    defaultValues: {
      newPassword: '',
      confirmPassword: '',
    },
  })

  const onSubmit = async (data: PasswordFormData) => {
    setIsSubmitting(true)
    setMessage(null)

    try {
      const { error } = await supabase.auth.updateUser({
        password: data.newPassword,
      })

      if (error) {
        throw error
      }

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

  return (
    <Card>
      <CardHeader>
        <CardTitle>パスワード変更</CardTitle>
      </CardHeader>
      <CardContent>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
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
  )
}
