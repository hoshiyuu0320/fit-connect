export const SESSION_TYPE_OPTIONS = [
  { value: 'パーソナルトレーニング', label: 'パーソナルトレーニング' },
  { value: '有酸素トレーニング', label: '有酸素トレーニング' },
  { value: 'ストレッチ', label: 'ストレッチ' },
  { value: 'カウンセリング', label: 'カウンセリング' },
  { value: 'other', label: 'その他' },
] as const;

export type SessionTypeValue = typeof SESSION_TYPE_OPTIONS[number]['value'];
