/**
 * session_reminder_format.ts の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/session_reminder_format_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 */

import {
  formatJstDate,
  formatJstDateTime,
  formatSessionReminderBody,
  parseTargetDate,
} from './session_reminder_format.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

Deno.test('formatJstDateTime: UTC 日付と JST 日付が異なる時刻を JST で整形する', () => {
  // UTC 09-12 15:30 = JST 09-13 00:30（UTC 日付で判定すると前日 9/12 になる）
  assertEq(formatJstDateTime('2026-09-12T15:30:00Z'), '9月13日(日) 00:30', 'UTC 15:30 → JST 翌日 00:30')
  // PostgREST が返す timestamptz の書式（+00:00 オフセット付き）でも同じ
  assertEq(formatJstDateTime('2026-09-12T15:30:00+00:00'), '9月13日(日) 00:30', '+00:00 表記')
  // JST オフセット付きの入力でも同じ時刻を指す
  assertEq(formatJstDateTime('2026-09-13T00:30:00+09:00'), '9月13日(日) 00:30', '+09:00 表記')
  // UTC 09-12 14:59:59 = JST 09-12 23:59（境界の直前は同日）
  assertEq(formatJstDateTime('2026-09-12T14:59:59Z'), '9月12日(土) 23:59', 'UTC 14:59:59 → JST 同日 23:59')
  // Date インスタンスでも同じ
  assertEq(formatJstDateTime(new Date('2026-09-13T09:00:00Z')), '9月13日(日) 18:00', 'Date 入力: UTC 09:00 → JST 18:00')
})

Deno.test('formatJstDateTime: 曜日は日本語1文字（日月火水木金土）', () => {
  // 2026-09-13（日）から7日連続。JST 10:00 = UTC 01:00
  const expected = ['日', '月', '火', '水', '木', '金', '土']
  for (let i = 0; i < 7; i++) {
    const day = 13 + i
    const actual = formatJstDateTime(`2026-09-${day}T01:00:00Z`)
    assertEq(actual, `9月${day}日(${expected[i]}) 10:00`, `9/${day}`)
  }
})

Deno.test('formatJstDateTime: 月跨ぎ・年跨ぎも JST の暦で表記する', () => {
  // UTC 09-30 15:00 = JST 10-01 00:00
  assertEq(formatJstDateTime('2026-09-30T15:00:00Z'), '10月1日(木) 00:00', '月跨ぎ（9月→10月）')
  // UTC 12-31 15:00 = JST 翌年 01-01 00:00
  assertEq(formatJstDateTime('2026-12-31T15:00:00Z'), '1月1日(金) 00:00', '年跨ぎ（12月→1月）')
  // 月日はゼロ埋めなし・時刻はゼロ埋めあり
  assertEq(formatJstDateTime('2026-01-05T00:05:00Z'), '1月5日(月) 09:05', '1桁の月日はゼロ埋めなし、時刻は HH:mm')
})

Deno.test('formatJstDate: JST の暦日を YYYY-MM-DD で返す', () => {
  assertEq(formatJstDate('2026-09-12T15:00:00Z'), '2026-09-13', 'UTC 15:00 → JST 翌日')
  assertEq(formatJstDate('2026-09-12T14:59:59Z'), '2026-09-12', 'UTC 14:59:59 → JST 同日')
  assertEq(formatJstDate('2026-12-31T15:00:00Z'), '2027-01-01', '年跨ぎ')
  assertEq(formatJstDate(new Date('2026-01-04T15:00:00Z')), '2026-01-05', 'Date 入力・ゼロ埋め')
})

Deno.test('formatSessionReminderBody: trainer_name ありの本文', () => {
  assertEq(
    formatSessionReminderBody('2026-09-13T09:00:00Z', '山田'),
    '9月13日(日) 18:00 から 山田 トレーナーとのセッションがあります',
    'trainer_name あり',
  )
  // 前後の空白は取り除く
  assertEq(
    formatSessionReminderBody('2026-09-13T09:00:00Z', '  山田  '),
    '9月13日(日) 18:00 から 山田 トレーナーとのセッションがあります',
    'trainer_name 前後空白',
  )
})

Deno.test('formatSessionReminderBody: trainer_name が NULL / 空なら「トレーナーとのセッション」に落とす', () => {
  const expected = '9月13日(日) 18:00 から トレーナーとのセッションがあります'
  assertEq(formatSessionReminderBody('2026-09-13T09:00:00Z', null), expected, 'null')
  assertEq(formatSessionReminderBody('2026-09-13T09:00:00Z', ''), expected, '空文字')
  assertEq(formatSessionReminderBody('2026-09-13T09:00:00Z', '   '), expected, '空白のみ')
})

Deno.test('formatSessionReminderBody: 解析できない日付は例外（呼び出し元の1件単位 try/catch で捕捉する前提）', () => {
  let thrown = false
  try {
    formatSessionReminderBody('not-a-date', '山田')
  } catch {
    thrown = true
  }
  assertEq(thrown, true, '不正日付で例外')
})

Deno.test('parseTargetDate: YYYY-MM-DD の実在する日付はそのまま返す', () => {
  assertEq(parseTargetDate('2026-09-13'), '2026-09-13', '通常の日付')
  assertEq(parseTargetDate('2026-01-01'), '2026-01-01', '年初')
  assertEq(parseTargetDate('2026-12-31'), '2026-12-31', '年末')
  assertEq(parseTargetDate('2028-02-29'), '2028-02-29', '閏年の 2/29 は実在')
})

Deno.test('parseTargetDate: 書式違いは null（tomorrow / スラッシュ区切り / 時刻付き / ゼロ埋めなし / 前後空白）', () => {
  assertEq(parseTargetDate('tomorrow'), null, 'tomorrow')
  assertEq(parseTargetDate('2026/09/13'), null, 'スラッシュ区切り')
  assertEq(parseTargetDate('2026-09-13 12:34'), null, '時刻付き（空白区切り）')
  assertEq(parseTargetDate('2026-09-13T00:00:00Z'), null, '時刻付き（ISO 8601）')
  assertEq(parseTargetDate('2026-9-13'), null, 'ゼロ埋めなし')
  assertEq(parseTargetDate(' 2026-09-13'), null, '先頭空白')
  assertEq(parseTargetDate('2026-09-13 '), null, '末尾空白')
  assertEq(parseTargetDate(''), null, '空文字')
})

Deno.test('parseTargetDate: 存在しない日付は null（2026-02-30 など）', () => {
  assertEq(parseTargetDate('2026-02-30'), null, '2月30日')
  assertEq(parseTargetDate('2026-02-29'), null, '平年の 2/29')
  assertEq(parseTargetDate('2026-09-31'), null, '9月31日')
  assertEq(parseTargetDate('2026-13-01'), null, '13月')
  assertEq(parseTargetDate('2026-00-10'), null, '0月')
  assertEq(parseTargetDate('2026-09-00'), null, '0日')
})

Deno.test('parseTargetDate: 文字列以外は null', () => {
  assertEq(parseTargetDate(20260913), null, '数値')
  assertEq(parseTargetDate(null), null, 'null')
  assertEq(parseTargetDate(undefined), null, 'undefined')
  assertEq(parseTargetDate({ target_date: '2026-09-13' }), null, 'オブジェクト')
  assertEq(parseTargetDate(['2026-09-13']), null, '配列')
  assertEq(parseTargetDate(new Date('2026-09-13T00:00:00Z')), null, 'Date インスタンス')
  assertEq(parseTargetDate(true), null, 'boolean')
})
