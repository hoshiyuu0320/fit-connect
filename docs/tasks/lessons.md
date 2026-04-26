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

## SleepRecord 設計時の知見（タスク 1.3）

- **recorded_date は DATE 型 + String 表現**: Mobile側でも `String "YYYY-MM-DD"` で扱い、`DateTime` 比較は禁止。`jstDateKey()` ヘルパーで一貫処理
- **UPSERT 戦略**: 手動評価と HealthKit 客観データを混在させる場合、ペイロードに**含めないフィールドを保持する** UPSERT が必要。Supabase の `.upsert(... onConflict: '...')` で実現
- **Supabase Trigger関数名**: 既存トリガは `update_updated_at_column()`（`set_updated_at` ではない）。新規テーブルでも踏襲すること
- **Sleep カラーは AppColorsExtension に追加**: `sleepStageDeep/Light/Rem/Awake` をライト/ダーク両preset対応。`AppColors` 直定数より ThemeExtension パターン優先

## エラー状態のUX原則（タスク 1.3）

- カードの error state は **ヘッダー構造を保持**してカードらしさを残す（テキスト1行のみは視認性が低い）
- **リトライ導線**を必ず提供（該当 provider を `ref.invalidate()`）
- 関連: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart` `_ErrorBody`