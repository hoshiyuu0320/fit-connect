import { describe, it, expect } from 'vitest'
import {
  NOTIFICATION_KINDS,
  applyPreferenceRows,
  defaultNotificationPrefs,
  isNotificationKind,
} from './notificationKinds'

describe('NOTIFICATION_KINDS', () => {
  it('メッセージ受信 → アラート（朝のまとめ） → 目標達成のお知らせ の順', () => {
    expect(NOTIFICATION_KINDS.map((item) => item.kind)).toEqual([
      'message',
      'client_alert',
      'goal_achievement',
    ])
  })

  it('アラート（朝のまとめ）の文言', () => {
    const alert = NOTIFICATION_KINDS.find((item) => item.kind === 'client_alert')
    expect(alert).toEqual({
      kind: 'client_alert',
      label: 'アラート（朝のまとめ）',
      description: '朝の自動チェックで新しく対応が必要な顧客が見つかった日に1通お知らせします',
    })
  })

  it('既存の種別の文言は変えない', () => {
    expect(NOTIFICATION_KINDS[0]).toEqual({
      kind: 'message',
      label: 'メッセージ受信',
      description: 'クライアントからメッセージが届いたとき',
    })
    expect(NOTIFICATION_KINDS[2]).toEqual({
      kind: 'goal_achievement',
      label: '目標達成のお知らせ',
      description: 'クライアントが目標を達成したとき',
    })
  })
})

describe('defaultNotificationPrefs', () => {
  it('すべてオン（一覧の種別ぶん）', () => {
    const prefs = defaultNotificationPrefs()
    expect(prefs).toEqual({ message: true, client_alert: true, goal_achievement: true })
    expect(Object.keys(prefs).sort()).toEqual(NOTIFICATION_KINDS.map((item) => item.kind).sort())
  })

  it('呼ぶたびに別のオブジェクト', () => {
    expect(defaultNotificationPrefs()).not.toBe(defaultNotificationPrefs())
  })
})

describe('isNotificationKind', () => {
  it('一覧の種別だけを受け付ける', () => {
    expect(isNotificationKind('client_alert')).toBe(true)
    expect(isNotificationKind('session_reminder')).toBe(false)
    expect(isNotificationKind('')).toBe(false)
    expect(isNotificationKind(null)).toBe(false)
  })
})

describe('applyPreferenceRows', () => {
  it('一覧にある種別の行を反映する', () => {
    const next = applyPreferenceRows(defaultNotificationPrefs(), [
      { kind: 'client_alert', enabled: false },
      { kind: 'message', enabled: false },
    ])
    expect(next).toEqual({ message: false, client_alert: false, goal_achievement: true })
  })

  it('未知の種別（顧客向けの session_reminder など）は無視する', () => {
    const next = applyPreferenceRows(defaultNotificationPrefs(), [
      { kind: 'session_reminder', enabled: false },
      { kind: 'unknown_kind', enabled: false },
      { kind: 'toString', enabled: false },
    ])
    expect(next).toEqual(defaultNotificationPrefs())
    expect(Object.keys(next).sort()).toEqual(['client_alert', 'goal_achievement', 'message'])
  })

  it('enabled が真偽値でない行は無視する', () => {
    const next = applyPreferenceRows(defaultNotificationPrefs(), [{ kind: 'client_alert', enabled: null }])
    expect(next.client_alert).toBe(true)
  })

  it('元のオブジェクトを書き換えない', () => {
    const prev = defaultNotificationPrefs()
    applyPreferenceRows(prev, [{ kind: 'message', enabled: false }])
    expect(prev.message).toBe(true)
  })

  it('行が無ければそのまま', () => {
    expect(applyPreferenceRows(defaultNotificationPrefs(), [])).toEqual(defaultNotificationPrefs())
  })
})
