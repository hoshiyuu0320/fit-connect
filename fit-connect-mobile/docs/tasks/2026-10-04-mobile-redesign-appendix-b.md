# モバイル再デザイン 付録B: 画面側で繰り返し使う共通部品（行・囲み・ボタン・グラフ）

仕様書（`2026-10-04-mobile-redesign-spec.md`）の付録A「基盤 API」への追加分。**加算のみ**（付録Aの部品の API は変えていない）。
画面担当は、同じ型の部品を自作せず、ここの部品を使うこと。足りないものはマネージャーへ。

```dart
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart'; // 付録A と同じ。新部品もここから出る
```

実装: `lib/shared/widgets/fc/fc_list.dart` / `fc_misc.dart` / `fc_charts.dart`。プレビュー: `fc_previews_extra.dart`（`FcExtraPreviewGallery` ほか）。
テスト: `test/shared/widgets/fc/fc_extra_widgets_test.dart`。

共通の性質（付録A と同じ）: 色・余白・角丸はトークン経由 / タッチ領域 44 以上 / `Semantics` あり / ライト・ダーク対応 / 文字拡大 1.35 で overflow しない（折り返して縦に伸びる）。

## B.1 一覧

| 部品 | 置き場所 | 正本の対応箇所 |
| --- | --- | --- |
| `FcListRow` / `FcListRow.toggle` / `FcRowValue` / `FcValuePart` / `FcRowDensity` | `fc_list.dart` | `home-screens.js` `SumRow`、`more-screens.js` `Row`、`record-screens.js` `ListCard` の行、`plan-screens.js` `Upcoming` の行、`home-screens.js` `GettingStarted` の行 |
| `FcRowsCard` | `fc_list.dart` | `more-screens.js` `RowsCard`、`.rd-rows`、`HomeSummary` / `GettingStarted` のカード |
| `FcStatList` / `FcStatItem` | `fc_list.dart` | `components.jsx.txt` `StatList`、`.rd-flush` |
| `FcInfoBox` | `fc_misc.dart` | `SleepTab` の就寝/起床、`MealForm` の推定値、`ExerciseCard` のコーチのメモ |
| `FcIconButton` | `fc_misc.dart` | `message-screens.js` `RoundBtn`、`RecordsScreen` の睡眠同期ボタン |
| `FcCloseButton` | `fc_misc.dart` | `message-screens.js` `CloseBtn`、`GettingStarted` の閉じる |
| `FcPhotoPlaceholder` | `fc_misc.dart` | `parts.js` `Photo` |
| `FcLineChart` / `FcChartPoint` | `fc_charts.dart` | `parts.js` `LineChart` |
| `FcBars` / `FcBarItem` | `fc_charts.dart` | `parts.js` `Bars` |
| `FcSleepStageBar` / `FcSleepStage` | `fc_charts.dart` | `record-screens.js` `StageBar` |

## B.2 行と行カード

### `FcListRow`

```dart
FcListRow(
  title: '食事',                       // 16 / 行高 1.5
  icon: LucideIcons.utensils,          // 18 / accent（color を渡せばタイトルと同じ色）
  leading: FcDoneMark(done: true),     // icon の代わりに置く任意の左側（icon より優先）
  caption: '朝食・昼食を記録',         // 12 / textSecondary
  trailing: FcRowValue.metric([FcValuePart('2', '回')]), // 右側（値・操作・任意の Widget）
  color: null,                         // タイトルとアイコンの色。error にすれば「アカウントを削除」
  chevron: null,                       // null = onTap があれば出す。false で消す、true で出す
  externalLink: false,                 // true で外部リンクのアイコン（chevron は出ない）
  onTap: open,                         // 行全体が押せる（scale 0.98）
  density: FcRowDensity.summary,       // 最小高さ / 縦余白
  semanticLabel: null,                 // 読み上げの上書き
)
```

- 末尾アイコンは 16 / textSecondary。文字拡大では title・caption が折り返し、行が縦に伸びる。`trailing` の幅は画面の半分まで（超えれば折り返す）
- 読み上げは「タイトル、補足、値」を 1 つにまとめる（`FcRowValue` と `Text` の値を拾う。それ以外の `trailing` を含めたいときは `semanticLabel`）。`trailing` がボタンなどの操作のときは、`onTap` を付けない（行をまとめて 1 つにしない）
- `FcRowDensity`: `standard`（最小 54・縦 10。設定・一覧）/ `summary`（56・13。ホームの今日のまとめ）/ `record`（52・12。記録の履歴）

