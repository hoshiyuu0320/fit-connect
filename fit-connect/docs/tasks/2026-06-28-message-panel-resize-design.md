# メッセージ画面 パネル幅ドラッグリサイズ — 設計

- 日付: 2026-06-28
- 対象: fit-connect（Trainer Web App / Next.js）
- ブランチ: `feature/message-panel-resize`（`develop/1.0.0` から分岐）

## 目的

メッセージ画面（`/message`）の3カラムのうち、**左の顧客リスト幅**と**右の記録パネル幅**を、
境界のドラッグで自由に変更できるようにする。調整した幅は localStorage に永続化し、
リロード・再ログイン後も維持する。

## 現状（調査結果）

- 3カラムは `src/app/(user_console)/message/page.tsx` の return 内に直書き（専用レイアウトコンポーネントなし）
  - 左リスト: `page.tsx:474` `<aside className="w-72 ...">`（288px 固定）
  - 中央会話: `page.tsx:497` `flex-1`（残り可変）
  - 右記録パネル: `RecordSidePanel.tsx:48` `<aside className="w-96 ...">`（384px 固定）
- 右パネルの開閉は `page.tsx:63` のローカル `useState(true)`（永続化なし）
- 幅の state 管理・localStorage 永続化・リサイズライブラリは未導入
- レスポンシブ（ブレークポイント）対応はメッセージ画面には無し

## 方針

採用アプローチ: **手書きのドラッグハンドル**（汎用フック + 共通ハンドルコンポーネント）。
`react-resizable-panels` 等の新規ライブラリは**導入しない**（開閉できる右パネルの既存ステートマシンと
噛み合わせる改修が大きいため）。`package.json` / `package-lock.json` は変更しない。

## 構成

### 新規ファイル

1. `src/hooks/useResizablePanel.ts`
   - 1パネル分の「サイズ state ＋ localStorage 永続化 ＋ min/max クランプ ＋ ドラッグ／キーボード処理」を担う汎用フック（幅・高さ両対応）
   - 入力: `{ axis: 'x' | 'y'; storageKey; defaultSize; min; max; edge: 'left' | 'right' | 'top' | 'bottom' }`
     - `axis` は `'x'`=幅 / `'y'`=高さ。`edge` はハンドルが置かれる辺。`'right'`/`'bottom'`＝拡大方向、`'left'`/`'top'`＝縮小方向（符号反転）
     - カーソルは軸から導出（x=`col-resize` / y=`row-resize`）、`aria-orientation` も軸から導出（x=`vertical` / y=`horizontal`）
   - 返り値: `{ size: number; isDragging: boolean; handleProps }`（`handleProps` に `role='separator'` / `aria-*` / `tabIndex` / `onMouseDown` / `onKeyDown`）
2. `src/components/message/ResizeHandle.tsx`
   - 境界に置く全長の細いドラッグ用ハンドル（見た目 ＋ `handleProps` スプレッドのみ。状態は持たない）
   - props: `{ side: 'left' | 'right' | 'top' | 'bottom'; isDragging; ariaLabel; handleProps }`（向きは `side` から導出: left/right=縦ハンドル / top/bottom=横ハンドル）

### 改修ファイル

3. `src/app/(user_console)/message/page.tsx`
   - フックを2回呼ぶ（左 / 右）
   - 左 `<aside>` の `w-72` を撤去 → `style={{ width: left.width }}` ＋ `shrink-0`
   - 左/中央の間に `<ResizeHandle>`（常時表示）
   - 中央/右の間に `<ResizeHandle>`（右パネルが開いている時のみ＝既存の条件付き描画ブロック内）
   - `right.width` を `RecordSidePanel` に渡す
4. `src/components/message/RecordSidePanel.tsx`
   - `w-96` を撤去 → `width` prop を受けて `style={{ width }}` ＋ `shrink-0`

> 右パネルの開閉ロジック（「記録を表示」ボタン・閉じる X・`useState`）は**変更しない**。
> 右ハンドルは開いている時だけ描画。閉じている間も幅は localStorage に保持し、再表示時に復元。

## データフロー

1. マウント時: 幅は**デフォルト値**で初期化（サーバー描画と一致＝ハイドレーション不整合回避）。
   `useEffect` で localStorage を読み、妥当値があれば反映（初回のみ1フレーム調整）
2. `mousedown`: 開始 X 座標・開始幅を記録 → `window` に `mousemove`/`mouseup` を登録 →
   `body` のカーソルを `col-resize`・テキスト選択を抑止
3. `mousemove`: `新幅 = 開始幅 ± (現在X − 開始X)`（左 = ＋ / 右 = −）→ min/max クランプ → 幅 state 更新
4. `mouseup`: リスナー解除・`body` スタイル復元 → **確定幅を localStorage へ保存**（ドラッグ中は書き込まない）

- localStorage キー: `fc.message.leftWidth` / `fc.message.rightWidth` / `fc.message.recordSummaryHeight`

## 幅の制約

| パネル | デフォルト | min | max |
|---|---|---|---|
| 左リスト | 288px（現 w-72） | 180px | 400px |
| 右記録パネル | 384px（現 w-96） | 320px | 480px |

