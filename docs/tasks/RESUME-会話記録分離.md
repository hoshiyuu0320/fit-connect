# 【再開用】メッセージ 会話/記録 表示分離機能

> このファイルは別マシン（Mac等）で作業を再開するための引き継ぎメモです。
> Claude に「`docs/tasks/RESUME-会話記録分離.md` を読んで続きから」と伝えれば、ここから再開できます。
> 最終更新: 2026-06-14

---

## 何を作っているか

メッセージ画面で**会話と記録（食事/体重/運動）が混在して使いづらい**問題を、**表示分離**で解決する機能。

**大原則**:
- ① 記録の"送信"は会話と一体（入力欄は1つ＝コンセプト「記録と報告が同時にできる」を死守）
- ② "閲覧"時だけ会話/記録を分離
- ❌ 完全分離は不採用

**UI方針**:
- **Mobile（クライアント）**: 混在ベース＋「すべて/記録」切替トグル。フィルタ状態は enum `all/recordsOnly/chatOnly`（将来3タブ拡張可）
- **Web（トレーナー）**: 会話メイン＋記録サイドパネル（開閉式・デフォルト開）。パネル=サマリー＋種別フィルタ＋記録ログ

**データ基盤（最重要・非自明）**: 記録判定は `messages.tags`（`cardinality(tags)>0`、非空＝記録）に一本化。正準タグ=`#`付き（例 `#食事:昼食`/`#体重`/`#運動:筋トレ`/`#運動:ランニング`/`#運動:完了`）。webhook `parse-message-tags` は「補完役」に降格し、送信側で確実付与。ワークアウト達成（#なし「本日のワークアウトプラン…達成しました！」）は `#運動:完了` ＋ exercise_records に `other` で記録（duration/distance必須制約は `20260101063157` で削除済み）。

---

## ブランチ構成（両方 push 済み）

```
main（本番）
└─ develop/1.0.0（開発）
   └─ feature/message-tags-unification   ← 基盤フェーズ（squash 1コミット）= PR #56（マージ待ち）
      └─ feature/message-record-tabs-ui  ← UIフェーズ（Mobile案A + Web案②）★最新の作業ブランチ
```

> UIブランチは基盤ブランチから派生（UIはtags統一に依存するため）。基盤PR #56がdevelopにマージされた後、UIブランチをdevelopへPRすればUI差分のみ乗る。

---

## 完了済み（コード実装は3つとも完了・テスト/レビュー全通過）

### ① 基盤フェーズ（tags統一）= PR #56
Mobile/Web/Backend横断。記録判定を `tags` に一本化。テスト Web17/Mobile9 pass。
（`feature/message-tags-unification` に squash 済み、コミット `26008e2`）

### ② Mobile案A（会話/記録トグル）
`feature/message-record-tabs-ui` のコミット: `cf00325`→`3893a47`→`a33db2f`→`9c389e2`
- `lib/features/messages/utils/message_filter.dart`（enum + `applyMessageFilter`/`isRecordMessage` 純関数、テスト5pass）
- `lib/features/messages/providers/message_filter_provider.dart`（@riverpod `MessageFilterController`）
- `lib/features/messages/presentation/screens/message_screen.dart`（SegmentedButtonトグル設置・フィルタ適用・記録のみ表示中の通常メッセージ送信で「すべて」自動復帰）

### ③ Web案②（記録サイドパネル）
`feature/message-record-tabs-ui` のコミット: `fcf4127`→`9136ff5`→`7d62c60`→`0115347`→`25bff69`
- `fit-connect/src/components/message/recordLog.ts`（`extractRecordLog`/`filterByType` 純関数、運動フィルタにachievementも含む、テスト5pass）
- `fit-connect/src/components/message/RecordSidePanel.tsx`（ヘッダー＋サマリー[`PfcBalanceCard`/`WeightNutritionChart`]＋種別フィルタchips＋`RecordCard`ログ）
- `fit-connect/src/app/(user_console)/message/page.tsx`（第3カラム統合・開閉state・サマリー取得useEffect）
- `fit-connect/src/components/clients/WeightNutritionChart.tsx`（`targetWeight` を optional 化、既存SummaryTab非破壊）

---

## 残りタスク（＝仕上げフェーズ）

```
1️⃣ 実機QA（まだ未実施）
   - Web案②  → chrome-web-qa（npm run dev + Chrome、Docker不要・軽い）★まず最初におすすめ
   - Mobile案A → ios-simulator-qa（iOSビルド重い。下記fvm注意）
2️⃣ develop/1.0.0 へ反映
   - 基盤 PR #56 をマージ → その後 feature/message-record-tabs-ui を develop へ PR（基盤マージ後はUI差分のみ）
3️⃣ C3 本番反映（⚠️要ユーザー承認）
   - supabase functions deploy parse-message-tags --no-verify-jwt
   - supabase db push
   - 適用前に Docker起動 → supabase db reset でマイグレーション検証 ＋ 本番の移行対象件数を計測（未計測）
```

---

## 関連ドキュメント（このリポジトリ内）
- 設計書: `docs/tasks/2026-06-07-message-record-conversation-tabs-design.md`
- 基盤フェーズ計画: `docs/tasks/2026-06-07-message-tags-unification-plan.md`
- Mobile案A計画: `docs/tasks/2026-06-14-message-record-filter-mobile-plan.md`
- Web案②計画: `docs/tasks/2026-06-14-message-record-sidepanel-web-plan.md`

## 環境メモ
- **Mobile**: Flutter は fvm で 3.41.9 にpin。ただしシェルに `fvm` が無い場合あり → その時は `flutter`（別途インストールのもの）で代替可。`flutter pub get` / `flutter analyze` / `flutter test`。
- **Web**: Next.js 15 + Vitest。`npm install` → `npx vitest run` / `npx tsc --noEmit` / `npm run dev`。
- **Supabase**: CLI操作はルート `FIT-CONNECT/` から。本番反映は要承認。
