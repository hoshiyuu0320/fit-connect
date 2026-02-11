'use client'

import {
  Dialog,
  DialogContent,
  DialogTitle,
} from '@/components/ui/dialog'

interface ImageModalProps {
  imageUrl: string | null
  onClose: () => void
}

export function ImageModal({ imageUrl, onClose }: ImageModalProps) {
  return (
    <Dialog open={!!imageUrl} onOpenChange={(open) => !open && onClose()}>
      <DialogContent className="max-w-4xl p-2">
        <DialogTitle className="sr-only">画像プレビュー</DialogTitle>
        {imageUrl && (
          <img
            src={imageUrl}
            alt="拡大画像"
            className="w-full h-auto max-h-[80vh] object-contain rounded"
          />
        )}
      </DialogContent>
    </Dialog>
  )
}