- 両パネルに `shrink-0` を付与し、インライン幅を厳密維持（中央 `flex-1` が残りを吸収）
- 中央会話領域は 1280px 幅・左右最大時でも約 320px 確保される想定
- より厳密に中央最小幅を守る動的 max はスコープ外（v1 は固定 max。必要なら拡張）

## 記録パネルのサマリー↔記録ログ 縦リサイズ

記録パネル（`RecordSidePanel`）内で、上部「サマリー」と下部「記録ログ」の高さ配分を、
境界の**縦ドラッグ**で変更できる。`useResizablePanel({ axis: 'y' })` を本コンポーネント内部で完結して使用する。

- フック: `useResizablePanel({ axis: 'y', storageKey: 'fc.message.recordSummaryHeight', defaultSize: 440, min: 80, max: maxSummaryHeight, edge: 'bottom' })`（`max` は固定値ではなく後述の動的値）
- 構造: サマリーは外側 `relative`（`overflow-hidden` は付けない＝下端ハンドルの `translate-y-1/2` がクリップされるため）＋ `style={{ height }}`。内側に `h-full overflow-y-auto` のスクロール領域を置き、その中身を `min-h-full flex flex-col` の縦カラムにする。ラベルと PFC カードは `flex-shrink-0`、グラフ枠は `flex-1 min-h-[320px] relative` ＋ 内側 `absolute inset-0`（recharts `height="100%"` が flex 由来の高さでは 0 に解決するため確定高さを与える。サマリーが高い時は拡大、低い時も最低 320px を確保→スクロール）。スクロール領域の兄弟として末尾に `<ResizeHandle side="bottom">` を配置（可視下端＝サマリー/フィルタ境界に留まる）
- フィルタ chips・記録ログ（`flex-1 overflow-y-auto`）は変更なし

### サマリー上限の動的追従

固定 max だとウィンドウが低い時にフィルタ/記録ログがはみ出すため、サマリー上限を**ウィンドウ高さに動的追従**させる。

- `RecordSidePanel` がルート `aside` / ヘッダー / フィルタ chips に ref を持ち、`ResizeObserver(aside)` で計測
- `max = clamp( aside.clientHeight − headerH − filterH − LOG_MIN(8), 下限 SUMMARY_MAX_FLOOR=320, 上限 SUMMARY_MAX_CAP=1000 )`
- これを `useResizablePanel` の `max` に渡す。`max` 変化時はフック側の**再クランプ effect**（`useEffect(() => setSize((prev) => clamp(prev)), [clamp])`）が現在 size を新範囲へ収める
- 効果: 境界を上方向にドラッグすると記録ログを約 8px の薄いピークまで畳め、サマリーを（フィルタを残したまま）利用可能高さいっぱい＝ほぼ全画面まで拡大して全表示できる。ウィンドウ/パネル幅変更時も上限が追従

| パネル | デフォルト | min | max |
|---|---|---|---|
| サマリー高さ | 440px | 80px | 動的（利用可能高さ − 8、範囲 320〜1000） |

- グラフ `WeightNutritionChart` はサマリー高さに**追従して拡大**（`fillHeight` prop ＝ `ResponsiveContainer height="100%"`、グラフ枠の `flex-1 min-h-[320px]` で最低 320px）。サマリーを下に拡大するとグラフが伸び（余白なし）、上に縮小するとグラフは 320px で固定＋サマリー内 `overflow-y-auto` でスクロール（従来の「ログ最大」状態を維持）
- `fillHeight` は**オプトイン**。顧客詳細の `SummaryTab` は `fillHeight` 未指定＝従来どおり固定 320px のまま（無影響）
- 画面が短い場合、サマリーを大きく取ると下部の記録ログ表示領域が小さくなり得る（記録ログは `flex-1` で残りを吸収するため最低限は確保されるが、縦ドラッグで調整可能）

## エッジケース

- **異常値ガード**: localStorage が NaN・範囲外・読込不可なら `try/catch` でデフォルトにフォールバック
- **リスナー後始末**: ドラッグ途中でアンマウントされても `useEffect` の cleanup で `window` リスナーと `body` スタイルを必ず復元
- **ハンドルの見た目**: 既存の境界線（`#E2E8F0`）に重なる約6px の当たり判定。`cursor-col-resize`、
  ホバー / ドラッグ中だけ控えめなアクセント表示。配色・太さは実装直前に `ui-ux-pro-max` で確定し
  CLAUDE.md のデザイントークン（角丸控えめ・原色濫用禁止・余白確保）に準拠

## 動作確認（chrome-web-qa）

実装後、以下を Chrome で検証:

1. 左ハンドルのドラッグで左リスト幅が変わる / min・max で止まる
2. 右ハンドルのドラッグで右パネル幅が変わる / min・max で止まる
3. リロード後も両幅が維持される
4. 右パネルを閉じて再表示しても幅が復元される
5. ドラッグ中に中央会話領域が極端に潰れない
6. ドラッグ中のテキスト選択が起きない / カーソルが `col-resize` になる
