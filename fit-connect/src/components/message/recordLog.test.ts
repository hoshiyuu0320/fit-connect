import { describe, it, expect } from 'vitest'
import type { Message } from '@/types/client'
import { extractRecordLog, filterByType } from '@/components/message/recordLog'

function msg(id: string, content: string, tags?: string[] | null): Message {
  return {
    id, sender: 'c', content, timestamp: '', created_at: '2026-01-01T00:00:00Z',
    senderType: 'client', receiverType: 'trainer', image_urls: [], tags,
    is_edited: false, edited_at: null, read_at: null, reply_to_message_id: null,
  } as Message
}

describe('extractRecordLog', () => {
  it('tagsが非空のメッセージだけを記録として抽出しcardを付与', () => {
    const list = [
      msg('1', 'こんにちは'),
      msg('2', '#食事:昼食 サラダ', ['#食事:昼食']),
      msg('3', '#体重 62kg', ['#体重']),
    ]
    const out = extractRecordLog(list)
    expect(out).toHaveLength(2)
    expect(out[0].card.type).toBe('meal')
    expect(out[1].card.type).toBe('weight')
  })
  it('ワークアウト達成(#なし)も記録として拾う', () => {
    const list = [msg('1', '本日のワークアウトプラン「脚の日」を達成しました！')]
    const out = extractRecordLog(list)
    expect(out).toHaveLength(1)
    expect(out[0].card.type).toBe('achievement')
  })
})

describe('filterByType', () => {
  const items = extractRecordLog([
    msg('1', '#食事:昼食 サラダ', ['#食事:昼食']),
    msg('2', '#体重 62kg', ['#体重']),
    msg('3', '#運動:筋トレ ベンチ', ['#運動:筋トレ']),
  ])
  it('all は全件', () => {
    expect(filterByType(items, 'all')).toHaveLength(3)
  })
  it('meal は食事だけ', () => {
    const out = filterByType(items, 'meal')
    expect(out).toHaveLength(1)
    expect(out[0].card.type).toBe('meal')
  })
})
