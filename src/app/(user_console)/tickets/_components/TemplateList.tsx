'use client'

import { useState } from 'react'
import type { TicketTemplate } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'
import { TemplateFormModal } from './TemplateFormModal'
import { DeleteTemplateDialog } from './DeleteTemplateDialog'

interface TemplateListProps {
  templates: TicketTemplate[]
  trainerId: string
  onRefetch: () => void
}

export function TemplateList({ templates, trainerId, onRefetch }: TemplateListProps) {
  const [createOpen, setCreateOpen] = useState(false)
  const [editTemplate, setEditTemplate] = useState<TicketTemplate | null>(null)
  const [deleteTemplate, setDeleteTemplate] = useState<TicketTemplate | null>(null)

  return (
    <div className="space-y-4">
      {/* ヘッダー */}
      <div className="flex items-center justify-between">
        <h2 className="text-lg font-semibold text-gray-900">テンプレート</h2>
        <button
          onClick={() => setCreateOpen(true)}
          className="inline-flex items-center px-4 py-2 text-sm font-medium text-white bg-blue-600 rounded-md hover:bg-blue-700"
        >
          + テンプレート作成
        </button>
      </div>

      {/* テンプレート一覧 */}
      {templates.length > 0 ? (
        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
          {templates.map((template) => (
            <div
              key={template.id}
              className="bg-white rounded-lg shadow-sm border p-5"
            >
              {/* テンプレート名 */}
              <h3 className="text-base font-bold text-gray-900 mb-2">
                {template.template_name}
              </h3>

              {/* 種別バッジ */}
              <div className="flex items-center space-x-2 mb-2">
                <span className="inline-block px-2 py-1 text-xs font-medium bg-gray-100 text-gray-700 rounded">
                  {TICKET_TYPE_OPTIONS[template.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] || template.ticket_type}
                </span>
                {template.is_recurring ? (
                  <span className="inline-block px-2 py-1 text-xs font-medium bg-blue-100 text-blue-700 rounded">
                    月契約
                  </span>
                ) : (
                  <span className="inline-block px-2 py-1 text-xs font-medium bg-gray-100 text-gray-500 rounded">
                    都度
                  </span>
                )}
              </div>

              {/* 回数/有効期間 */}
              <p className="text-sm text-gray-600 mb-4">
                {template.total_sessions}回 / {template.valid_months}ヶ月有効
              </p>

              {/* アクションボタン */}
              <div className="flex items-center justify-end space-x-2">
                <button
                  onClick={() => setEditTemplate(template)}
                  className="px-3 py-1 text-xs font-medium text-gray-700 bg-gray-100 rounded-md hover:bg-gray-200"
                >
                  編集
                </button>
                <button
                  onClick={() => setDeleteTemplate(template)}
                  className="px-3 py-1 text-xs font-medium text-red-600 bg-red-50 rounded-md hover:bg-red-100"
                >
                  削除
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div className="flex items-center justify-center h-48 bg-white rounded-lg shadow-sm border">
          <div className="text-center">
            <p className="text-gray-500 mb-2">テンプレートがありません</p>
            <button
              onClick={() => setCreateOpen(true)}
              className="text-sm text-blue-600 hover:text-blue-700 font-medium"
            >
              最初のテンプレートを作成する
            </button>
          </div>
        </div>
      )}

      {/* モーダル */}
      <TemplateFormModal
        open={createOpen}
        onOpenChange={setCreateOpen}
        template={null}
        trainerId={trainerId}
        onSaved={onRefetch}
      />

      <TemplateFormModal
        open={!!editTemplate}
        onOpenChange={(open) => !open && setEditTemplate(null)}
        template={editTemplate}
        trainerId={trainerId}
        onSaved={onRefetch}
      />

      <DeleteTemplateDialog
        open={!!deleteTemplate}
        onOpenChange={(open) => !open && setDeleteTemplate(null)}
        template={deleteTemplate}
        onDeleted={onRefetch}
      />
    </div>
  )
}
