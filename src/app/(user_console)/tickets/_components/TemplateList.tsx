'use client'

import { useState } from 'react'
import type { TicketTemplate } from '@/types/client'
import { TICKET_TYPE_OPTIONS } from '@/types/client'
import { TemplateFormModal } from './TemplateFormModal'
import { DeleteTemplateDialog } from './DeleteTemplateDialog'
import { LayoutGrid, Clock, Calendar } from 'lucide-react'

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
        <h2 className="text-base font-semibold" style={{ color: '#0F172A' }}>テンプレート一覧</h2>
        <button
          onClick={() => setCreateOpen(true)}
          className="inline-flex items-center gap-1.5 px-4 py-2 text-sm font-medium text-white rounded-md transition-colors"
          style={{ backgroundColor: '#14B8A6' }}
          onMouseEnter={(e) => (e.currentTarget.style.backgroundColor = '#0D9488')}
          onMouseLeave={(e) => (e.currentTarget.style.backgroundColor = '#14B8A6')}
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
              className="bg-white border rounded-md transition-colors cursor-pointer"
              style={{
                borderColor: '#E2E8F0',
                borderLeft: template.is_recurring ? '3px solid #2563EB' : undefined,
              }}
              onMouseEnter={(e) => (e.currentTarget.style.borderColor = template.is_recurring ? '#2563EB' : '#14B8A6')}
              onMouseLeave={(e) => (e.currentTarget.style.borderColor = template.is_recurring ? '#2563EB' : '#E2E8F0')}
            >
              {/* カード上部 */}
              <div className="p-5">
                {/* テンプレート名 */}
                <h3 className="text-base font-bold mb-3" style={{ color: '#0F172A' }}>
                  {template.template_name}
                </h3>

                {/* 種別バッジ */}
                <div className="flex items-center gap-2 mb-4">
                  <span
                    className="inline-block px-2 py-0.5 text-xs font-medium border rounded-md"
                    style={{
                      backgroundColor: '#F0FDFA',
                      color: '#14B8A6',
                      borderColor: '#CCFBF1',
                    }}
                  >
                    {TICKET_TYPE_OPTIONS[template.ticket_type as keyof typeof TICKET_TYPE_OPTIONS] || template.ticket_type}
                  </span>
                  {template.is_recurring ? (
                    <span
                      className="inline-block px-2 py-0.5 text-xs font-medium border rounded-md"
                      style={{
                        backgroundColor: '#EFF6FF',
                        color: '#2563EB',
                        borderColor: '#BFDBFE',
                      }}
                    >
                      月契約
                    </span>
                  ) : (
                    <span
                      className="inline-block px-2 py-0.5 text-xs font-medium border rounded-md"
                      style={{
                        backgroundColor: '#F8FAFC',
                        color: '#94A3B8',
                        borderColor: '#E2E8F0',
                      }}
                    >
                      都度
                    </span>
                  )}
                </div>

                {/* 回数/有効期間 */}
                <div className="flex items-center gap-4">
                  <span className="flex items-center gap-1.5 text-sm" style={{ color: '#475569' }}>
                    <Clock size={14} style={{ color: '#94A3B8' }} />
                    {template.total_sessions}回
                  </span>
                  <span className="flex items-center gap-1.5 text-sm" style={{ color: '#475569' }}>
                    <Calendar size={14} style={{ color: '#94A3B8' }} />
                    {template.valid_months}ヶ月有効
                  </span>
                </div>
              </div>

              {/* 区切り線 */}
              <div style={{ borderTop: '1px solid #E2E8F0' }} />

              {/* アクションボタン */}
              <div className="flex items-center justify-end gap-2 px-5 py-3">
                <button
                  onClick={() => setEditTemplate(template)}
                  className="px-3 py-1 text-xs font-medium border rounded-md transition-colors"
                  style={{
                    backgroundColor: '#F8FAFC',
                    color: '#475569',
                    borderColor: '#E2E8F0',
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = '#F1F5F9'
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = '#F8FAFC'
                  }}
                >
                  編集
                </button>
                <button
                  onClick={() => setDeleteTemplate(template)}
                  className="px-3 py-1 text-xs font-medium border rounded-md transition-colors"
                  style={{
                    backgroundColor: '#FEF2F2',
                    color: '#DC2626',
                    borderColor: '#FECACA',
                  }}
                  onMouseEnter={(e) => {
                    e.currentTarget.style.backgroundColor = '#FEE2E2'
                  }}
                  onMouseLeave={(e) => {
                    e.currentTarget.style.backgroundColor = '#FEF2F2'
                  }}
                >
                  削除
                </button>
              </div>
            </div>
          ))}
        </div>
      ) : (
        <div
          className="flex items-center justify-center h-48 bg-white border rounded-md"
          style={{ borderColor: '#E2E8F0', borderStyle: 'dashed' }}
        >
          <div className="text-center">
            <div
              className="w-12 h-12 rounded-full flex items-center justify-center mx-auto mb-3"
              style={{ backgroundColor: '#F0FDFA' }}
            >
              <LayoutGrid size={24} style={{ color: '#14B8A6' }} />
            </div>
            <p className="text-sm mb-2" style={{ color: '#94A3B8' }}>テンプレートがありません</p>
            <button
              onClick={() => setCreateOpen(true)}
              className="text-sm font-medium transition-colors"
              style={{ color: '#14B8A6' }}
              onMouseEnter={(e) => (e.currentTarget.style.color = '#0D9488')}
              onMouseLeave={(e) => (e.currentTarget.style.color = '#14B8A6')}
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
