import { describe, it, expect } from 'vitest'
import { buildTriageRows, collectTriageClientIds } from '@/lib/triage/buildTriageRows'
import type { ClientAlert } from '@/types/alert'
import type { UnrepliedClient } from '@/types/triage'

const weightPayload = {
  v: 1,
  direction: 'increase',
  recent: { from: '2026-09-06', to: '2026-09-12', avg_kg: 72.9, days: 5 },
  previous: { from: '2026-08-30', to: '2026-09-05', avg_kg: 70.5, days: 4 },
  delta_kg: 2.4,
  delta_pct: 3.4,
  threshold: { pct: 3, kg: 2 },
}

const gapPayload = {
  v: 1,
  variant: 'no_data',
  gap_from: '2026-09-09',
  gap_to: '2026-09-12',
  last_activity_on: '2026-09-08',
  last_record_on: '2026-09-08',
  threshold_days: 3,
}

let seq = 0
function makeAlert(overrides: Partial<ClientAlert> = {}): ClientAlert {
  seq += 1
  return {
    id: `alert-${String(seq).padStart(3, '0')}`,
    client_id: 'client-a',
    alert_type: 'record_gap',
    severity: 'medium',
    status: 'open',
    payload: gapPayload,
    first_detected_on: '2026-09-12',
    surfaced_on: '2026-09-12',
    last_detected_on: '2026-09-13',
    acknowledged_at: null,
    reopened_count: 0,
    client_name: 'あべ',
    client_profile_image_url: null,
    ...overrides,
  }
}

function makeUnreplied(overrides: Partial<UnrepliedClient> = {}): UnrepliedClient {
  return {
    client_id: 'client-u',
    client_name: 'うえだ',
    profile_image_url: 'client-u/avatar.png',
    unreplied_since: '2026-09-12T15:00:00Z',
    latest_unreplied_at: '2026-09-13T01:00:00Z',
    unreplied_count: 2,
    ...overrides,
  }
}

/** 表示時点（9/13 18:00 JST） */
const NOW = new Date('2026-09-13T09:00:00Z')

