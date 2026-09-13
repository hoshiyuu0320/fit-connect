import { describe, it, expect, afterEach } from 'vitest'
import {
  describeAlert,
  formatJstMonthDay,
  countDaysInclusive,
  normalizeSeverity,
  severityLabel,
  severityRank,
  clientRecordHref,
  clientMessageHref,
} from '@/lib/alerts/describeAlert'
import type {
  WeightChangePayload,
  RecordGapNotStartedPayload,
  RecordGapNoDataPayload,
  RecordGapNoRecordPayload,
} from '@/types/alert'

// 計画書「Web UI > 文言」の例に合わせた payload（対象日 D = 2026-09-13）
const weightIncrease: WeightChangePayload = {
  v: 1,
  direction: 'increase',
  recent: { from: '2026-09-06', to: '2026-09-12', avg_kg: 72.9, days: 5 },
  previous: { from: '2026-08-30', to: '2026-09-05', avg_kg: 70.5, days: 4 },
  delta_kg: 2.4,
  delta_pct: 3.4,
  threshold: { pct: 3, kg: 2 },
}

const notStarted: RecordGapNotStartedPayload = {
  v: 1,
  variant: 'not_started',
  gap_from: '2026-09-08', // 登録日 J
  gap_to: '2026-09-12', // D − 1
  last_activity_on: '2026-09-08',
  last_record_on: null,
  threshold_days: 3,
}

const noData: RecordGapNoDataPayload = {
  v: 1,
  variant: 'no_data',
  gap_from: '2026-09-09', // R + 1
  gap_to: '2026-09-12',
  last_activity_on: '2026-09-08',
  last_record_on: '2026-09-08',
  threshold_days: 3,
}

const noRecord: RecordGapNoRecordPayload = {
  v: 1,
  variant: 'no_record',
  gap_from: '2026-09-09', // L + 1
  gap_to: '2026-09-12', // min(R, D) − 1
  last_activity_on: '2026-09-13',
  last_record_on: '2026-09-08',
  threshold_days: 3,
}

describe('describeAlert: weight_change', () => {
  it('増加: チップ・見出し・詳細（窓の日数と比較期間）・要確認・体重タブ', () => {
    const d = describeAlert({ alert_type: 'weight_change', severity: 'high', payload: weightIncrease })
    expect(d).toEqual({
      kindLabel: '体重の変化',
      chip: '体重 +2.4kg',
      title: '体重の急な変化',
      detail: '7日平均 +2.4kg（+3.4%）。9/6〜9/12 と 8/30〜9/5 の比較',
      severity: 'high',
      severityLabel: '要確認',
      tab: 'weight',
      gapDays: null,
      recognized: true,
    })
  })

  it('減少（diet で medium）: 符号は -、ラベルは「注意」', () => {
    const d = describeAlert({
      alert_type: 'weight_change',
      severity: 'medium',
      payload: {
        ...weightIncrease,
        direction: 'decrease',
        delta_kg: -2.1,
        delta_pct: -3.0,
        severity_reason: 'diet_decrease',
      },
    })
    expect(d.chip).toBe('体重 -2.1kg')
    expect(d.detail).toBe('7日平均 -2.1kg（-3.0%）。9/6〜9/12 と 8/30〜9/5 の比較')
    expect(d.severityLabel).toBe('注意')
  })

  it('数値は小数1桁に丸める（2.04 → 2.0、3.456 → 3.5）', () => {
    const d = describeAlert({
      alert_type: 'weight_change',
      severity: 'high',
      payload: { ...weightIncrease, delta_kg: 2.04, delta_pct: 3.456 },
    })
    expect(d.chip).toBe('体重 +2.0kg')
    expect(d.detail).toContain('+2.0kg（+3.5%）')
  })

  it('符号は direction ではなく delta_kg から決める', () => {
    const d = describeAlert({
      alert_type: 'weight_change',
      severity: 'high',
      payload: { ...weightIncrease, direction: 'decrease' },
    })
    expect(d.chip).toBe('体重 +2.4kg')
  })

  it('月・年をまたぐ比較期間', () => {
    const d = describeAlert({
      alert_type: 'weight_change',
      severity: 'high',
      payload: {
        ...weightIncrease,
        recent: { from: '2026-12-28', to: '2027-01-03', avg_kg: 70, days: 7 },
        previous: { from: '2026-12-21', to: '2026-12-27', avg_kg: 68, days: 7 },
      },
    })
    expect(d.detail).toBe('7日平均 +2.4kg（+3.4%）。12/28〜1/3 と 12/21〜12/27 の比較')
  })

  it('payload の欠け・未知の v・壊れた値でも落ちず、体重の汎用文言になる', () => {
    const broken: unknown[] = [
      null,
      undefined,
      'weight',
      [],
      {},
      { ...weightIncrease, v: 2 },
      { ...weightIncrease, v: undefined },
      { ...weightIncrease, recent: undefined },
      { ...weightIncrease, previous: { from: '2026-08-30' } },
      { ...weightIncrease, delta_kg: null },
      { ...weightIncrease, delta_pct: Number.NaN },
      { ...weightIncrease, recent: { ...weightIncrease.recent, from: '2026-02-30' } },
      { ...weightIncrease, recent: { ...weightIncrease.recent, from: '2026-09-13' } }, // from > to
    ]
    for (const payload of broken) {
      const d = describeAlert({ alert_type: 'weight_change', severity: 'high', payload })
      expect(d.recognized).toBe(false)
      expect(d.title).toBe('体重の急な変化')
      expect(d.chip).toBe('体重の変化')
      expect(d.kindLabel).toBe('体重の変化')
      expect(d.tab).toBe('weight')
      expect(d.severityLabel).toBe('要確認')
    }
  })
})

