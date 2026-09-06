'use client'

import {
  Dialog,
  DialogContent,
  DialogTitle,
} from '@/components/ui/dialog'
import { useStorageUrl } from '@/lib/supabase/signedStorageUrls'
import type { StorageBucket } from '@/lib/supabase/storagePaths'

interface ImageModalProps {
  /** Storage パス or フルURL（レガシー）。署名URL解決はモーダル内部で行う */
  imageUrl: string | null
  /** 値が属するバケット（既定: message-photos） */
  bucket?: StorageBucket
  onClose: () => void
}

export function ImageModal({ imageUrl, bucket = 'message-photos', onClose }: ImageModalProps) {
  const resolvedUrl = useStorageUrl(imageUrl, bucket)

  return (
    <Dialog open={!!imageUrl} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-4xl p-2 rounded-md border border-[#E2E8F0]">
        <DialogTitle className="sr-only">画像プレビュー</DialogTitle>
        {resolvedUrl && (
          <img
            src={resolvedUrl}
            alt="拡大画像"
            className="w-full h-auto max-h-[80vh] object-contain rounded-md"
          />
        )}
      </DialogContent>
    </Dialog>
  )
}
