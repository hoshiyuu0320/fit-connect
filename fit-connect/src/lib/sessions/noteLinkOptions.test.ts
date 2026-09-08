import { describe, it, expect } from 'vitest'
import {
  isNoteLinkableSession,
  buildNoteLinkOptions,
  formatSessionOptionLabel,
  selectNoteLinkSession,
  seedNoteLinkSession,
  initialNoteLinkSelection,
  pickSessionForAssignment,
  EMPTY_SESSION_SELECTION_FIELD,
  type SessionRow,
  type ClientSessionOption,
} from './noteLinkOptions'

const NOW = new Date('2026-09-06T12:00:00Z')

const row = (over: Partial<SessionRow> & Pick<SessionRow, 'id'>): SessionRow => ({
  session_date: '2026-09-01T01:00:00Z',
  session_type: 'パーソナル',
  status: 'completed',
  ...over,
})

describe('isNoteLinkableSession', () => {
  it('completed は対象（過去）', () => {
    expect(isNoteLinkableSession(row({ id: 'a', status: 'completed' }), NOW)).toBe(true)
  })

  it('completed は未来日時でも対象', () => {
    const session = row({ id: 'a', status: 'completed', session_date: '2026-12-31T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(true)
  })

  it('過去の scheduled は対象（完了にし忘れた予定を拾う）', () => {
    const session = row({ id: 'a', status: 'scheduled', session_date: '2026-09-05T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(true)
  })

  it('過去の confirmed も対象', () => {
    const session = row({ id: 'a', status: 'confirmed', session_date: '2026-09-05T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(true)
  })

  it('未来の scheduled は対象外', () => {
    const session = row({ id: 'a', status: 'scheduled', session_date: '2026-09-07T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })

  it('未来の confirmed は対象外', () => {
    const session = row({ id: 'a', status: 'confirmed', session_date: '2026-09-07T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })

  it('cancelled は過去でも対象外', () => {
    const session = row({ id: 'a', status: 'cancelled', session_date: '2026-01-01T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })

  it('cancelled は completed 以外の判定より優先される（未来も対象外）', () => {
    const session = row({ id: 'a', status: 'cancelled', session_date: '2026-12-31T01:00:00Z' })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })

  it('ちょうど now の scheduled は対象外（< now の判定）', () => {
    const session = row({ id: 'a', status: 'scheduled', session_date: NOW.toISOString() })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })

  it('壊れた日時は対象外', () => {
    const session = row({ id: 'a', status: 'scheduled', session_date: 'not-a-date' })
    expect(isNoteLinkableSession(session, NOW)).toBe(false)
  })
})

describe('buildNoteLinkOptions', () => {
  const rows: SessionRow[] = [
    row({ id: 's3', session_date: '2026-09-05T01:00:00Z', status: 'scheduled' }), // 過去の未完了 → 対象
    row({ id: 's1', session_date: '2026-07-01T01:00:00Z', status: 'completed' }),
    row({ id: 'future', session_date: '2026-09-20T01:00:00Z', status: 'scheduled' }), // 対象外
    row({ id: 'cancelled', session_date: '2026-08-10T01:00:00Z', status: 'cancelled' }), // 対象外
    row({ id: 's2', session_date: '2026-08-01T01:00:00Z', status: 'completed' }),
  ]

  it('対象外（未来・キャンセル）を除外する', () => {
    const options = buildNoteLinkOptions(rows, [], NOW)
    expect(options.map((o) => o.id)).toEqual(['s3', 's2', 's1'])
  })

  it('新しい順で返す', () => {
    const options = buildNoteLinkOptions(rows, [], NOW)
    expect(options.map((o) => o.session_date)).toEqual([
      '2026-09-05T01:00:00Z',
      '2026-08-01T01:00:00Z',
      '2026-07-01T01:00:00Z',
    ])
  })

  it('入力の並び順が変わっても結果は同じ', () => {
    const ascending = [...rows].sort(
      (a, b) => new Date(a.session_date).getTime() - new Date(b.session_date).getTime(),
    )
    expect(buildNoteLinkOptions(ascending, [], NOW)).toEqual(buildNoteLinkOptions(rows, [], NOW))
  })

  it('元の配列を破壊しない', () => {
    const input = [...rows]
    buildNoteLinkOptions(input, [], NOW)
    expect(input.map((r) => r.id)).toEqual(rows.map((r) => r.id))
  })

  it('紐づき済みのセッションに has_note を立てる', () => {
    const options = buildNoteLinkOptions(rows, ['s2'], NOW)
    expect(options.map((o) => [o.id, o.has_note])).toEqual([
      ['s3', false],
      ['s2', true],
      ['s1', false],
    ])
  })

  it('対象外セッションの紐づけ id が混ざっても無視される', () => {
    const options = buildNoteLinkOptions(rows, ['cancelled', 'unknown'], NOW)
    expect(options.every((o) => o.has_note === false)).toBe(true)
  })

  it('同時刻のセッションは id で安定して並ぶ', () => {
    const sameTime: SessionRow[] = [
      row({ id: 'a', session_date: '2026-08-01T01:00:00Z' }),
      row({ id: 'b', session_date: '2026-08-01T01:00:00Z' }),
    ]
    const options = buildNoteLinkOptions(sameTime, [], NOW)
    expect(options.map((o) => o.id)).toEqual(['b', 'a'])
  })

  it('対象が無ければ空配列', () => {
    const onlyFuture = [row({ id: 'f', session_date: '2026-12-01T01:00:00Z', status: 'scheduled' })]
    expect(buildNoteLinkOptions(onlyFuture, [], NOW)).toEqual([])
  })
})

describe('formatSessionOptionLabel', () => {
  // タイムゾーン非依存にするためオフセット無しのローカル日時で組み立てる
  const option = (over: Partial<ClientSessionOption> = {}): ClientSessionOption => ({
    id: 's1',
    session_date: '2026-08-01T09:30:00',
    session_type: 'パーソナル',
    status: 'completed',
    has_note: false,
    ...over,
  })

  it('日時と種別を並べる', () => {
    expect(formatSessionOptionLabel(option())).toBe('2026/08/01 09:30 ・ パーソナル')
  })

  it('種別が無ければ日時のみ', () => {
    expect(formatSessionOptionLabel(option({ session_type: null }))).toBe('2026/08/01 09:30')
  })

  it('紐づき済みは（カルテ作成済み）を付ける', () => {
    expect(formatSessionOptionLabel(option({ has_note: true }))).toBe(
      '2026/08/01 09:30 ・ パーソナル（カルテ作成済み）',
    )
  })

  it('種別が無く紐づき済みの場合', () => {
    expect(formatSessionOptionLabel(option({ session_type: null, has_note: true }))).toBe(
      '2026/08/01 09:30（カルテ作成済み）',
    )
  })
})

describe('selectNoteLinkSession / seedNoteLinkSession', () => {
  const options: ClientSessionOption[] = [
    {
      id: 's2',
      session_date: '2026-08-01T09:30:00',
      session_type: 'パーソナル',
      status: 'completed',
      has_note: false,
    },
    {
      id: 's1',
      session_date: '2026-07-01T09:30:00',
      session_type: 'パーソナル',
      status: 'completed',
      has_note: false,
    },
  ]

  it('選択すると manual になる', () => {
    expect(selectNoteLinkSession('s1')).toEqual({ value: 's1', source: 'manual' })
  })

  it('「紐づけない」を選んでも manual', () => {
    expect(selectNoteLinkSession('')).toEqual({ value: '', source: 'manual' })
  })

  it('初期選択を反映すると auto になる', () => {
    expect(seedNoteLinkSession(EMPTY_SESSION_SELECTION_FIELD, 's2', options)).toEqual({
      value: 's2',
      source: 'auto',
    })
  })

  it('初期選択が別のセッションに変わったら auto の値を差し替える', () => {
    const seeded = seedNoteLinkSession(EMPTY_SESSION_SELECTION_FIELD, 's2', options)
    expect(seedNoteLinkSession(seeded, 's1', options)).toEqual({ value: 's1', source: 'auto' })
  })

  it('トレーナーが選んだ後の初期選択は無視する（開き直しで巻き戻らない）', () => {
    const chosen = selectNoteLinkSession('s1')
    expect(seedNoteLinkSession(chosen, 's2', options)).toEqual(chosen)
  })

  it('トレーナーが「紐づけない」を選んだ後も初期選択で戻さない', () => {
    const cleared = selectNoteLinkSession('')
    expect(seedNoteLinkSession(cleared, 's2', options)).toEqual(cleared)
  })

  it('初期選択が選択肢に無ければ「紐づけない」になる', () => {
    expect(seedNoteLinkSession(EMPTY_SESSION_SELECTION_FIELD, 'unknown', options)).toEqual(
      EMPTY_SESSION_SELECTION_FIELD,
    )
  })

  it('初期選択が未指定なら「紐づけない」のまま', () => {
    expect(seedNoteLinkSession(EMPTY_SESSION_SELECTION_FIELD, null, options)).toEqual(
      EMPTY_SESSION_SELECTION_FIELD,
    )
  })

  it('auto の状態で初期選択が外れたら「紐づけない」に戻る', () => {
    const seeded = seedNoteLinkSession(EMPTY_SESSION_SELECTION_FIELD, 's2', options)
    expect(seedNoteLinkSession(seeded, null, options)).toEqual(EMPTY_SESSION_SELECTION_FIELD)
  })
})

describe('initialNoteLinkSelection', () => {
  it('保存済みの紐づけは manual（初期選択に巻き戻されない）', () => {
    expect(initialNoteLinkSelection({ session_id: 's1' })).toEqual({
      value: 's1',
      source: 'manual',
    })
  })

  it('紐づけ無しのカルテは空の状態', () => {
    expect(initialNoteLinkSelection({ session_id: null })).toEqual(EMPTY_SESSION_SELECTION_FIELD)
    expect(initialNoteLinkSelection({})).toEqual(EMPTY_SESSION_SELECTION_FIELD)
  })
})

describe('pickSessionForAssignment', () => {
  // タイムゾーン非依存にするためオフセット無しのローカル日時で組み立てる
  const option = (id: string, session_date: string): ClientSessionOption => ({
    id,
    session_date,
    session_type: 'パーソナル',
    status: 'completed',
    has_note: false,
  })

  const options: ClientSessionOption[] = [
    option('s3', '2026-09-08T10:00:00'),
    option('s2', '2026-09-07T10:00:00'),
    option('s1', '2026-09-01T10:00:00'),
  ]

  it('session_id があればそれを返す（選択肢に無くても）', () => {
    expect(
      pickSessionForAssignment(options, { session_id: 'linked', assigned_date: '2026-09-08' }),
    ).toBe('linked')
  })

  it('session_id が無く同日のセッションが1件ならその id', () => {
    expect(
      pickSessionForAssignment(options, { session_id: null, assigned_date: '2026-09-07' }),
    ).toBe('s2')
  })

  it('同日のセッションが無ければ null', () => {
    expect(
      pickSessionForAssignment(options, { session_id: null, assigned_date: '2026-09-05' }),
    ).toBeNull()
  })

  it('同日のセッションが2件あれば null（推測で紐づけない）', () => {
    const twoSameDay = [...options, option('s4', '2026-09-07T18:00:00')]
    expect(
      pickSessionForAssignment(twoSameDay, { session_id: null, assigned_date: '2026-09-07' }),
    ).toBeNull()
  })

  it('選択肢が空なら null', () => {
    expect(pickSessionForAssignment([], { session_id: null, assigned_date: '2026-09-07' })).toBeNull()
  })

  it('壊れた日時の選択肢は無視する', () => {
    const withBroken = [option('broken', 'not-a-date'), option('s2', '2026-09-07T10:00:00')]
    expect(
      pickSessionForAssignment(withBroken, { session_id: null, assigned_date: '2026-09-07' }),
    ).toBe('s2')
  })
})
