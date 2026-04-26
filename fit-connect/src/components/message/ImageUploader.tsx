'use client'

import { useRef, useCallback, useState } from 'react'
import { Paperclip, X } from 'lucide-react'

interface ImageUploaderProps {
  images: File[]
  onImagesChange: (images: File[]) => void
  maxImages?: number
  disabled?: boolean
}

export function ImageUploader({
  images,
  onImagesChange,
  maxImages = 3,
  disabled = false,
}: ImageUploaderProps) {
  const fileInputRef = useRef<HTMLInputElement>(null)
  const [isDragging, setIsDragging] = useState(false)

  const addFiles = useCallback(
    (files: FileList | File[]) => {
      const newFiles = Array.from(files).slice(0, maxImages - images.length)
      if (newFiles.length === 0) return
      onImagesChange([...images, ...newFiles])
    },
    [images, maxImages, onImagesChange],
  )

  const removeImage = useCallback(
    (index: number) => {
      onImagesChange(images.filter((_, i) => i !== index))
    },
    [images, onImagesChange],
  )

  const handleDragOver = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(true)
  }, [])

  const handleDragLeave = useCallback((e: React.DragEvent) => {
    e.preventDefault()
    setIsDragging(false)
  }, [])

  const handleDrop = useCallback(
    (e: React.DragEvent) => {
      e.preventDefault()
      setIsDragging(false)
      if (disabled || images.length >= maxImages) return
      addFiles(e.dataTransfer.files)
    },
    [disabled, images.length, maxImages, addFiles],
  )

  const hasImages = images.length > 0

  return (
    <div
      onDragOver={handleDragOver}
      onDragLeave={handleDragLeave}
      onDrop={handleDrop}
    >
      <input
        ref={fileInputRef}
        type="file"
        accept="image/jpeg,image/png,image/webp,image/heic"
        multiple
        className="hidden"
        onChange={(e) => {
          if (e.target.files) addFiles(e.target.files)
          e.target.value = ''
        }}
        disabled={disabled}
      />

      <div className="flex items-center gap-2">
        <button
          type="button"
          onClick={() => fileInputRef.current?.click()}
          disabled={disabled || images.length >= maxImages}
          className={`p-2 border rounded-md transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${
            hasImages
              ? 'border-[#14B8A6] text-[#14B8A6] bg-[#F0FDFA]'
              : 'border-[#E2E8F0] text-[#94A3B8] bg-white hover:border-[#14B8A6] hover:text-[#14B8A6] hover:bg-[#F0FDFA]'
          }`}
          title={`画像を添付（最大${maxImages}枚）`}
        >
          <Paperclip className="h-5 w-5" />
        </button>

        {hasImages && (
          <span className="text-xs text-[#94A3B8]">
            {images.length}/{maxImages}
          </span>
        )}
      </div>

      {/* プレビュー */}
      {hasImages && (
        <div className="flex gap-2 mt-2">
          {images.map((file, index) => (
            <div key={index} className="relative group">
              <img
                src={URL.createObjectURL(file)}
                alt={`プレビュー ${index + 1}`}
                className="w-20 h-20 object-cover rounded-md border border-[#E2E8F0]"
              />
              <button
                type="button"
                onClick={() => removeImage(index)}
                className="absolute -top-1.5 -right-1.5 bg-[#DC2626] text-white rounded-full p-0.5 border-2 border-white opacity-0 group-hover:opacity-100 transition-opacity"
                disabled={disabled}
              >
                <X className="h-3 w-3" />
              </button>
            </div>
          ))}
        </div>
      )}

      {/* ドラッグ中のオーバーレイ */}
      {isDragging && (
        <div className="mt-2 border-2 border-dashed border-[#14B8A6] bg-[rgba(240,253,250,0.92)] rounded-md p-3 text-center text-sm text-[#14B8A6]">
          ここにドロップして画像を添付
          <p className="text-xs text-[#94A3B8] mt-1">JPEG / PNG / WebP / HEIC</p>
        </div>
      )}
    </div>
  )
}