describe('describeAlert: record_gap', () => {
  it('not_started: 「登録から N日・記録なし」（N = gap_to − gap_from + 1 = D − J）', () => {
    const d = describeAlert({ alert_type: 'record_gap', severity: 'medium', payload: notStarted })
    expect(d).toEqual({
      kindLabel: '記録開始前',
      chip: '登録から5日・記録なし',
      title: '記録開始前',
      detail: '9/8 に登録してから、記録もメッセージもありません',
      severity: 'medium',
      severityLabel: '注意',
      tab: 'summary',
      gapDays: 5,
      recognized: true,
    })
  })

  it('no_data: 「記録・同期なし N日」。「アプリを開いていない」とは書かない', () => {
    const d = describeAlert({ alert_type: 'record_gap', severity: 'medium', payload: noData })
    expect(d.chip).toBe('記録・同期なし 4日')
    expect(d.title).toBe('記録・同期なし 4日')
    expect(d.kindLabel).toBe('記録・同期なし')
    expect(d.detail).toBe(
      '9/9 以降、記録も同期も届いていません（計測していても、アプリを開くまで届かないことがあります）'
    )
    expect(d.detail).not.toContain('アプリを開いていない')
    expect(d.gapDays).toBe(4)
    expect(d.tab).toBe('summary')
  })

  it('no_record: 最後の記録日と、データが届いた日（日付だけ）を出す', () => {
    const d = describeAlert({ alert_type: 'record_gap', severity: 'medium', payload: noRecord })
    expect(d.chip).toBe('記録なし 4日')
    expect(d.title).toBe('記録なし 4日')
    expect(d.kindLabel).toBe('記録なし')
    expect(d.detail).toBe('最後の記録は 9/8 です（9/13 まではアプリからのデータが届いています）')
    // 到着は日付だけで時刻を持たない（オーナー決定 (2)）
    expect(d.detail).not.toMatch(/\d{1,2}:\d{2}/)
    expect(d.gapDays).toBe(4)
  })

  it('no_record: 最後の記録日・到着日が欠けていても落ちない', () => {
    const noLast = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: { ...noRecord, last_record_on: null },
    })
    expect(noLast.detail).toBe('9/9 以降、記録がありません（9/13 まではアプリからのデータが届いています）')

    const noArrival = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: { ...noRecord, last_activity_on: undefined },
    })
    expect(noArrival.detail).toBe('最後の記録は 9/8 です')
  })

  it('no_record: 最後の記録が登録日より前なら、登録日から数えた言い方にする（日数と食い違わせない）', () => {
    // J = 9/9、L = 8/20（登録前の初回連携分）、R = 9/12、D = 9/13 → 途絶は登録日から 9/9〜9/11 の3日
    const d = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: {
        ...noRecord,
        gap_from: '2026-09-09',
        gap_to: '2026-09-11',
        last_record_on: '2026-08-20',
        last_activity_on: '2026-09-12',
      },
    })
    expect(d.chip).toBe('記録なし 3日')
    expect(d.detail).toBe('9/9 に登録してから記録がありません（9/12 まではアプリからのデータが届いています）')
    expect(d.detail).not.toContain('8/20')
  })

  it('no_record: 最後の記録が登録日の前日なら、最後の記録日をそのまま出す（gap_from = 最後の記録の翌日）', () => {
    // J = 9/9、L = 9/8 → gap_from = max(L, J − 1) + 1 = 9/9
    const d = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: { ...noRecord, gap_from: '2026-09-09', last_record_on: '2026-09-08' },
    })
    expect(d.detail).toBe('最後の記録は 9/8 です（9/13 まではアプリからのデータが届いています）')
  })

  it('7日以上は high（要確認）。日数は payload から出し、今日の日付に依らない', () => {
    const d = describeAlert({
      alert_type: 'record_gap',
      severity: 'high',
      payload: { ...noData, gap_from: '2026-09-01', gap_to: '2026-09-07' },
    })
    expect(d.chip).toBe('記録・同期なし 7日')
    expect(d.severityLabel).toBe('要確認')
    expect(d.gapDays).toBe(7)
  })

  it('月・年をまたぐ途絶の日数（12/30〜1/2 = 4日）', () => {
    const d = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: { ...noData, gap_from: '2026-12-30', gap_to: '2027-01-02' },
    })
    expect(d.chip).toBe('記録・同期なし 4日')
    expect(d.detail.startsWith('12/30 以降')).toBe(true)
  })

  it('未知の変種は汎用の文言（日数の定義は共通なので日数は出す）', () => {
    const d = describeAlert({
      alert_type: 'record_gap',
      severity: 'medium',
      payload: { ...noData, variant: 'no_heartbeat' },
    })
    expect(d.recognized).toBe(false)
    expect(d.chip).toBe('記録の途切れ 4日')
    expect(d.gapDays).toBe(4)
    expect(d.tab).toBe('summary')
  })

  it('payload の欠け・未知の v・日付の逆転でも落ちず、途絶の汎用文言になる', () => {
    const broken: unknown[] = [
      null,
      42,
      { ...noData, v: 2 },
      { ...noData, gap_from: undefined },
      { ...noData, gap_to: 'yesterday' },
      { ...noData, gap_from: '2026-09-13', gap_to: '2026-09-12' },
      { ...noData, gap_from: '2026-13-01' },
    ]
    for (const payload of broken) {
      const d = describeAlert({ alert_type: 'record_gap', severity: 'medium', payload })
      expect(d.recognized).toBe(false)
      expect(d.chip).toBe('記録の途切れ')
      expect(d.gapDays).toBeNull()
      expect(d.tab).toBe('summary')
    }
  })
})

