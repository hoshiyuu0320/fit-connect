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
          className="p-2 text-gray-500 hover:text-gray-700 disabled:opacity-50 disabled:cursor-not-allowed rounded hover:bg-gray-100"
          title={`画像を添付（最大${maxImages}枚）`}
        >
          <Paperclip className="h-5 w-5" />
        </button>

        {images.length > 0 && (
          <span className="text-xs text-gray-500">
            {images.length}/{maxImages}
          </span>
        )}
      </div>

      {/* プレビュー */}
      {images.length > 0 && (
        <div className="flex gap-2 mt-2">
          {images.map((file, index) => (
            <div key={index} className="relative group">
              <img
                src={URL.createObjectURL(file)}
                alt={`プレビュー ${index + 1}`}
                className="w-20 h-20 object-cover rounded border"
              />
              <button
                type="button"
                onClick={() => removeImage(index)}
                className="absolute -top-1.5 -right-1.5 bg-red-500 text-white rounded-full p-0.5 opacity-0 group-hover:opacity-100 transition-opacity"
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
        <div className="mt-2 border-2 border-dashed border-blue-400 bg-blue-50 rounded p-3 text-center text-sm text-blue-600">
          ここにドロップして画像を添付
        </div>
      )}
    </div>
  )
}
