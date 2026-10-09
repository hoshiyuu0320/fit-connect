# 合成スクリーンショット生成器（screenshots-synthetic-v1）

`estimate-meal-nutrition` の **スクショ入力（`input_kind: 'screenshot'`）** を評価するためのデータセットを作ります。
他社の食事管理アプリの画面を **架空アプリとして HTML で描画** し、iPhone のスクショ → モバイルアプリのアップロード前処理と同じ縮小・JPEG 化を通したものです。
画面に出ている数値はすべて `cases.ts` のデータから描画しているので、**正解（ground truth）が厳密に分かっています**。

- 本番プロンプト: `supabase/functions/estimate-meal-nutrition/index.ts` の `SCREENSHOT_SYSTEM_PROMPT`
- 出力: `datasets/screenshots-synthetic/cases.json` と `datasets/screenshots-synthetic/images/*.jpg`（コミット対象）
- 参考用の撮影直後 PNG（1170x2532）: `datasets/screenshots-synthetic/raw/*.png`（gitignore 済み）

## 再生成

```bash
cd evals/meal-estimation
npm run gen:screenshots
```

- Chromium は `/opt/pw-browsers/chromium-1194/chrome-linux/chrome` を使います（`CHROMIUM_PATH` で上書き可）。
- フォントは `'IPAGothic', 'IPAPGothic', sans-serif`（ローカルにインストール済みのもの。外部フォントは読み込まない）。
- `KEEP_RAW=0` を付けると raw PNG を保存しません。
- 乱数は使っていません。同じ環境で再実行すると `cases.json` と JPEG はバイト単位で同一になります（確認済み）。
  Chromium / sharp / フォントのバージョンが変わると JPEG のバイト列は変わり得ますが、`cases.json` は変わりません。

## 前処理（本番と同じ）

| 段階 | 内容 |
| --- | --- |
| 撮影 | viewport 390x844 CSS px、deviceScaleFactor 3 → **1170x2532 PNG**（iPhone 14/15 相当） |
| アップロード前処理 | `fit-connect-mobile/lib/services/storage_service.dart` の `StorageService.pickImage` と同じ値（maxWidth 1920 / maxHeight 1080 / imageQuality 80）。sharp で `resize({ width: 1920, height: 1080, fit: 'inside', withoutEnlargement: true }).jpeg({ quality: 80 })` |
| 結果 | 縦長スクショは **499x1080 JPEG**（1枚 30〜50 KB） |

499px 幅だと文字は小さくなりますが、これは本番でモデルが実際に見る解像度です。正解に使う数値は、この解像度でも人が読めることを目視で確認しています（小さい文字のケースでも CSS 11px 以上 = 出力で約 14px 以上）。

## ケース構成（27 ケース / 34 枚）

架空アプリ 3 種のレイアウト + 食事アプリ以外の 3 種です。実在アプリ（あすけん、カロミル、MyFitnessPal 等）の名前・ロゴは使っていません。

| レイアウト | アプリ名 | 特徴 |
| --- | --- | --- |
| A | ごはんログ | 1食サマリー: kcal リング + P/F/C 棒グラフ + 品目ごとの kcal のみ（品目の PFC は出ない） |
| B | ミールノート | 1食詳細: 品目ごとに kcal と P/F/C チップ、合計カードは上 or 下 |
| C | MealDiary | 英語 UI: Calories / Protein / Fat / Carbs の表 + Total 行 |

| 種別 | 件数 | ID | 内容 | 正解 |
| --- | --- | --- | --- | --- |
| 1枚・1食 (`single`) | 13 | ss-001〜013 | A×4 / B×5 / C×4。ダーク 3（ss-003, 007, 011）、小さい文字・詰まった画面 2（ss-009: 7品目, ss-013: 10品目）、小数グラム 2（ss-008, ss-012） | 画面の合計を整数に切り捨て |
| 1日ビュー (`day-view`) | 4 | ss-014〜017 | 朝・昼・夕・間食それぞれの kcal と P/F/C 小計 + 1日合計（A / B / C / B ダーク） | `totals` = 1日合計、`alt_totals` = [最大の1食の小計] |
| 2枚・同じ食事 (`two-image`, `consistent`) | 4 | ss-018〜021 | 1枚目 = 品目 + 合計 kcal（PFC なし）、2枚目 = 同じ食事の PFC グラフ（同じ合計 kcal を表示） | 合計（kcal は両画面共通、PFC は2枚目）、`expect_warning: false` |
| 2枚・別の食事 (`mismatch`) | 3 | ss-022〜024 | 2枚目が別の食事。kcal が 30% 以上違い、2枚目の PFC は1枚目の kcal に合わない。ss-022 は同じ日の昼食 vs 夕食、ss-023 は日付・食事区分の表示まで同じで数値だけが違う、ss-024 は別の日 | `totals: null`（採点しない）、`expect_warning: true` |
| 食事アプリ以外 (`non-meal`) | 3 | ss-025〜027 | 天気アプリ（そらもよう）、チャット（トークル: 食べ物の話題と金額はあるが栄養値なし）、歩数計（てくてくメーター: **消費カロリー** 312 kcal と脂肪燃焼量 21g を表示） | `is_meal: false`（foods は空配列が正解） |

