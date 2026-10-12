/**
 * 通知設定（notification_preferences）でトレーナーが切り替えられる種別の一覧と、既定値・読み込みのフィルタ。
 * 設計書 docs/superpowers/specs/2026-10-04-trainer-alert-push-design.md §7.2。依存の無い純関数のモジュール
 */

export type NotificationKind = 'message' | 'client_alert' | 'goal_achievement'

export type NotificationKindItem = {
  kind: NotificationKind
  label: string
  description: string
}

/** 設定画面に並べる順（メッセージ受信 → アラート（朝のまとめ） → 目標達成のお知らせ） */
export const NOTIFICATION_KINDS: readonly NotificationKindItem[] = [
  {
    kind: 'message',
    label: 'メッセージ受信',
    description: 'クライアントからメッセージが届いたとき',
  },
  {
    kind: 'client_alert',
    label: 'アラート（朝のまとめ）',
    description: '朝の自動チェックで新しく対応が必要な顧客が見つかった日に1通お知らせします',
  },
  {
    kind: 'goal_achievement',
    label: '目標達成のお知らせ',
    description: 'クライアントが目標を達成したとき',
  },
]

export type NotificationPrefs = Record<NotificationKind, boolean>

/** 行が無い種別は有効（既定はすべてオン） */
export function defaultNotificationPrefs(): NotificationPrefs {
  return { message: true, client_alert: true, goal_achievement: true }
}

export function isNotificationKind(value: unknown): value is NotificationKind {
  return NOTIFICATION_KINDS.some((item) => item.kind === value)
}

/** 読み込んだ行のうち、一覧にある種別の行だけを prev に反映する（未知の種別・enabled が真偽値でない行は無視） */
export function applyPreferenceRows(
  prev: NotificationPrefs,
  rows: readonly { kind: unknown; enabled: unknown }[]
): NotificationPrefs {
  const next = { ...prev }
  for (const row of rows) {
    if (isNotificationKind(row.kind) && typeof row.enabled === 'boolean') {
      next[row.kind] = row.enabled
    }
  }
  return next
}
