import { describe, it, expect } from 'vitest'
import {
  createTriageListState,
  triageListReducer,
  selectVisibleAlerts,
  selectTriageListView,
  isClientExpanded,
  TRIAGE_INITIAL_LIMIT,
  type TriageListAction,
  type TriageListState,
} from '@/lib/triage/triageListState'
import type { ClientAlert } from '@/types/alert'

function makeAlert(id: string, overrides: Partial<ClientAlert> = {}): ClientAlert {
  return {
    id,
    client_id: `client-${id}`,
    alert_type: 'record_gap',
    severity: 'medium',
    status: 'open',
    payload: {
      v: 1,
      variant: 'no_data',
      gap_from: '2026-09-09',
      gap_to: '2026-09-12',
      last_activity_on: '2026-09-08',
      last_record_on: '2026-09-08',
      threshold_days: 3,
    },
    first_detected_on: '2026-09-12',
    surfaced_on: '2026-09-12',
    last_detected_on: '2026-09-13',
    acknowledged_at: null,
    reopened_count: 0,
    client_name: `顧客${id}`,
    client_profile_image_url: null,
    ...overrides,
  }
}

const A = makeAlert('a')
const B = makeAlert('b')

/** 順に dispatch した結果 */
function run(state: TriageListState, ...actions: TriageListAction[]): TriageListState {
  return actions.reduce(triageListReducer, state)
}

const visibleIds = (state: TriageListState) => selectVisibleAlerts(state).map((a) => a.id)

describe('対応済み（楽観的更新）', () => {
  it('押した直後に一覧から外れ、成功しても外れたまま', () => {
    const s1 = run(createTriageListState([A, B]), { type: 'acknowledge', alertId: 'a' })
    expect(visibleIds(s1)).toEqual(['b'])
    expect(s1.hidden.a.phase).toBe('pending')

    const s2 = run(s1, { type: 'acknowledgeSucceeded', alertId: 'a' })
    expect(visibleIds(s2)).toEqual(['b'])
    expect(s2.hidden.a.phase).toBe('done')
  })

  it('API が失敗したら行に戻す（巻き戻し）', () => {
    const state = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeFailed', alertId: 'a' }
    )
    expect(visibleIds(state)).toEqual(['a', 'b'])
    expect(state.hidden).toEqual({})
  })

  it('二度押し・一覧に無い id は何もしない（同じ state を返す）', () => {
    const s1 = run(createTriageListState([A]), { type: 'acknowledge', alertId: 'a' })
    expect(triageListReducer(s1, { type: 'acknowledge', alertId: 'a' })).toBe(s1)
    expect(triageListReducer(s1, { type: 'acknowledge', alertId: 'zzz' })).toBe(s1)
    expect(triageListReducer(s1, { type: 'acknowledgeFailed', alertId: 'zzz' })).toBe(s1)
    expect(triageListReducer(s1, { type: 'undo', alertId: 'zzz' })).toBe(s1)
  })

  it('成功後に届いた失敗（順序の乱れ）では戻さない', () => {
    const state = run(
      createTriageListState([A]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'acknowledgeFailed', alertId: 'a' }
    )
    expect(visibleIds(state)).toEqual([])
  })

  it('元の state を書き換えない', () => {
    const initial = createTriageListState([A, B])
    const snapshot = JSON.stringify(initial)
    run(
      initial,
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' },
      { type: 'toggleExpanded', clientId: 'client-a' },
      { type: 'toggleShowAll' }
    )
    expect(JSON.stringify(initial)).toBe(snapshot)
  })
})

describe('元に戻す', () => {
  it('成功済みを元に戻すと行に戻り、reopen が成功すればそのまま', () => {
    const s1 = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' }
    )
    expect(visibleIds(s1)).toEqual(['a', 'b'])
    expect(Object.keys(s1.restoring)).toEqual(['a'])

    const s2 = run(s1, { type: 'undoSucceeded', alertId: 'a' })
    expect(visibleIds(s2)).toEqual(['a', 'b'])
    expect(s2.restoring).toEqual({})
  })

  it('reopen が失敗したら再び外す', () => {
    const state = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' },
      { type: 'undoFailed', alertId: 'a' }
    )
    expect(visibleIds(state)).toEqual(['b'])
    expect(state.hidden.a.phase).toBe('done')
    expect(state.restoring).toEqual({})
  })

  it('取り直しで一覧から消えた後でも、持っておいたデータで行に戻せる', () => {
    const state = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'loaded', alerts: [B] }, // サーバーでは acknowledged なので open の一覧に居ない
      { type: 'undo', alertId: 'a' }
    )
    expect(visibleIds(state).sort()).toEqual(['a', 'b'])
  })

  it('acknowledge の応答待ちの間に元に戻すと行に戻り、あとから届いた成功で外し直さない', () => {
    const s1 = run(
      createTriageListState([A]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'undo', alertId: 'a' }
    )
    expect(visibleIds(s1)).toEqual(['a'])

    const s2 = run(s1, { type: 'acknowledgeSucceeded', alertId: 'a' })
    expect(visibleIds(s2)).toEqual(['a'])
    expect(s2.hidden).toEqual({})

    const s3 = run(s1, { type: 'acknowledgeFailed', alertId: 'a' })
    expect(visibleIds(s3)).toEqual(['a'])
  })

  it('元に戻している途中にもう一度対応済みにできる', () => {
    const state = run(
      createTriageListState([A]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' },
      { type: 'acknowledge', alertId: 'a' }
    )
    expect(visibleIds(state)).toEqual([])
    expect(state.hidden.a.phase).toBe('pending')
    expect(state.restoring).toEqual({})
  })
})

