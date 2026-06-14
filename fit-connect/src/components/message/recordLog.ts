import type { Message } from '@/types/client'
import {
  parseRecordMessage,
  type RecordCardData,
  type RecordCardType,
} from '@/components/message/recordCardParser'

export interface RecordLogItem {
  message: Message
  card: RecordCardData
}

/** messages から記録（parseRecordMessage が非nullを返すもの）だけを抽出し、card を付与する。 */
export function extractRecordLog(messages: Message[]): RecordLogItem[] {
  const items: RecordLogItem[] = []
  for (const m of messages) {
    const card = parseRecordMessage(m.content, m.tags)
    if (card) items.push({ message: m, card })
  }
  return items
}

/** 種別（all/weight/meal/exercise/achievement）で絞り込む。 */
export function filterByType(
  items: RecordLogItem[],
  type: RecordCardType | 'all',
): RecordLogItem[] {
  if (type === 'all') return items
  return items.filter((it) => it.card.type === type)
}
