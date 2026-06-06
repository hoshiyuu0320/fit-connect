# 設計書：サマリータブの体重×栄養グラフ統合 + PFC構成比カード

- 日付: 2026-06-06
- 対象: fit-connect（Trainer Web App / Next.js 15）
- ブランチ: `feature/summary-pfc-overlay-chart`
- 関連: モバイル `nutrition_trend_chart`（PR #48 / d66dcf0 で導入済み）と思想統一

## 背景・課題

クライアント詳細「サマリー」タブ（[SummaryTab.tsx](../../../fit-connect/src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx)）には、現在 体重系グラフが 2 つ存在する。

- 上部カード「体重推移」: [WeightChart](../../../fit-connect/src/components/clients/WeightChart.tsx)（体重ライン + 目標体重ライン、内部に期間切替）
- 最下部「栄養トレンド」セクション: [NutritionTrendChart](../../../fit-connect/src/components/clients/NutritionTrendChart.tsx)（PFC積み上げ棒 + 体重ライン、外部 `PeriodSelector`）

この 2 つで **体重ラインが重複**し、PFC が離れた最下部にあるため一覧性が低い。また、PFC は「量・推移」は見えるが「構成比（%）」が読み取りにくい。

## ゴール

サマリータブの体重系表示を、重複を排した 2 部構成に再編する。

1. **体重 × PFC オーバーレイグラフ**（量・推移・体重との相関）
2. **PFC 構成比カード**（構成比 % と適正バランス判定）

モバイル版（淡色 PFC・kcal 積み上げ・目標ライン）とデザイン思想を統一する。

## スコープ

### やること
- SummaryTab の上部カードを「統合オーバーレイグラフ」に置換
- SummaryTab の最下部「栄養トレンド」セクションを「PFC 構成比カード」に置換
- 期間セレクタ（週/月/3ヶ月/全期間）を 1 つに共通化（両表示で共有）

### やらないこと（スコープ外）
- clients テーブルへの目標 PFC カラム追加・カスタム編集 UI（→ 段階 B / 別タスク。Web/Mobile 両方に影響するスキーマ変更のため分離）
- 「体重」タブ（別タブ）の `WeightChart` は変更しない
- モバイル側の変更（今回は Web のみ）

## レイアウト変更（SummaryTab）

```
[ 左カラム (col-span-2) ]
  ┌ カード: 体重推移 ─────────────────┐   ← WeightChart を「統合オーバーレイグラフ」に置換
  │ (期間セレクタ 1つをここに集約)        │
  │ 体重ライン + 目標破線 + PFC積み上げ棒   │
  └────────────────────────────┘
  ┌ カード: 最近の活動 ───────────────┐   ← 変更なし
  └────────────────────────────┘

[ 右カラム ] クライアント情報 / 睡眠 / 体重予測 / チケット   ← 変更なし

[ 全幅 ]
  ┌ カード: PFC構成比 ────────────────┐   ← 旧「栄養トレンド」セクションを置換
  │ ドーナツ(構成比% + 中央 平均kcal/日)    │
  │ あすけん風 目安バー (P/F/C)            │
  └────────────────────────────┘
```

- 期間 state は SummaryTab で 1 つに統一（現状の `nutritionPeriod` を流用し、両コンポーネントへ渡す）。
- WeightChart 内部の期間切替は SummaryTab では使わない（共通セレクタに集約）。

## コンポーネント①：体重 × PFC オーバーレイグラフ

既存 `NutritionTrendChart` を拡張、または新規 `WeightNutritionChart` として実装（実装計画で確定）。recharts `ComposedChart`。

### 表示要素
- **主役**: 体重ライン（青 `#3B82F6`・線幅 2.5・淡い青エリア `rgba(59,130,246,0.10)`）＋ 目標体重の緑破線
- **背面**: PFC 積み上げ棒（**kcal 換算**: P×4 / F×9 / C×4、淡色 alpha 0.55）
- **軸**: 左 = kg（主役）、右 = kcal（補助）
- **グリッド**: 既存トークン（`#E2E8F0`, dash 3 3）
- **ツールチップ**: 日付 / 体重 / 摂取 kcal / PFC(g) を表示（既存 `NutritionTooltip` 踏襲）
- 空データ / ローディングは既存 EmptyState / LoadingState を踏襲

### 配色
| 要素 | 色 |
|---|---|
| 体重ライン | `#3B82F6` |
| 目標体重ライン | 緑破線（`#22C55E` 系） |
| タンパク質（棒・kcal積み上げ） | `#6366F1`（alpha 0.55） |
| 脂質（棒） | `#E6B968`（alpha 0.55） |
| 炭水化物（棒） | `#E294AE`（alpha 0.55） |

## コンポーネント②：PFC 構成比カード（新規 `PfcBalanceCard`）

### 構成
- **左**: ドーナツ（P:F:C 構成比）。中央に **期間平均 kcal/日**。
- **右**: あすけん風の目安バー（P / F / C 各 1 行）

### あすけん風バー（確定仕様：案2・色味B）
- 実測 %（エネルギー比）でバーが伸びる（x 軸スケール 0–70%）
- 背面に**淡い適正ゾーン** `#C2E6A8`
- **目標値の縦線**（範囲中央 (lo+hi)/2、線幅 3px `#2F7D33`）＋ 上に **▼マーカー**
- 左に**ステータスチップ**: 不足（`#2563EB`）/ 適正（`#16A34A`）/ 過剰（`#EA580C`）
- バー下に「適正 13–20%」等の数値注記
- バー色: P `#6366F1` / F `#E6B968` / C `#E294AE`