describe('取り直し（loaded）', () => {
  it('一覧をサーバーの open に置き換える', () => {
    const C = makeAlert('c')
    const state = run(createTriageListState([A, B]), { type: 'loaded', alerts: [B, C] })
    expect(visibleIds(state)).toEqual(['b', 'c'])
  })

  it('acknowledge の応答待ち中に届いた一覧（まだ open に居る）でも外したまま', () => {
    const state = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'loaded', alerts: [A, B] }
    )
    expect(visibleIds(state)).toEqual(['b'])
    expect(state.hidden.a.phase).toBe('pending')
  })

  it('成功済みのものが open の一覧に居たら出す（翌朝の昇格で再浮上した場合など）', () => {
    const escalated = makeAlert('a', { severity: 'high', surfaced_on: '2026-09-14', reopened_count: 1 })
    const state = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'loaded', alerts: [escalated, B] }
    )
    expect(visibleIds(state)).toEqual(['a', 'b'])
    expect(selectVisibleAlerts(state)[0].severity).toBe('high')
    expect(state.hidden).toEqual({})
  })

  it('reopen の反映前に届いた一覧（まだ open に居ない）でも、元に戻したものは出し続ける', () => {
    const s1 = run(
      createTriageListState([A, B]),
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' },
      { type: 'loaded', alerts: [B] }
    )
    expect(visibleIds(s1).sort()).toEqual(['a', 'b'])

    // reopen が反映された後の取り直しでは二重にならない
    const s2 = run(s1, { type: 'undoSucceeded', alertId: 'a' }, { type: 'loaded', alerts: [A, B] })
    expect(visibleIds(s2)).toEqual(['a', 'b'])
  })
})

describe('展開', () => {
  it('行の詳細は顧客ごとに開閉する', () => {
    const s1 = run(createTriageListState([A, B]), { type: 'toggleExpanded', clientId: 'client-a' })
    expect(isClientExpanded(s1, 'client-a')).toBe(true)
    expect(isClientExpanded(s1, 'client-b')).toBe(false)

    const s2 = run(s1, { type: 'toggleExpanded', clientId: 'client-b' }, { type: 'toggleExpanded', clientId: 'client-a' })
    expect(isClientExpanded(s2, 'client-a')).toBe(false)
    expect(isClientExpanded(s2, 'client-b')).toBe(true)
  })

  it('対応済みで行が消えて元に戻したとき、開いていた状態も戻る', () => {
    const state = run(
      createTriageListState([A]),
      { type: 'toggleExpanded', clientId: 'client-a' },
      { type: 'acknowledge', alertId: 'a' },
      { type: 'acknowledgeSucceeded', alertId: 'a' },
      { type: 'undo', alertId: 'a' }
    )
    expect(isClientExpanded(state, 'client-a')).toBe(true)
  })
})

describe('selectTriageListView', () => {
  const many = Array.from({ length: TRIAGE_INITIAL_LIMIT + 2 }, (_, i) => makeAlert(`m${i}`))

  it('上位5件を出し、「すべて表示」で全件を出す', () => {
    const s1 = createTriageListState(many)
    const v1 = selectTriageListView(s1)
    expect(v1.totalCount).toBe(7)
    expect(v1.displayedRows).toHaveLength(TRIAGE_INITIAL_LIMIT)
    expect(v1.hasMore).toBe(true)

    const v2 = selectTriageListView(triageListReducer(s1, { type: 'toggleShowAll' }))
    expect(v2.displayedRows).toHaveLength(7)
    expect(v2.hasMore).toBe(true)
  })

  it('5件以下なら「すべて表示」は出さない', () => {
    const view = selectTriageListView(createTriageListState([A, B]))
    expect(view.hasMore).toBe(false)
    expect(view.displayedRows).toHaveLength(2)
  })

  it('見出しの件数とバッジの数は、外したものを除いた顧客の数で揃う', () => {
    const sameClient = makeAlert('a2', { client_id: 'client-a', alert_type: 'weight_change' })
    const s1 = createTriageListState([A, sameClient, B])
    expect(selectTriageListView(s1).totalCount).toBe(2)
    expect(selectTriageListView(s1).badgeCount).toBe(2)

    // 顧客 a の理由を1つだけ対応済みにしても、行は残る
    const s2 = run(s1, { type: 'acknowledge', alertId: 'a' })
    expect(selectTriageListView(s2).totalCount).toBe(2)
    expect(selectTriageListView(s2).rows.find((r) => r.clientId === 'client-a')?.reasons).toHaveLength(1)

    // 残りも対応済みにすると、行とバッジから消える
    const s3 = run(s2, { type: 'acknowledge', alertId: 'a2' })
    expect(selectTriageListView(s3).totalCount).toBe(1)
    expect(selectTriageListView(s3).badgeCount).toBe(1)
  })
})
