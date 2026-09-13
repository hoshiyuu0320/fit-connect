import { describe, it, expect } from 'vitest'
import {
  acknowledgeButtonLabel,
  acknowledgedToastDescription,
  clientHonorific,
  detailToggleLabel,
  messageLinkLabel,
  recordLinkLabel,
  showAllButtonLabel,
  triageBadgeLabel,
  triageCountAnnouncement,
  triageEmptyMessage,
} from '@/lib/triage/triageLabels'
import type { DetectionState } from '@/lib/alerts/detectionStatus'

const fresh: DetectionState = {
  kind: 'fresh',
  lastSucceededAt: '2026-09-12T21:00:00.000Z',
  lastCheckedLabel: '9/13 6:00',
}
const notRun: DetectionState = { kind: 'not_run', lastSucceededAt: null, lastCheckedLabel: null }
const pausedNeverRun: DetectionState = { kind: 'paused', lastSucceededAt: null, lastCheckedLabel: null }

describe('clientHonorific', () => {
  it('名前に「さん」を付ける（前後の空白は除く）', () => {
    expect(clientHonorific('田中 太郎')).toBe('田中 太郎さん')
    expect(clientHonorific('  田中  ')).toBe('田中さん')
  })

  it('名前が空なら「名前未設定の顧客」', () => {
    expect(clientHonorific('')).toBe('名前未設定の顧客')
    expect(clientHonorific('   ')).toBe('名前未設定の顧客')
  })
})

describe('アクセシブルな名前（顧客名と種別を入れ、見える文字を含める）', () => {
  it('対応済みボタン', () => {
    const label = acknowledgeButtonLabel('田中', '体重の変化')
    expect(label).toBe('田中さんの体重の変化を対応済みにする')
    expect(label).toContain('対応済みにする')
  })

  it('記録・メッセージのリンクと、行の開閉ボタン', () => {
    expect(recordLinkLabel('田中')).toBe('田中さんの記録を見る')
    expect(recordLinkLabel('田中')).toContain('記録を見る')
    expect(messageLinkLabel('田中')).toBe('田中さんにメッセージを送る')
    expect(messageLinkLabel('田中')).toContain('メッセージ')
    expect(detailToggleLabel('田中')).toBe('田中さんの詳細')
    expect(detailToggleLabel('田中')).toContain('詳細')
  })

  it('名前が空でも文として読める', () => {
    expect(acknowledgeButtonLabel('', '記録なし')).toBe('名前未設定の顧客の記録なしを対応済みにする')
    expect(recordLinkLabel('')).toBe('名前未設定の顧客の記録を見る')
  })
})

describe('一覧まわりの文言', () => {
  it('すべて表示 / 上位N件だけ表示', () => {
    expect(showAllButtonLabel(false, 8, 5)).toBe('すべて表示（8件）')
    expect(showAllButtonLabel(true, 8, 5)).toBe('上位5件だけ表示')
  })

  it('トーストの補足とバッジの読み上げ', () => {
    expect(acknowledgedToastDescription('田中', '記録・同期なし')).toBe('田中さんの記録・同期なし')
    expect(triageBadgeLabel(3)).toBe('今日の対応 3人')
  })

  it('0件の文言: 本実行が一度も成功していなければ「いません」と言い切らない', () => {
    expect(triageEmptyMessage(fresh)).toBe('確認が必要な顧客はいません')
    expect(triageEmptyMessage(notRun)).toBe('自動チェックの結果はまだありません')
    expect(triageEmptyMessage(pausedNeverRun)).toBe('自動チェックの結果はまだありません')
    // 検知状態が分からないときは、一覧が空であることだけ
    expect(triageEmptyMessage(null)).toBe('確認が必要な顧客はいません')
  })

  it('件数の読み上げ', () => {
    expect(triageCountAnnouncement(3, fresh)).toBe('今日の対応は3人です')
    expect(triageCountAnnouncement(0, fresh)).toBe('確認が必要な顧客はいません')
    expect(triageCountAnnouncement(0, notRun)).toBe('自動チェックの結果はまだありません')
  })
})
