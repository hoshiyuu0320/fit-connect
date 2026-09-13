import { describe, it, expect } from 'vitest'
import { buildTriageRows, collectTriageClientIds } from '@/lib/triage/buildTriageRows'
import type { ClientAlert } from '@/types/alert'

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

  it('行は最大の重要度 → surfaced_on の新しい順 → 名前の順', () => {
    const alerts = [
      makeAlert({ client_id: 'm-old', client_name: 'えがわ', severity: 'medium', surfaced_on: '2026-09-10' }),
      makeAlert({ client_id: 'h-old', client_name: 'おの', severity: 'high', surfaced_on: '2026-09-11' }),
      makeAlert({ client_id: 'h-new', client_name: 'かとう', severity: 'high', surfaced_on: '2026-09-13' }),
      makeAlert({ client_id: 'm-new-2', client_name: 'いとう', severity: 'medium', surfaced_on: '2026-09-13' }),
      makeAlert({ client_id: 'm-new-1', client_name: 'あべ', severity: 'medium', surfaced_on: '2026-09-13' }),
    ]
    expect(buildTriageRows(alerts).rows.map((r) => r.clientId)).toEqual([
      'h-new',
      'h-old',
      'm-new-1', // 同じ重要度・同じ日は名前順（あべ → いとう）
      'm-new-2',
      'm-old',
    ])
  })

  it('行の surfaced_on は最大の重要度の理由のもの（重要度の低い新しい理由では前に出ない）', () => {
    const alerts = [
      // A: high は 9/10、medium が 9/13
      makeAlert({ client_id: 'a', client_name: 'あべ', severity: 'high', surfaced_on: '2026-09-10', alert_type: 'weight_change', payload: weightPayload }),
      makeAlert({ client_id: 'a', client_name: 'あべ', severity: 'medium', surfaced_on: '2026-09-13' }),
      // B: high が 9/12
      makeAlert({ client_id: 'b', client_name: 'いとう', severity: 'high', surfaced_on: '2026-09-12' }),
    ]
    expect(buildTriageRows(alerts).rows.map((r) => [r.clientId, r.surfacedOn])).toEqual([
      ['b', '2026-09-12'],
      ['a', '2026-09-10'],
    ])
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
    const snapshot = JSON.stringify(alerts)
    buildTriageRows(alerts)
    expect(JSON.stringify(alerts)).toBe(snapshot)
  })
})

describe('collectTriageClientIds', () => {
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