### 意図的に入れているディストラクタ

- `distractor-target`: リング下の「目標 700 kcal」（ss-001, 003）。1日ビュー A も「目標 2,000 kcal」を表示
- `distractor-goal`: MealDiary の「Goal − Food + Exercise = Remaining」（ss-010）、1日表の Goal / Remaining 行（ss-016）
- `distractor-extra-nutrients`: ミールノート栄養タブの食物繊維・食塩相当量（ss-019, 023）
- PFC のエネルギー比 %（A / B / C の栄養画面）、ステータスバーの時刻・バッテリー %
- 1000 kcal 以上は「1,947」のように 3 桁区切り（1日ビュー、ss-024）
- `with-note`: `content` に中立的な補足（ss-002, ss-010）。他はすべて `''`

### タグ一覧

`layout-a|b|c`、`single`、`day-view`、`two-image`、`consistent`、`mismatch`、`non-meal`、`dark`、`dense`、`decimal`、`english`、
補助タグ: `totals-top`、`totals-bottom`、`jp-food-names`（英語 UI に日本語の食品名）、`diff-meal-label`、`same-label`、`diff-date`、`weather`、`chat`、`food-words`、`burned-kcal`、`with-note`、`distractor-*`

## 正解（expected）の決め方

`generate.ts` が `cases.ts` の同じデータから導出します（手書きの期待値はありません）。

- **合計** = 画面に表示している合計（品目の合計を 0.1 単位で合算）→ 各値を `Math.floor`（プロンプトの「小数点以下は切り捨て」）
  - 例: ss-008 は画面上 P 41.7 / F 14.6 / C 53.8 → 正解 41 / 14 / 53（四捨五入とは結果が変わるよう 2 つ以上を .5 以上にしている）
- `foods_count`: 採点対象の食事で画面に見えている品目行の数。1日ビューと mismatch は `null`、食事アプリ以外は `0`
- `expect_warning`: 2枚ケースのみ true/false、1枚ケースは `null`
- `app_name`: 画面に出ている架空アプリ名（参考情報。モデルの `app_name` は採点しない想定）
- `meal_type`: 1日ビューでは最大の食事の区分に合わせている（`alt_totals` と矛盾しないように）

## 生成時の自動チェック

生成時に以下を検証し、1 つでも外れたら失敗します。

- 採点対象の合計は kcal ≈ 4P + 9F + 4C（±5%）。品目単位でも ±12%（小さい品目は ±8 kcal）
- 小数ケース以外は全値が整数、小数ケースは小数第1位まで
- 2枚・同じ食事は 2 画面の合計・日付・食事区分が一致
- mismatch は kcal の差が 30% 以上、かつ 2枚目の 4P+9F+4C が 1枚目の kcal から 25% 以上ずれる
- 1日ビューは 4 食すべてあり、最大の食事が一意
- 描画後、正解に使う要素（`data-gt` 属性）がすべてタブバーより上・画面内にあり、はみ出していないこと（Chromium 上で計測）
- 撮影サイズが 1170x2532 であること

## ケースを追加・変更するとき

1. `cases.ts` の `CASES` にケースを追加（食品は `J` / `E` のライブラリか `f(...)` で直接書く）
2. `npm run gen:screenshots` を実行（検証エラーが出たら値を直す）
3. 出力 JPEG を目視確認（数値が読めるか、文字化け（豆腐）がないか）
4. `cases.json` と `images/` をコミット