### `FcListRow.toggle`

```dart
FcListRow.toggle(title: 'セッションのリマインド', caption: '前日と当日の朝にお知らせ', value: v, onChanged: set)
```

右端に `FcToggle`。行のどこを押しても切り替わる（スイッチを押しても 1 回だけ）。読み上げは「タイトル、補足」＋切り替え状態。`onChanged: null` で無効。

### `FcRowValue`（`trailing` の定型）

| 形 | 見た目 | 使いどころ |
| --- | --- | --- |
| `FcRowValue.metric([FcValuePart('7', '時間'), FcValuePart('30', '分')])` | 数値 20 / 500（tabular・字間 -0.4）＋ 単位 13（textSecondary） | ホームの今日のまとめ（`SumRow`） |
| `FcRowValue.text('62.4 kg', muted: false)` | 16 / 500（tabular）。`muted` で textSecondary | 記録の履歴の値（`ListCard`）。「未取得」は `muted: true` |
| `FcRowValue.missing()` | 「未記録」15 / textSecondary（文言は `text:` で変更可） | 未記録（0 と区別して 0 を出さない） |
| `FcRowValue.action('目覚めを記録')` | accent 15 / 500 | 行を `onTap` で押すと記録できる入口 |
| `FcRowValue.loading()` | スケルトン 64×18。読み上げ「読み込み中」 | 読込中の行（配置は保つ） |

### `FcRowsCard`

```dart
FcRowsCard(
  title: '今日のまとめ',                 // 16 / 500（下に 2）。または header: 任意の Widget
  padding: FcRowsCard.summaryPadding,    // 上 16・下 4・左右 20。既定は defaultPadding（上下 2・左右 20）
  headerEndBleed: 0,                     // 見出しの右に FcCloseButton を置くとき FcCloseButton.endBleed
  children: [FcListRow(...), FcListRow(...)],
)
```

`FcCard`（角丸 23・不透明）の中に子の**間だけ**区切り線（`FcSeparator`）を挟む。先頭の上・最後の下には引かない。見出しと最初の行の間にも引かない。行側で線を描かない。

### 使用例（正本の画面）

```dart
// ホームの今日のまとめ（HomeSummary）
FcRowsCard(
  title: '今日のまとめ',
  padding: FcRowsCard.summaryPadding,
  children: [
    FcListRow(density: FcRowDensity.summary, icon: LucideIcons.utensils, title: '食事', caption: '朝食・昼食を記録',
        trailing: FcRowValue.metric([FcValuePart('2', '回')]), onTap: openMeals),
    FcListRow(density: FcRowDensity.summary, icon: LucideIcons.moon, title: '睡眠',
        caption: 'ヘルスケアと連携すると自動で入ります', trailing: FcRowValue.action('目覚めを記録'), onTap: record),
  ],
)

// 設定のカード（通知トグル / 連携 / 法的情報 / アカウント）
FcRowsCard(children: [
  FcListRow.toggle(title: '目標の達成', value: on, onChanged: set),
])
FcRowsCard(children: [FcListRow(title: '利用規約', externalLink: true, onTap: open), ...])
FcRowsCard(children: [
  FcListRow(icon: LucideIcons.logOut, title: 'ログアウト', chevron: false, onTap: logout),
  FcListRow(title: 'アカウントを削除', color: colors.error, chevron: false, onTap: delete),
])

// 記録の履歴（ListCard）
FcRowsCard(children: [
  FcListRow(density: FcRowDensity.record, title: '9月13日（日）7:30', caption: 'メッセージから', trailing: FcRowValue.text('62.4 kg')),
])

// はじめの3ステップ（GettingStarted）。完了は leading に FcDoneMark
FcRowsCard(
  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
  headerEndBleed: FcCloseButton.endBleed,
  header: Row(children: [
    Expanded(child: Text('はじめの3ステップ', style: AppTextStyles.body(context).copyWith(fontWeight: FontWeight.w500))),
    Text('1 / 3', style: AppTextStyles.supplement(context)),
    FcCloseButton(onPressed: dismiss),
  ]),
  children: [
    FcListRow(leading: FcDoneMark(done: true, size: 22), title: '最初の体重を記録する', color: colors.textSecondary,
        trailing: Text('完了', style: AppTextStyles.supplement(context))),
    FcListRow(leading: FcDoneMark(done: false, size: 22), title: 'トレーナーにメッセージを送る', onTap: open),
  ],
)
```

