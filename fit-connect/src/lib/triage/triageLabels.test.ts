import { describe, it, expect } from 'vitest'
import {
  acknowledgeButtonLabel,
  acknowledgedToastDescription,
  clientHonorific,
  detailToggleLabel,
  formatUnrepliedElapsed,
  messageLinkLabel,
  recordLinkLabel,
  replyLinkLabel,
  showAllButtonLabel,
  TRIAGE_HELP_TEXT,
  triageBadgeLabel,
  triageCountAnnouncement,
  triageEmptyMessage,
  triageTimingNote,
  unrepliedChipLabel,
  unrepliedDetailNote,
  unrepliedDetailText,
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

  it('未返信のある行の主ボタン（返信する）', () => {
    expect(replyLinkLabel('田中')).toBe('田中さんに返信する')
    expect(replyLinkLabel('田中')).toContain('返信する')
    expect(replyLinkLabel('')).toBe('名前未設定の顧客に返信する')
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

  it('一部を読み込めていない0件は、読み込めた範囲の話だと断る（検知状態より優先）', () => {
    const partial = '読み込めた範囲では、確認が必要な顧客はいません'
    expect(triageEmptyMessage(fresh, true)).toBe(partial)
    expect(triageEmptyMessage(notRun, true)).toBe(partial)
    expect(triageEmptyMessage(null, true)).toBe(partial)
    expect(triageCountAnnouncement(0, fresh, true)).toBe(partial)
    // 行があれば人数を読む
    expect(triageCountAnnouncement(2, fresh, true)).toBe('今日の対応は2人です')
  })
})

describe('未返信の文言', () => {
  it('未返信の時間: 1時間未満 → N時間 → 48時間からは日数（どれも切り捨て）', () => {
    expect(formatUnrepliedElapsed(0)).toBe('1時間未満')
    expect(formatUnrepliedElapsed(1)).toBe('1時間')
    expect(formatUnrepliedElapsed(18)).toBe('18時間')
    expect(formatUnrepliedElapsed(47)).toBe('47時間')
    expect(formatUnrepliedElapsed(48)).toBe('2日')
    expect(formatUnrepliedElapsed(71)).toBe('2日')
    expect(formatUnrepliedElapsed(72)).toBe('3日')
    // RPC は最も古い未返信が7日より前の顧客も返す
    expect(formatUnrepliedElapsed(24 * 9 + 5)).toBe('9日')
  })

  it('未返信の時間: 負・小数・数でない値でも崩れない', () => {
    expect(formatUnrepliedElapsed(-3)).toBe('1時間未満')
    expect(formatUnrepliedElapsed(18.9)).toBe('18時間')
    expect(formatUnrepliedElapsed(Number.NaN)).toBe('1時間未満')
  })

  it('チップ「未返信 18時間・2件」', () => {
    expect(unrepliedChipLabel({ elapsedHours: 18, count: 2 })).toBe('未返信 18時間・2件')
    expect(unrepliedChipLabel({ elapsedHours: 0, count: 1 })).toBe('未返信 1時間未満・1件')
    expect(unrepliedChipLabel({ elapsedHours: 100, count: 3 })).toBe('未返信 4日・3件')
  })

  it('詳細文: 時刻は JST の M/D H:mm', () => {
    // 2026-09-20T05:05Z = JST 9/20 14:05、2026-09-21T00:12Z = JST 9/21 9:12
    expect(
      unrepliedDetailText({
        since: '2026-09-20T05:05:00Z',
        latestAt: '2026-09-20T05:05:00Z',
        count: 1,
      })
    ).toBe('9/20 14:05 に届いたメッセージに、まだ返信していません')
    expect(
      unrepliedDetailText({
        since: '2026-09-20T05:05:00Z',
        latestAt: '2026-09-21T00:12:00Z',
        count: 2,
      })
    ).toBe('9/20 14:05 以降に届いた2件のメッセージに、まだ返信していません（最新は 9/21 9:12）')
  })

  it('詳細文: JST の日付の境界（UTC では前日の 15:00 以降）', () => {
    expect(
      unrepliedDetailText({
        since: '2026-09-19T15:30:00Z',
        latestAt: '2026-09-19T15:30:00Z',
        count: 1,
      })
    ).toBe('9/20 0:30 に届いたメッセージに、まだ返信していません')
  })

  it('詳細文: 最新が最古と同じ時刻なら「最新は」を付けない / 時刻が読めなければ省く', () => {
    expect(
      unrepliedDetailText({
        since: '2026-09-20T05:05:00Z',
        latestAt: '2026-09-20T05:05:00Z',
        count: 2,
      })
    ).toBe('9/20 14:05 以降に届いた2件のメッセージに、まだ返信していません')
    expect(unrepliedDetailText({ since: 'broken', latestAt: 'broken', count: 3 })).toBe(
      '届いた3件のメッセージに、まだ返信していません'
    )
    expect(unrepliedDetailText({ since: 'broken', latestAt: 'broken', count: 1 })).toBe(
      '届いたメッセージに、まだ返信していません'
    )
  })
})

describe('見出しのヘルプ・判定の時点・未返信の注記', () => {
  it('ヘルプは未返信の定義・7日で外れること・未読との違いを伝える', () => {
    expect(TRIAGE_HELP_TEXT).toContain('最後のメッセージが顧客からで、まだ返信していない')
    expect(TRIAGE_HELP_TEXT).toContain('記録の投稿は含みません')
    expect(TRIAGE_HELP_TEXT).toContain('最後に届いた未返信から7日たつと')
    expect(TRIAGE_HELP_TEXT).toContain('未読の数')
  })

  it('判定の時点: 未返信は取得した時刻を JST の H:mm で出す', () => {
    expect(triageTimingNote(new Date('2026-09-22T00:05:00Z'))).toBe(
      '未返信は 9:05 時点、アラートは 6:00 時点の判定'
    )
    // JST の日付をまたぐ時刻（UTC 15:30 = JST 0:30）
    expect(triageTimingNote(new Date('2026-09-22T15:30:00Z'))).toBe(
      '未返信は 0:30 時点、アラートは 6:00 時点の判定'
    )
  })

  it('判定の時点: まだ取得していない・時刻が読めなければ「表示した時点」', () => {
    expect(triageTimingNote(null)).toBe('未返信は表示した時点、アラートは 6:00 時点の判定')
    expect(triageTimingNote(new Date('broken'))).toBe(
      '未返信は表示した時点、アラートは 6:00 時点の判定'
    )
  })

  it('未返信の注記: アラートもある行は、返信しても一覧に残ると伝える', () => {
    expect(unrepliedDetailNote(false)).toBe('返信すると、この一覧から外れます')
    expect(unrepliedDetailNote(true)).toBe(
      '返信すると、未返信の表示は消えます（アラートがあるため、この顧客は一覧に残ります）'
    )
    expect(unrepliedDetailNote(true)).not.toContain('一覧から外れます')
  })
})
