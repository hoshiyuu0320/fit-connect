/**
 * quiet_hours.ts の単体テスト
 *
 * 実行: npx -y deno test supabase/functions/_shared/quiet_hours_test.ts
 * （外部依存ゼロ。ネットワーク不要で実行可能）
 */

import { isWithinQuietHours, jstSecondsOfDay, parseTimeToSeconds } from './quiet_hours.ts'

function assertEq<T>(actual: T, expected: T, label: string): void {
  if (actual !== expected) {
    throw new Error(`${label}: expected ${String(expected)}, got ${String(actual)}`)
  }
}

const sec = (h: number, m = 0, s = 0) => h * 3600 + m * 60 + s

Deno.test('parseTimeToSeconds: HH:MM:SS / HH:MM を解析できる', () => {
  assertEq(parseTimeToSeconds('22:00:00'), sec(22), '22:00:00')
  assertEq(parseTimeToSeconds('07:30:15'), sec(7, 30, 15), '07:30:15')
  assertEq(parseTimeToSeconds('9:05'), sec(9, 5), '9:05 (秒省略)')
  assertEq(parseTimeToSeconds('00:00:00'), 0, '00:00:00')
  assertEq(parseTimeToSeconds('23:59:59'), sec(23, 59, 59), '23:59:59')
})

Deno.test('parseTimeToSeconds: 不正値は null', () => {
  assertEq(parseTimeToSeconds(''), null, '空文字')
  assertEq(parseTimeToSeconds('abc'), null, '非時刻文字列')
  assertEq(parseTimeToSeconds('25:00:00'), null, '25時')
  assertEq(parseTimeToSeconds('12:60:00'), null, '60分')
  assertEq(parseTimeToSeconds('12:00:60'), null, '60秒')
})

Deno.test('isWithinQuietHours: 通常レンジ（start < end）は [start, end) 半開区間', () => {
  const start = '22:00:00'
  const end = '23:00:00'
  assertEq(isWithinQuietHours(start, end, sec(22, 30)), true, '22:30 は範囲内')
  assertEq(isWithinQuietHours(start, end, sec(22)), true, '22:00 ちょうど（start含む）')
  assertEq(isWithinQuietHours(start, end, sec(22, 59, 59)), true, '22:59:59 は範囲内')
  assertEq(isWithinQuietHours(start, end, sec(23)), false, '23:00 ちょうど（end含まず）')
  assertEq(isWithinQuietHours(start, end, sec(21, 59, 59)), false, '21:59:59 は範囲外')
  assertEq(isWithinQuietHours(start, end, sec(3)), false, '03:00 は範囲外')
})

Deno.test('isWithinQuietHours: 跨日レンジ（start > end）は start〜24:00 + 00:00〜end', () => {
  const start = '22:00:00'
  const end = '07:00:00'
  assertEq(isWithinQuietHours(start, end, sec(23)), true, '23:00 は範囲内（前半）')
  assertEq(isWithinQuietHours(start, end, sec(22)), true, '22:00 ちょうど（start含む）')
  assertEq(isWithinQuietHours(start, end, sec(23, 59, 59)), true, '23:59:59 は範囲内')
  assertEq(isWithinQuietHours(start, end, 0), true, '00:00 は範囲内（後半）')
  assertEq(isWithinQuietHours(start, end, sec(3)), true, '03:00 は範囲内（後半）')
  assertEq(isWithinQuietHours(start, end, sec(6, 59, 59)), true, '06:59:59 は範囲内')
  assertEq(isWithinQuietHours(start, end, sec(7)), false, '07:00 ちょうど（end含まず）')
  assertEq(isWithinQuietHours(start, end, sec(12)), false, '12:00 は範囲外')
  assertEq(isWithinQuietHours(start, end, sec(21, 59, 59)), false, '21:59:59 は範囲外')
})

Deno.test('isWithinQuietHours: start === end は空区間として常に false', () => {
  assertEq(isWithinQuietHours('09:00:00', '09:00:00', sec(9)), false, '09:00')
  assertEq(isWithinQuietHours('09:00:00', '09:00:00', sec(12)), false, '12:00')
})

Deno.test('isWithinQuietHours: 解析不能な時刻は false（通知を落とさない安全側）', () => {
  assertEq(isWithinQuietHours('invalid', '07:00:00', sec(3)), false, 'start不正')
  assertEq(isWithinQuietHours('22:00:00', 'invalid', sec(23)), false, 'end不正')
})

Deno.test('jstSecondsOfDay: UTC → JST(+9h) 変換', () => {
  assertEq(jstSecondsOfDay(new Date('2026-07-19T00:00:00Z')), sec(9), 'UTC 00:00 → JST 09:00')
  assertEq(jstSecondsOfDay(new Date('2026-07-19T15:00:00Z')), 0, 'UTC 15:00 → JST 00:00（日跨ぎ）')
  assertEq(jstSecondsOfDay(new Date('2026-07-18T20:30:00Z')), sec(5, 30), 'UTC 20:30 → JST 05:30')
  assertEq(jstSecondsOfDay(new Date('2026-07-19T14:59:59Z')), sec(23, 59, 59), 'UTC 14:59:59 → JST 23:59:59')
})