### `FcStatList`

```dart
FcStatList(items: [
  FcStatItem(label: 'たんぱく質', description: '記録した10日の平均', value: '95 g'),
  FcStatItem(icon: LucideIcons.dumbbell, label: '筋トレ', value: '2回'),
  FcStatItem(label: '消費カロリー', value: null), // null = 「未記録」（textSecondary）
])
```

行は縦余白 14・間にだけ区切り線（**最後の行は線なし**）。icon 17 / accent、label 16、description は caption（上 3）、値 17 / 500（tabular・右寄せ）。カードの余白・見出しは画面側で `FcCard`（正本は上 16・下 2 や 上 4・下 2）＋ `FcCardHead` を組む。

## B.3 囲み・ボタン・写真の代替

| 部品 | コンストラクタの要点 | 使用例 |
| --- | --- | --- |
| `FcInfoBox` | `child`, `padding`（既定 縦 10 × 横 14）, `expand=true`, `semanticLabel`。surfaceSecondary・角丸 12。surface の上に重ねる | `FcInfoBox(child: Text('推定 640 kcal'))` |
| `FcIconButton` | `icon`, `semanticLabel`（**必須**）, `onPressed`（null で無効・不透明度 0.4）, `primary=false`, `iconColor`, `iconSize=20`。44×44 の丸。既定は surface の面＋textSecondary、`primary` は actionFill＋onAction。surface のカードの上に置くと面が溶ける | `FcIconButton(icon: LucideIcons.arrowUp, semanticLabel: '送信', primary: true, onPressed: send)` / 同期ボタンは `iconColor: colors.accent` |
| `FcCloseButton` | `onPressed`, `semanticLabel='閉じる'`（返信バナーなら「返信をやめる」）。44×44・「×」18・textSecondary。`FcCloseButton.endBleed=12` / `verticalBleed=10` は正本の負マージンの値 | `FcCloseButton(onPressed: close)` |
| `FcPhotoPlaceholder` | `height=160`, `width`（省略で親の幅いっぱい。`Row` の中では渡す）, `radius=16`, `label='写真'`。surfaceSecondary・image アイコン 22。高さ 100 以上でラベルも出す。画像として読み上げ | `FcPhotoPlaceholder(height: 176, radius: 0, label: '食事の写真')` / 72×72 は `width: 72, height: 72, radius: 14` |

### `FcCloseButton` の置き方（正本の負マージンの代わり）

正本 `CloseBtn` は右 -12・上下 -10 の負マージンで詰めている。Flutter では負の余白だと押せる範囲が欠けるので、**部品は 44×44 のまま**、配置側でカードの余白を減らす。

```dart
// 食事を記録フォーム（正本: カード余白 18・見出し行の高さ 24）
FcCard(
  paddingOverride: EdgeInsets.fromLTRB(18, 18 - FcCloseButton.verticalBleed, 18 - FcCloseButton.endBleed, 18),
  child: Column(children: [
    Row(children: [icon, Expanded(child: title), FcCloseButton(onPressed: close)]),
    SizedBox(height: 12 - FcCloseButton.verticalBleed), // 見出し行の下の余白 12 から 10 を引く
    ...
  ]),
)
```

`FcRowsCard` の見出しに置くときは `headerEndBleed: FcCloseButton.endBleed`（上の「はじめの3ステップ」参照）。

## B.4 グラフ（`fl_chart` 不使用）

### `FcLineChart`