### 構成比・目安の定義
- 構成比は **エネルギー(kcal)比**
- 目安レンジ既定値（厚労省 食事摂取基準 相当）:
  - タンパク質 P: 13–20%
  - 脂質 F: 20–30%
  - 炭水化物 C: 50–65%
- 目安レンジは**コンポーネント props で受け取り、既定値を上記固定**にする（段階 A）。将来クライアント別カスタムは props 差し替えで対応可能な作りにしておく。
- 「目標を編集」ボタンは今回は実装しない（段階 B）。

## データフロー

- 既存 [aggregateDailyNutrition](../../../fit-connect/src/lib/nutrition/aggregate.ts)（`mealRecords`, `weightRecords`, `period` → 日次 `DailyNutritionPoint[]`）を流用。
- オーバーレイグラフ: 日次配列をそのまま使用。PFC を kcal 換算して積み上げ。
- PFC 構成比カード:
  - 期間内の P/F/C グラム合計 → kcal 換算（P×4 / F×9 / C×4）→ 構成比 % を算出。
  - 平均 kcal/日 = 期間内合計 kcal ÷ 「食事記録のある日数」。
  - 記録のある日が 0 の場合は空表示（ドーナツ/バー非表示の EmptyState）。
- 集計ロジックは `src/lib/nutrition/` 配下に純関数として切り出し、単体テスト可能にする（例: `computePfcBalance(points, targets)`）。

## エラー / エッジケース

- 食事記録なし: PFC 構成比カードは EmptyState。
- 体重記録なし: オーバーレイグラフは体重ライン非表示、PFC 棒のみ（既存の空表示踏襲）。
- 構成比合計が丸めで 100% にならない: 表示は四捨五入 %、内部計算は実値を使用。

## テスト / QA

- 集計純関数（`computePfcBalance` 等）の単体テスト: 通常値・記録 0 日・体重欠損・端数丸め。
- 実装後 `chrome-web-qa` スキルでブラウザ動作確認:
  - データ有/無、期間切替（共通セレクタ）の両グラフ連動、ツールチップ、ステータス判定（不足/適正/過剰）。

## UIデザイン仕様（ui-ux-pro-max 反映）

実装サブエージェント（nextjs-ui）向けの確定指針。既存デザイントークン（Primary `#0F172A` / Accent `#14B8A6` / BG `#F8FAFC` / Surface `#FFF` / border `#E2E8F0` / radius 6px(最大8px) / font Noto Sans JP・Plus Jakarta Sans / 8px グリッド）に従う。

### 共通
- カードは `bg-white border border-[#E2E8F0] rounded-md p-4`（既存サマリーカード踏襲）。シャドウは使わない（フラット）。
- ミュート文字は最低 `#475569`（slate-600）。`#94A3B8` 以下を本文に使わない（コントラスト 4.5:1 確保）。
- **色だけで情報を伝えない**: ステータスは色＋テキスト（不足/適正/過剰）。任意でアイコン併用（lucide）。
- **reduced-motion**: recharts は `prefers-reduced-motion` 時に `isAnimationActive={false}`。CSS アニメーションも `@media (prefers-reduced-motion: reduce)` で抑制。
- インタラクティブ要素に `cursor-pointer`、hover は `transition-colors duration-200`。
- アイコンは lucide（emoji を UI アイコンに使わない）。
- `'use client'` はチャートのリーフ component のみ。

### ① 体重 × PFC オーバーレイグラフ
- recharts `ComposedChart` + `ResponsiveContainer`（height 300–320）。
- PFC 棒は part-to-whole だが 3 系列なので可読。各棒は alpha 0.55 で**背面**、体重ラインを**前面**に。
- 凡例（Legend）必須。体重=実線、目標=破線、P/F/C=色四角で区別。
- 空/ローディングは既存 EmptyState/LoadingState 踏襲。
- a11y: グラフ下に「データ表で見る」trigger（折りたたみの table 代替）を任意提供（horizontal scroll ラッパ）。

### ② PFC 構成比カード
- ドーナツ: スライスは P/F/C の 3 色のみ、**各スライスに % ラベル**＋凡例。中央に平均 kcal/日（数値大 `#0F172A` bold + 補足 `#475569`）。
- あすけん風バー: 1 行 = ラベル + ステータスチップ + 実測% + g。バー高さ 18px、`rounded`。適正ゾーン `#C2E6A8`、目標線 3px `#2F7D33`＋▼、バー色 P `#6366F1` / F `#E6B968` / C `#E294AE`。
- バー下に「適正 13–20%」注記（`#475569`）。
- レスポンシブ: ドーナツとバーは `flex-wrap`。狭幅（<640px）では縦積み。

## 後続タスク（このスペックの外）

- 段階 B: clients テーブルに目標 PFC 比カラム追加 + 編集 UI + Web/Mobile 型/モデル更新。
- モバイル側へ「PFC 構成比カード」相当を展開するか検討。

## デザイン検討の記録（ビジュアル壁打ち）

`.superpowers/brainstorm/.../content/` に検討時のモックを保存:
- `compare-current.html` 現状 Web vs モバイル
- `merge-options.html` 統合方式 A(オーバーレイ) vs B(上下パネル) → **A 採用**
- `donut-asken-v2.html` / `zone-compare.html` 目安バー → **案2（目標線主体）採用**
- `zone2-saturation.html` 色味 → **B（しっかり）採用**
- `protein-color.html` P バー色 → **インディゴ #6366F1 採用**
