'use client'

import Link from 'next/link'
import { Card, CardHeader, CardTitle, CardContent } from '@/components/ui/card'
import { Button } from '@/components/ui/button'
import {
  AlertDialog,
  AlertDialogAction,
  AlertDialogCancel,
  AlertDialogContent,
  AlertDialogDescription,
  AlertDialogFooter,
  AlertDialogHeader,
  AlertDialogTitle,
  AlertDialogTrigger,
} from '@/components/ui/alert-dialog'

interface AccountSectionProps {
  onLogout: () => void
}

export function AccountSection({ onLogout }: AccountSectionProps) {
  return (
    <Card>
      <CardHeader>
        <CardTitle>アカウント管理</CardTitle>
      </CardHeader>
      <CardContent className="space-y-4">
        <div className="space-y-1">
          <Link
            href="/settings/email"
            className="flex items-center justify-between p-3 -mx-3 rounded-lg hover:bg-gray-50 transition-colors"
          >
            <p className="text-sm font-medium text-gray-900">メールアドレスを変更</p>
            <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </Link>
          <Link
            href="/settings/password"
            className="flex items-center justify-between p-3 -mx-3 rounded-lg hover:bg-gray-50 transition-colors"
          >
            <p className="text-sm font-medium text-gray-900">パスワードを変更</p>
            <svg className="w-5 h-5 text-gray-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
              <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M9 5l7 7-7 7" />
            </svg>
          </Link>
        </div>
        <div className="border-t pt-4">
        <AlertDialog>
          <AlertDialogTrigger asChild>
            <Button variant="destructive">ログアウト</Button>
          </AlertDialogTrigger>
          <AlertDialogContent>
            <AlertDialogHeader>
              <AlertDialogTitle>ログアウトしますか？</AlertDialogTitle>
              <AlertDialogDescription>
                ログアウトするとログイン画面に戻ります。
              </AlertDialogDescription>
            </AlertDialogHeader>
            <AlertDialogFooter>
              <AlertDialogCancel>キャンセル</AlertDialogCancel>
              <AlertDialogAction onClick={onLogout}>ログアウト</AlertDialogAction>
            </AlertDialogFooter>
          </AlertDialogContent>
        </AlertDialog>
        </div>
      </CardContent>
    </Card>
  )
}