```dart
FcLineChart(
  data: [FcChartPoint(61.6, label: '9/1'), FcChartPoint(61.8), ..., FcChartPoint(62.4, label: '9/13')],
  goal: 65, goalLabel: '目標 65.0 kg',
  min: 61, max: 65.4,   // 省略すると データと goal から余白 10% を足して自動
  height: 150,          // 体重タブは 170
  semanticLabel: '9月の体重の推移', // 必須。グラフ本体は読み上げない
)
```

横線 3 本（separator）、目標の破線（4/4）とラベル（右端・11px）、折れ線（accent 2px）、点（半径 2.5・塗り surface・枠 accent 1.5。**最後の点だけ半径 4・塗り accent**）、x ラベル（11px・中央）。上 16、下 24（x ラベルがあるとき）/ 6（無いとき）。ラベルは 11px 固定（正本も固定）。幅は親いっぱい。`min`/`max` を超える値は枠の外に描かれる。

### `FcBars`

```dart
FcBars(
  max: 540, height: 96,       // 既定 110
  showValues: true, gap: 8,   // カロリーの 13 本は showValues: false, gap: 4, height: 84
  semanticLabel: '直近7日間の睡眠時間',
  items: [FcBarItem(value: 410, text: '6:50', highlighted: false, label: '月'), FcBarItem(value: null, label: '水'), ...],
)
```

列は等幅、棒は幅いっぱい（最大 28）・角丸 7・最小高さ 4。**ハイライト = accent、それ以外 = textSecondary の 28%**。`value: null` は高さ 2 の separator 線で、`showValues` のとき「未取得」を出す（0 と区別する）。値の文字は 11px（文字拡大は 1.15 倍まで、収まらなければ縮小）、x ラベルは caption（ハイライトは accent・500）。読み上げは列ごとに「ラベル 値」（`text` は表示しなくても読み上げに使う）。

### `FcSleepStageBar`

```dart
FcSleepStageBar(stages: [
  FcSleepStage(label: '深い', minutes: 85, percent: 100),
  FcSleepStage(label: 'レム', minutes: 110, percent: 60),
  FcSleepStage(label: '浅い', minutes: 255, percent: 30),
  FcSleepStage(label: '覚醒', minutes: 20, percent: 0), // percent 0 = separator 色
])
FcSleepStageBar.formatMinutes(410); // '6時間50分'（60 分未満は '59分'）。睡眠の履歴の時間にも使える
```

帯は高さ 10・角丸 5・区間の間 2、幅は分の比率。色は accent を surface に `percent`% 混ぜた色。凡例は 2 列（文字拡大 1.25 倍以上は 1 列）。上の余白（正本は 16）は含まないので画面側で空ける。0 分の区間は帯に出さず凡例には残す。

## B.5 判断したこと

- **数値の単位の色**: 正本の画面 HTML では `<small>` が親の色を継ぐが、`DESIGN_SYSTEM.md` §4 の「textSecondary: 日時・単位の補足」と付録A の `numUnit`（textSecondary）に合わせ、`FcRowValue.metric` の単位も textSecondary にした（優先順位: DESIGN_SYSTEM.md とトークン → 画面HTML）。
- **行の押下は `FcPressable`**（scale 0.98）。正本の `Row` / `SumRow` は押下表現を持たないが、「行全体を押せる」要件のため。`onTap` を付けない行は押下しない。
- **`FcPressable` の読み上げ**: `semanticLabel` を渡さないと button フラグとラベルが別ノードに割れていた（基盤側で `GestureDetector(excludeFromSemantics: true)` により修正済み）。`FcListRow` は念のため、押せる行ではタイトル・補足・値をつなげた `semanticLabel` を明示して 1 ノードにしている。
- **負マージンは再現しない**: `FcCloseButton` の B.3 を参照（押せる範囲を欠かさないため、配置側の余白で調整する）。
- **テスト用キー**: `FcBars` の棒は `ValueKey('fc-bar-N')`、`FcSleepStageBar` の区間は `ValueKey('fc-sleep-stage-N')`（テストが寸法・色を確かめるためのもの。画面側は使わない）。
- **確認方法**: 使い捨てのゴールデン（Arial Unicode と Lucide のフォントを読み込んだ PNG）で、ライト／ダーク／文字拡大 1.35 を目視し、正本の値（グラフの余白・点の大きさ・棒の色・凡例の 2 列など）と照合済み。ファイルは削除済み。