describe('describeAlert: 未知の種別・重要度', () => {
  it('未知の alert_type は汎用の文言で、サマリータブへ', () => {
    const d = describeAlert({ alert_type: 'sleep_drop', severity: 'high', payload: { v: 1 } })
    expect(d).toEqual({
      kindLabel: '自動チェックの検知',
      chip: '自動チェックの検知',
      title: '自動チェックの検知',
      detail: 'この項目の詳しい内容は表示できません。顧客の記録を確認してください。',
      severity: 'high',
      severityLabel: '要確認',
      tab: 'summary',
      gapDays: null,
      recognized: false,
    })
  })

  it('未知の重要度は medium（注意）に丸める', () => {
    const d = describeAlert({ alert_type: 'record_gap', severity: 'critical', payload: noData })
    expect(d.severity).toBe('medium')
    expect(d.severityLabel).toBe('注意')
  })

  it('重要度のラベルと並び順', () => {
    expect(severityLabel('high')).toBe('要確認')
    expect(severityLabel('medium')).toBe('注意')
    expect(severityLabel('low')).toBe('参考')
    expect(normalizeSeverity(undefined)).toBe('medium')
    expect(severityRank('high')).toBeGreaterThan(severityRank('medium'))
    expect(severityRank('medium')).toBeGreaterThan(severityRank('low'))
    expect(severityRank('unknown')).toBe(severityRank('medium'))
  })
})