describe('buildTriageRows', () => {
  it('空なら行もバッジも空', () => {
    const result = buildTriageRows([])
    expect(result.rows).toEqual([])
    expect(result.badgeClientIds.size).toBe(0)
  })

  it('同じ顧客の複数のアラートは1行にまとめ、理由は重要度 → 新しい順に並べる', () => {
    const gap = makeAlert({ id: 'gap', severity: 'medium', surfaced_on: '2026-09-13' })
    const weight = makeAlert({
      id: 'weight',
      alert_type: 'weight_change',
      severity: 'high',
      payload: weightPayload,
      surfaced_on: '2026-09-10',
      first_detected_on: '2026-09-10',
    })
    const { rows, badgeClientIds } = buildTriageRows([gap, weight])

    expect(rows).toHaveLength(1)
    const [row] = rows
    expect(row.clientId).toBe('client-a')
    expect(row.clientName).toBe('あべ')
    expect(row.reasons.map((r) => r.alertId)).toEqual(['weight', 'gap'])
    // 行の重要度・surfaced_on・主ボタンのタブは先頭の理由から
    expect(row.severity).toBe('high')
    expect(row.surfacedOn).toBe('2026-09-10')
    expect(row.recordTab).toBe('weight')
    expect(row.reasons[0].description.chip).toBe('体重 +2.4kg')
    expect(row.reasons[0].firstDetectedOn).toBe('2026-09-10')
    expect(row.reasons[1].description.chip).toBe('記録・同期なし 4日')
    expect([...badgeClientIds]).toEqual(['client-a'])
  })

  // PR2 で並び順を「最大の重要度 → surfaced_on の新しい順 → 名前」から優先度スコア順に変えた
  // （計画書 Web UI > PR2・契約 > スコア triageScore）。surfaced_on は並び順に使わない
  it('行はスコアの高い順 → 同点は最初の検知日が古い順 → 名前の順', () => {
    // どれも4日の途絶（+20）。high は 50 点、medium は 30 点
    const alerts = [
      makeAlert({ client_id: 'm-1', client_name: 'あべ', severity: 'medium', first_detected_on: '2026-09-12' }),
      makeAlert({ client_id: 'h-new', client_name: 'かとう', severity: 'high', first_detected_on: '2026-09-13', surfaced_on: '2026-09-13' }),
      makeAlert({ client_id: 'm-2', client_name: 'いとう', severity: 'medium', first_detected_on: '2026-09-12' }),
      makeAlert({ client_id: 'h-old', client_name: 'おの', severity: 'high', first_detected_on: '2026-09-11', surfaced_on: '2026-09-11' }),
      makeAlert({ client_id: 'm-old', client_name: 'えがわ', severity: 'medium', first_detected_on: '2026-09-10', surfaced_on: '2026-09-13' }),
    ]
    const { rows } = buildTriageRows(alerts)
    expect(rows.map((r) => [r.clientId, r.score])).toEqual([
      ['h-old', 50], // 同点の high は最初の検知日が古い方（surfaced_on が新しい h-new より前）
      ['h-new', 50],
      ['m-old', 30],
      ['m-1', 30], // 同じ点・同じ検知日は名前順（あべ → いとう）
      ['m-2', 30],
    ])
  })

  it('理由の多い顧客は点が足し上がり、長い途絶の medium は短い high より前に出ることがある', () => {
    const alerts = [
      // A: high の体重（30）+ medium の4日の途絶（30）= 60
      makeAlert({ client_id: 'a', client_name: 'あべ', severity: 'high', surfaced_on: '2026-09-10', alert_type: 'weight_change', payload: weightPayload }),
      makeAlert({ client_id: 'a', client_name: 'あべ', severity: 'medium', surfaced_on: '2026-09-13' }),
      // B: high の4日の途絶 = 50
      makeAlert({ client_id: 'b', client_name: 'いとう', severity: 'high', surfaced_on: '2026-09-12' }),
      // C: medium の20日の途絶 = 10 + 14日 × 5 = 80
      makeAlert({
        client_id: 'c',
        client_name: 'うえの',
        severity: 'medium',
        payload: { ...gapPayload, gap_from: '2026-08-24', gap_to: '2026-09-12' },
      }),
    ]
    const { rows } = buildTriageRows(alerts)
    expect(rows.map((r) => [r.clientId, r.score])).toEqual([
      ['c', 80],
      ['a', 60],
      ['b', 50],
    ])
    // 行の重要度・surfaced_on は先頭の理由（最大の重要度）のもの
    expect(rows[1].severity).toBe('high')
    expect(rows[1].surfacedOn).toBe('2026-09-10')
    expect(rows[1].firstDetectedOn).toBe('2026-09-12')
  })

  it('同じ名前・同じ条件なら顧客 ID で安定させる', () => {
    const alerts = [
      makeAlert({ client_id: 'c-2', client_name: 'たなか' }),
      makeAlert({ client_id: 'c-1', client_name: 'たなか' }),
    ]
    expect(buildTriageRows(alerts).rows.map((r) => r.clientId)).toEqual(['c-1', 'c-2'])
    expect(buildTriageRows([...alerts].reverse()).rows.map((r) => r.clientId)).toEqual([
      'c-1',
      'c-2',
    ])
  })

  it('open 以外は行にもバッジにも入れない', () => {
    const alerts = [
      makeAlert({ client_id: 'open', status: 'open' }),
      makeAlert({ client_id: 'ack', status: 'acknowledged' }),
      makeAlert({ client_id: 'done', status: 'resolved' }),
    ]
    const { rows, badgeClientIds } = buildTriageRows(alerts)
    expect(rows.map((r) => r.clientId)).toEqual(['open'])
    expect([...badgeClientIds]).toEqual(['open'])
  })

  it('記録途絶だけの顧客の主ボタンはサマリータブ', () => {
    const { rows } = buildTriageRows([makeAlert()])
    expect(rows[0].recordTab).toBe('summary')
  })

  it('未知の種別・重要度・壊れた payload でも落ちない（重要度は medium 扱い）', () => {
    const alerts = [
      makeAlert({
        client_id: 'x',
        client_name: 'えがわ',
        alert_type: 'sleep_drop' as ClientAlert['alert_type'],
        severity: 'critical' as ClientAlert['severity'],
        payload: null,
      }),
      makeAlert({ client_id: 'y', client_name: 'あべ', severity: 'high' }),
    ]
    const { rows } = buildTriageRows(alerts)
    expect(rows.map((r) => r.clientId)).toEqual(['y', 'x'])
    expect(rows[1].severity).toBe('medium')
    expect(rows[1].reasons[0].description.recognized).toBe(false)
  })

  it('入力の配列を書き換えない', () => {
    const alerts = [
      makeAlert({ client_id: 'b', client_name: 'いとう' }),
      makeAlert({ client_id: 'a', client_name: 'あべ' }),
    ]
    const unreplied = [makeUnreplied({ client_id: 'c' }), makeUnreplied({ client_id: 'a' })]
    const snapshot = JSON.stringify([alerts, unreplied])
    buildTriageRows(alerts, { unreplied, now: NOW })
    expect(JSON.stringify([alerts, unreplied])).toBe(snapshot)
  })

  it('未返信を渡さなければ、どの行も unreplied は null', () => {
    const { rows } = buildTriageRows([makeAlert()])
    expect(rows[0].unreplied).toBeNull()
  })
})

