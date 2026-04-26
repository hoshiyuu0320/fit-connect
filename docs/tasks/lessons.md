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

## モノレポ移行（2026-04-26 完了）

- **背景**: Web (`fit-connect`) と Mobile (`fit-connect-mobile`) を独立リポジトリで運用していたが、同一 Supabase 共有・1セッションで両方を統括したい等の理由でモノレポ化
- **戦略**: `git subtree add --prefix=fit-connect-mobile mobile-origin develop/1.0.0`（フル履歴保持）→ Web側ファイルを `fit-connect/` サブディレクトリへ `git mv` → 親レベル CLAUDE.md/.claude/docs を統合 → main を develop で上書き force push
- **トラップ**:
  - **subtree 取り込み元は default branch を確認**: mobile は `main` ではなく `develop/1.0.0` が事実上の運用ブランチだった（main は古い）。Web も同様で main は Initial commit のみ、develop に122コミット
  - **Vercel の Production Branch と実際のデプロイ元の不一致**: Production Branch は main 設定だが、実際の本番 deploy は Mar 14 の develop スナップショット凍結（main へ push されてなかった）。移行を機にこの歪みを解消
  - **Default branch を別運用ブランチに変更してあると、リポジトリ整理時にそれが削除できない**: GitHub の default branch を main に切り替える操作が必要（develop 削除前）
  - **Supabase の `_remote_schema.sql` は完全スキーマダンプ**: 両プロジェクト両方にあるからといって両方を採用してはいけない（時系列で新しい方を採用、古い方は破棄）
- **意図せず混入したもの** (.gitignore 追加候補): `.superpowers/brainstorm/*/.server.pid` 系、`.claude/skills/*/scripts/__pycache__/*.pyc`
- **移行詳細手順書**: `docs/tasks/2026-04-26-monorepo-migration.md`
- **未完のフォローアップ**: `docs/tasks/2026-04-26-monorepo-migration-followups.md`