describe('日付の表示（JST の暦日）', () => {
  const originalTz = process.env.TZ
  afterEach(() => {
    // undefined を代入すると文字列 'undefined' になるので、元が無ければ消す
    if (originalTz === undefined) delete process.env.TZ
    else process.env.TZ = originalTz
  })

  it("'YYYY-MM-DD' は UTC より西のタイムゾーンでも前日にならない", () => {
    process.env.TZ = 'America/Los_Angeles'
    // 素朴に Date に通すと UTC 0時として解釈され、ロサンゼルスでは 9/7 になる（壊れるケースの確認）
    expect(new Date('2026-09-08').getDate()).toBe(7)
    expect(formatJstMonthDay('2026-09-08')).toBe('9/8')
    expect(countDaysInclusive('2026-09-08', '2026-09-12')).toBe(5)
    expect(describeAlert({ alert_type: 'record_gap', severity: 'medium', payload: notStarted }).detail).toBe(
      '9/8 に登録してから、記録もメッセージもありません'
    )
  })

  it('時刻付きの値は JST の暦日に直す（JST 9/8 0:30 = UTC 9/7 15:30 は 9/8）', () => {
    // 先頭10文字を切り出す（UTC の日付）と 9/7 になる
    expect('2026-09-07T15:30:00.000Z'.slice(0, 10)).toBe('2026-09-07')
    expect(formatJstMonthDay('2026-09-07T15:30:00.000Z')).toBe('9/8')
    expect(formatJstMonthDay('2026-09-07T15:30:00+00:00')).toBe('9/8')
    expect(formatJstMonthDay('2026-09-07T14:59:59Z')).toBe('9/7')
  })

  it('解釈できない値は null（Date の独自解釈に任せない）', () => {
    expect(formatJstMonthDay('9/8')).toBeNull()
    expect(formatJstMonthDay('2026-02-30')).toBeNull()
    expect(formatJstMonthDay('')).toBeNull()
    expect(formatJstMonthDay(null)).toBeNull()
    expect(formatJstMonthDay(20260908)).toBeNull()
  })

  it('countDaysInclusive: 両端を含み、逆転は null', () => {
    expect(countDaysInclusive('2026-09-12', '2026-09-12')).toBe(1)
    expect(countDaysInclusive('2026-02-27', '2026-03-01')).toBe(3)
    expect(countDaysInclusive('2028-02-27', '2028-03-01')).toBe(4) // うるう年
    expect(countDaysInclusive('2026-09-13', '2026-09-12')).toBeNull()
  })
})

describe('リンク先', () => {
  it('記録を見る: /clients/<id>?tab=…', () => {
    expect(clientRecordHref('c-1', 'weight')).toBe('/clients/c-1?tab=weight')
    expect(clientRecordHref('c-1', 'summary')).toBe('/clients/c-1?tab=summary')
  })

  it('メッセージ: /message?clientId=<id>（値はエンコードする）', () => {
    expect(clientMessageHref('c-1')).toBe('/message?clientId=c-1')
    expect(clientMessageHref('a&b')).toBe('/message?clientId=a%26b')
  })
})
