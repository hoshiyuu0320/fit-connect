# 体重記録 期間統計表示機能 設計書

## 概要

Web側（トレーナー向け）の `WeightTab` に、選択中の期間内の体重統計（平均・最高・最低・変動幅）を表示するセクションを追加する。

Mobile側には既に同等の機能が `_buildPeriodStats` として実装済みのため、Web側のみの変更。

## 変更対象

- `fit-connect/src/app/(user_console)/clients/[client_id]/_components/WeightTab.tsx`

## UI設計

### 配置

グラフカード `</div>` (約line 86) と記録リスト `<div>` (約line 89) の間に統計カードを挿入:

```
┌─────────────────────────────────┐
│  期間フィルター [1W][1M][3M][ALL] │
│  ┌───────────────────────────┐  │
│  │     体重推移グラフ          │  │
│  └───────────────────────────┘  │
├─────────────────────────────────┤
│  平均    │  最高   │  最低   │ 変動幅 │
│  62.3kg  │ 63.5kg │ 61.0kg │ 2.5kg  │
├─────────────────────────────────┤
│  最近の記録リスト               │
└─────────────────────────────────┘
```

### スタイル

- 4項目を `grid grid-cols-2 sm:grid-cols-4 gap-4` で均等配置（狭い画面では2列に折り返し）
- 既存の WeightTab デザイントークンに準拠（グレー背景カード、テキスト色）
- ラベル: 小さめグレーテキスト (`text-sm text-gray-500`)
- 値: 太字 (`text-lg font-bold`)
- 角丸: `rounded-md` (6px)

## 計算ロジック

計算対象: `filteredRecords`（期間フィルター適用済み配列。`WeightTab` 内の既存 `useMemo` で生成される変数）

`useMemo` で `filteredRecords` から算出:

| 項目 | 計算方法 |
|------|----------|
| 平均 | `records.reduce((sum, r) => sum + r.weight, 0) / records.length` |
| 最高 | `Math.max(...records.map(r => r.weight))` |
| 最低 | `Math.min(...records.map(r => r.weight))` |
| 変動幅 | `最高 - 最低` |

- 小数点第1位まで表示（`toFixed(1)`）
- `filteredRecords.length === 0` の場合は全項目 `--` 表示（Mobile側は0件時にセクション非表示だが、Web側はトレーナー向けUIのため `--` を表示して期間内にデータがないことを明示する）
- 0件ガードは `Math.max` / `Math.min` 呼び出し前に行い、`-Infinity` / `Infinity` / `NaN` を防止する

## 既存機能への影響

- 変更は `WeightTab.tsx` のみで完結
- 既存の `weightRecords` データを再利用するため、追加のAPI呼び出しなし
- `WeightChart` コンポーネントへの変更なし
- Supabaseスキーマへの変更なし → Mobile側への影響なし
