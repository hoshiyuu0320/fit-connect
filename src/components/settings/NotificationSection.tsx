'use client'

import { useState } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Label } from '@/components/ui/label'

export function NotificationSection() {
  const [emailNotification, setEmailNotification] = useState(false)

  return (
    <Card>
      <CardHeader>
        <CardTitle>通知設定</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        {/* Email Notification Toggle */}
        <div className="flex items-center justify-between">
          <Label htmlFor="email-notification" className="text-base font-normal">
            メール通知
          </Label>
          <button
            id="email-notification"
            type="button"
            role="switch"
            aria-checked={emailNotification}
            onClick={() => setEmailNotification(!emailNotification)}
            className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 ${
              emailNotification ? 'bg-blue-600' : 'bg-gray-300'
            }`}
          >
            <span
              className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                emailNotification ? 'translate-x-6' : 'translate-x-1'
              }`}
            />
          </button>
        </div>

        {/* Notice */}
        <p className="text-sm text-gray-500 mt-4">
          この機能は現在開発中です。今後のアップデートで通知が届くようになります。
        </p>
      </CardContent>
    </Card>
  )
}
