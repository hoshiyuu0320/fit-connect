'use client'

import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { zodResolver } from '@hookform/resolvers/zod'
import { z } from 'zod'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Form, FormControl, FormField, FormItem, FormLabel, FormMessage } from '@/components/ui/form'
import { uploadProfileImage } from '@/lib/supabase/uploadProfileImage'
import type { Trainer } from '@/types/trainer'

const profileSchema = z.object({
  name: z.string().min(1, '名前は必須です').max(50, '50文字以内で入力してください'),
})

type ProfileFormData = z.infer<typeof profileSchema>

interface ProfileSectionProps {
  trainer: Trainer
  onUpdate: () => void
}

export function ProfileSection({ trainer, onUpdate }: ProfileSectionProps) {
  const [selectedFile, setSelectedFile] = useState<File | null>(null)
  const [previewUrl, setPreviewUrl] = useState<string | null>(null)
  const [message, setMessage] = useState<{ type: 'success' | 'error'; text: string } | null>(null)
  const [isSubmitting, setIsSubmitting] = useState(false)

  const form = useForm<ProfileFormData>({
    resolver: zodResolver(profileSchema),
    defaultValues: {
      name: trainer.name ?? '',
    },
  })

  const handleFileChange = (e: React.ChangeEvent<HTMLInputElement>) => {
    const file = e.target.files?.[0]
    if (file) {
      setSelectedFile(file)
      const url = URL.createObjectURL(file)
      setPreviewUrl(url)
    }
  }

  const getInitials = (name: string) => {
    return name
      .split(' ')
      .map((n) => n[0])
      .join('')
      .toUpperCase()
      .slice(0, 2)
  }

  const onSubmit = async (data: ProfileFormData) => {
    setIsSubmitting(true)
    setMessage(null)

    try {
      let profileImageUrl = trainer.profile_image_url

      // Upload image if selected
      if (selectedFile) {
        profileImageUrl = await uploadProfileImage(selectedFile, trainer.id)
      }

      // Update trainer profile
      const response = await fetch(`/api/trainers/${trainer.id}`, {
        method: 'PUT',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          name: data.name,
          profileImageUrl,
        }),
      })

      if (!response.ok) {
        throw new Error('更新に失敗しました')
      }

      setMessage({ type: 'success', text: '保存しました' })
      setSelectedFile(null)
      setPreviewUrl(null)
      onUpdate()
    } catch (error) {
      console.error('Error updating profile:', error)
      setMessage({ type: 'error', text: error instanceof Error ? error.message : '保存に失敗しました' })
    } finally {
      setIsSubmitting(false)
    }
  }

  const displayImageUrl = previewUrl || trainer.profile_image_url

  return (
    <Card>
      <CardHeader>
        <CardTitle>プロフィール情報</CardTitle>
      </CardHeader>
      <CardContent>
        <Form {...form}>
          <form onSubmit={form.handleSubmit(onSubmit)} className="space-y-6">
            {/* Profile Image */}
            <div className="space-y-4">
              <Label>プロフィール画像</Label>
              <div className="flex items-center gap-4">
                <div className="w-24 h-24 rounded-full overflow-hidden bg-blue-100 flex items-center justify-center">
                  {displayImageUrl ? (
                    <img
                      src={displayImageUrl}
                      alt="プロフィール画像"
                      className="w-full h-full object-cover"
                    />
                  ) : (
                    <span className="text-2xl font-semibold text-blue-600">
                      {getInitials(trainer.name)}
                    </span>
                  )}
                </div>
                <div>
                  <input
                    type="file"
                    id="profile-image"
                    accept="image/jpeg,image/png,image/webp"
                    onChange={handleFileChange}
                    className="hidden"
                  />
                  <Label
                    htmlFor="profile-image"
                    className="cursor-pointer inline-flex items-center justify-center rounded-md text-sm font-medium transition-colors focus-visible:outline-none focus-visible:ring-1 focus-visible:ring-ring bg-secondary text-secondary-foreground shadow-sm hover:bg-secondary/80 h-9 px-4 py-2"
                  >
                    画像を変更
                  </Label>
                </div>
              </div>
            </div>

            {/* Name */}
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
              {isSubmitting ? '保存中...' : '保存'}
            </Button>
          </form>
        </Form>

      </CardContent>
    </Card>
  )
}
