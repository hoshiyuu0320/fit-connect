import { describe, it, expect } from 'vitest'
import {
  isTriageIncomplete,
  nextPartStatus,
  nextTriageBadgeCount,
  triageSectionPhase,
} from '@/lib/triage/triageLoadState'

describe('nextPartStatus', () => {
  it('成功すれば ready', () => {
    expect(nextPartStatus('loading', true)).toBe('ready')
    expect(nextPartStatus('failed', true)).toBe('ready')
    expect(nextPartStatus('ready', true)).toBe('ready')
  })

  it('初回の失敗・失敗の続きは failed', () => {
    expect(nextPartStatus('loading', false)).toBe('failed')
    expect(nextPartStatus('failed', false)).toBe('failed')
  })

  it('一度表示できた部分は、取り直しの失敗で failed にしない（前のデータを出し続ける）', () => {
    expect(nextPartStatus('ready', false)).toBe('ready')
  })
})

describe('triageSectionPhase', () => {
  it('どちらかがまだ結果を持たなければスケルトン', () => {
    expect(triageSectionPhase('loading', 'loading')).toBe('loading')
    expect(triageSectionPhase('ready', 'loading')).toBe('loading')
    expect(triageSectionPhase('loading', 'failed')).toBe('loading')
  })

  it('両方とも失敗したときだけ全体のエラー', () => {
    expect(triageSectionPhase('failed', 'failed')).toBe('error')
  })

  it('片方でも取れていれば一覧を出す（失敗した部分はセクション内で示す）', () => {
    expect(triageSectionPhase('ready', 'ready')).toBe('ready')
    expect(triageSectionPhase('failed', 'ready')).toBe('ready')
    expect(triageSectionPhase('ready', 'failed')).toBe('ready')
  })
})

describe('isTriageIncomplete', () => {
  it('どちらかの部分を出せていなければ一部だけ', () => {
    expect(isTriageIncomplete('failed', 'ready')).toBe(true)
    expect(isTriageIncomplete('ready', 'failed')).toBe(true)
    expect(isTriageIncomplete('ready', 'ready')).toBe(false)
  })
})

describe('nextTriageBadgeCount', () => {
  it('両方を取れたらその人数（前の値に関係なく）', () => {
    expect(nextTriageBadgeCount({ count: 5, complete: true }, { count: 2, complete: true })).toEqual({
      count: 2,
      complete: true,
    })
    expect(nextTriageBadgeCount({ count: 0, complete: false }, { count: 0, complete: true })).toEqual({
      count: 0,
      complete: true,
    })
  })

  it('表示直後（前に両方を取れた値が無い）に一部だけ取れたら、取れた分の人数を出す（0 のまま消さない）', () => {
    // 未返信の RPC だけ失敗し、open の high アラートが2人分取れた
    expect(nextTriageBadgeCount({ count: 0, complete: false }, { count: 2, complete: false })).toEqual({
      count: 2,
      complete: false,
    })
    // 一部だけの値が続くときは、新しい方に揃える（対応済みにして減った分も反映する）
    expect(nextTriageBadgeCount({ count: 2, complete: false }, { count: 1, complete: false })).toEqual({
      count: 1,
      complete: false,
    })
  })

  it('前に両方を取れた値があれば、一部だけの失敗では前の値を残す（取れた分より少なくはしない）', () => {
    expect(nextTriageBadgeCount({ count: 3, complete: true }, { count: 1, complete: false })).toEqual({
      count: 3,
      complete: true,
    })
    expect(nextTriageBadgeCount({ count: 3, complete: true }, { count: 4, complete: false })).toEqual({
      count: 4,
      complete: true,
    })
  })
})
