# Lessons - 過去の失敗と学び

## 記録ルール

- バグを解決したら、ここにパターンと対策を追記する
- 設計上の判断ミスや整合性の注意点も記録する
- 同じ失敗を繰り返さないための知見をまとめる

## 日付比較のタイムゾーン問題

- **発生箇所**: GoalAchievementChart（目標達成率推移グラフ）
- **症状**: 体重進捗率が実際の記録と連動せず、古い値のまま固定される
- **原因**: `new Date(record.recorded_at)` と date-fns の interval（ローカルタイム）を直接比較すると、JST(UTC+9) のレコードが期間境界で正しく振り分けられない
- **対策**: Supabase の `recorded_at` をフィルタする際は `recorded_at.split('T')[0]` の文字列比較を使う（report/page.tsx と同じパターン）。`new Date()` 同士の比較は避ける