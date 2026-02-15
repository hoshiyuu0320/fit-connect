'use client'

import { useState } from 'react'
import { QRCodeCanvas } from 'qrcode.react'
import { Dialog, DialogContent, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { Label } from '@/components/ui/label'
import { Copy, Download } from 'lucide-react'

type ClientInviteModalProps = {
  open: boolean
  onOpenChange: (open: boolean) => void
  trainerId: string
}

export default function ClientInviteModal({ open, onOpenChange, trainerId }: ClientInviteModalProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    try {
      await navigator.clipboard.writeText(trainerId)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    } catch (error) {
      console.error('コピーに失敗しました:', error)
      // Fallback for older browsers
      const input = document.createElement('input')
      input.value = trainerId
      document.body.appendChild(input)
      input.select()
      document.execCommand('copy')
      document.body.removeChild(input)
      setCopied(true)
      setTimeout(() => setCopied(false), 2000)
    }
  }

  const handleDownloadQR = () => {
    const canvas = document.getElementById('invite-qr-code') as HTMLCanvasElement
    if (!canvas) return

    const url = canvas.toDataURL('image/png')
    const link = document.createElement('a')
    link.href = url
    link.download = 'fitconnect-invite.png'
    link.click()
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent className="sm:max-w-[500px] bg-white">
        <DialogHeader>
          <DialogTitle>クライアントを招待</DialogTitle>
        </DialogHeader>

        <div className="space-y-6">
          {/* 説明テキスト */}
          <p className="text-sm text-gray-600 text-center">
            QRコードをスキャンするか、招待コードをアプリで入力してください
          </p>

          {/* QRコード表示 */}
          <div className="flex justify-center">
            <div className="bg-white border rounded-lg p-4">
              <QRCodeCanvas
                id="invite-qr-code"
                value={trainerId}
                size={256}
                level="H"
                includeMargin={true}
              />
            </div>
          </div>

          {/* 招待コード */}
          <div className="space-y-2">
            <Label htmlFor="invite-code">招待コード</Label>
            <div className="flex gap-2">
              <Input
                id="invite-code"
                type="text"
                value={trainerId}
                readOnly
                className="font-mono text-sm"
              />
              <Button
                type="button"
                variant="outline"
                size="icon"
                onClick={handleCopy}
                className="shrink-0"
              >
                <Copy className="h-4 w-4" />
              </Button>
            </div>
            {copied && (
              <p className="text-sm text-emerald-600 flex items-center gap-1">
                <span>✓</span>
                <span>コピーしました</span>
              </p>
            )}
          </div>

          {/* ダウンロードボタン */}
          <Button
            type="button"
            variant="outline"
            onClick={handleDownloadQR}
            className="w-full"
          >
            <Download className="h-4 w-4 mr-2" />
            QRコードをダウンロード
          </Button>
        </div>
      </DialogContent>
    </Dialog>
  )
}