describe('buildTriageRows（未返信の合流）', () => {
  it('未返信だけの顧客も1行にする（理由は空・重要度は null・名前とアバターは RPC の値）', () => {
    const { rows, badgeClientIds } = buildTriageRows([], {
      unreplied: [makeUnreplied()],
      now: NOW,
    })
    expect(rows).toEqual([
      {
        clientId: 'client-u',
        clientName: 'うえだ',
        profileImageUrl: 'client-u/avatar.png',
        severity: null,
        surfacedOn: null,
        firstDetectedOn: null,
        reasons: [],
        unreplied: {
          since: '2026-09-12T15:00:00Z',
          latestAt: '2026-09-13T01:00:00Z',
          count: 2,
          elapsedHours: 18, // 表示時点 NOW から数える
        },
        recordTab: 'summary',
        score: 36,
      },
    ])
    expect([...badgeClientIds]).toEqual(['client-u'])
  })

  it('アラートのある顧客の未返信は同じ行にまとめ、点を足す', () => {
    const { rows } = buildTriageRows(
      [makeAlert({ client_id: 'client-a', client_name: 'あべ', client_profile_image_url: 'a.png' })],
      {
        unreplied: [
          makeUnreplied({ client_id: 'client-a', client_name: 'あべ（RPC）', profile_image_url: 'rpc.png' }),
        ],
        now: NOW,
      }
    )
    expect(rows).toHaveLength(1)
    const [row] = rows
    expect(row.clientName).toBe('あべ') // アラートの埋め込みの値を優先
    expect(row.profileImageUrl).toBe('a.png')
    expect(row.reasons).toHaveLength(1)
    expect(row.severity).toBe('medium')
    expect(row.unreplied?.count).toBe(2)
    expect(row.score).toBe(30 + 36) // medium の4日の途絶 + 未返信18時間
  })

  it('未返信とアラートをスコア順に混ぜて並べる', () => {
    const { rows } = buildTriageRows(
      [
        makeAlert({ client_id: 'high-gap', client_name: 'かとう', severity: 'high' }), // 50
        makeAlert({ client_id: 'medium-gap', client_name: 'きむら', severity: 'medium' }), // 30
      ],
      {
        unreplied: [
          makeUnreplied({ client_id: 'waiting-30h', client_name: 'あべ', unreplied_since: '2026-09-12T03:00:00Z' }), // 60
          makeUnreplied({ client_id: 'waiting-10h', client_name: 'いとう', unreplied_since: '2026-09-12T23:00:00Z' }), // 20
          makeUnreplied({ client_id: 'waiting-4d', client_name: 'うえの', unreplied_since: '2026-09-09T09:00:00Z' }), // 72時間で頭打ち → 144
        ],
        now: NOW,
      }
    )
    expect(rows.map((r) => [r.clientId, r.score])).toEqual([
      ['waiting-4d', 144],
      ['waiting-30h', 60],
      ['high-gap', 50],
      ['medium-gap', 30],
      ['waiting-10h', 20],
    ])
  })

  it('同点なら未返信が古い行を先に出す（未返信の無い行は後ろ）', () => {
    const { rows } = buildTriageRows(
      // medium の4日の途絶 = 30 点、最初の検知日は一番古い
      [makeAlert({ client_id: 'alert-only', client_name: 'あべ', first_detected_on: '2026-09-01' })],
      {
        unreplied: [
          // 15時間 = 30 点
          makeUnreplied({ client_id: 'newer', client_name: 'いとう', unreplied_since: '2026-09-12T18:00:00Z' }),
          // 15時間59分 = 30 点（切り捨て）。こちらの方が古い
          makeUnreplied({ client_id: 'older', client_name: 'うえの', unreplied_since: '2026-09-12T17:01:00Z' }),
        ],
        now: NOW,
      }
    )
    expect(rows.map((r) => [r.clientId, r.score])).toEqual([
      ['older', 30],
      ['newer', 30],
      ['alert-only', 30],
    ])
  })

  it('対応済みのアラートしか無い顧客も、未返信があれば未返信だけの行として残る', () => {
    const { rows, badgeClientIds } = buildTriageRows(
      [makeAlert({ client_id: 'client-a', status: 'acknowledged', severity: 'high' })],
      { unreplied: [makeUnreplied({ client_id: 'client-a' })], now: NOW }
    )
    expect(rows).toHaveLength(1)
    expect(rows[0].reasons).toEqual([])
    expect(rows[0].severity).toBeNull()
    expect(rows[0].score).toBe(36) // 対応済みの high は点に入れない
    expect([...badgeClientIds]).toEqual(['client-a'])
  })

  it('バッジ用の顧客 ID は open のアラートと未返信の和集合', () => {
    const { rows, badgeClientIds } = buildTriageRows(
      [
        makeAlert({ client_id: 'a' }),
        makeAlert({ client_id: 'b' }),
        makeAlert({ client_id: 'ack', status: 'acknowledged' }),
      ],
      { unreplied: [makeUnreplied({ client_id: 'b' }), makeUnreplied({ client_id: 'c' })], now: NOW }
    )
    expect([...badgeClientIds].sort()).toEqual(['a', 'b', 'c'])
    // 見出しの件数（行の数）とバッジの数は同じ定義
    expect(rows).toHaveLength(badgeClientIds.size)
  })

  it('同じ顧客の未返信が2件来たら最初のものを使う', () => {
    const { rows } = buildTriageRows([], {
      unreplied: [
        makeUnreplied({ unreplied_count: 1 }),
        makeUnreplied({ unreplied_count: 5, unreplied_since: '2026-09-01T00:00:00Z' }),
      ],
      now: NOW,
    })
    expect(rows).toHaveLength(1)
    expect(rows[0].unreplied?.count).toBe(1)
    expect(rows[0].score).toBe(36)
  })
})

describe('collectTriageClientIds', () => {
  it('アラートと未返信で同じ顧客は1人として数える', () => {
    const ids = collectTriageClientIds(
      [{ client_id: 'a' }, { client_id: 'b' }],
      [{ client_id: 'b' }, { client_id: 'c' }, { client_id: 'c' }]
    )
    expect([...ids].sort()).toEqual(['a', 'b', 'c'])
  })

  it('同じ顧客は1回だけ数える', () => {
    const ids = collectTriageClientIds([
      { client_id: 'a' },
      { client_id: 'b' },
      { client_id: 'a' },
    ])
    expect(ids.size).toBe(2)
    expect(ids.has('a')).toBe(true)
    expect(ids.has('b')).toBe(true)
  })
})
