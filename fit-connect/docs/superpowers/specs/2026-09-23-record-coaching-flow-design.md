# 記録→指導動線（フェーズ9.3 / カタログ cat1 6-A）MVP 設計書

**作成日**: 2026-09-23
**対象**: fit-connect（Trainer Web App）のみ。Mobile・Supabase の変更なし
**出典**: `docs/tasks/2026-07-08-solution-catalog.md` 課題6 / 6-A、`docs/tasks/IMPLEMENTATION_TASKS.md` 9.3、フェーズ1.5 の繰り延べ分（睡眠→メッセージ画面への明示的動線）

## 1. 目的と背景

トレーナーが記録（体重・食事・運動・睡眠）の異変に気づいた場所から、**1クリックでその記録に触れたメッセージを書き始められる**ようにする。今は「記録を見る画面」と「メッセージ画面」が断絶しており、メッセージ画面へ手で移動してから文脈を打ち直す必要がある。

調査で確定した前提:

- `/message` の記録サイドパネル（`RecordSidePanel`）は DB の記録テーブルではなく **読み込み済みの messages 配列** からタグ付きメッセージを抽出して表示している（`extractRecordLog`）。各記録カードは元メッセージ（`item.message`）を既に持つ
- 返信機能（`replyToMessage` → `ReplyPreview` → `reply_to_message_id`）は Web / Mobile とも実装済み。Mobile は `reply_to_message_id` を持つメッセージを引用付きで描画する
- **睡眠はメッセージを経由しない**（`sleep_records` は HealthKit / 手動のみ、`message_id` 列なし、`#睡眠` タグは存在しない）。よってサイドパネルの引用返信だけでは睡眠に触れられない
- `messages.metadata` の規約レジストリ（統合判断7-1 の `docs/architecture/message-metadata-registry.md`）は未作成で、Web は `metadata` を読んでいない。Mobile も `record_ref` を描画しない
- `/message` のクエリは `clientId`（カタログ記載の `client` ではない）。ダッシュボードや顧客詳細からの導線はすべて `/message?clientId=...`
- Web のテストは vitest（node 環境）の純関数テストのみ。コンポーネントテストの基盤は無い

## 2. 検討した案

| 案 | 内容 | 判断 |
| --- | --- | --- |
| A. サイドパネルの引用返信 | 記録カードに「返信で触れる」を付け、既存の返信機構（`reply_to_message_id`）に乗せる。メッセージ由来の記録（体重・食事・運動・達成）が対象 | **採用**。カタログの MVP。Mobile 変更ゼロで両アプリに引用が出る |
| B. 睡眠からのディープリンク + 本文引用 | 顧客詳細の睡眠カード / 睡眠記録行から `/message?clientId=…&record=sleep:…` へ遷移し、メッセージ画面が睡眠の要約を **本文先頭に付ける平文の引用** として用意する | **採用**。睡眠に触れる唯一の Web 完結の方法。本文は平文なので Mobile の変更が要らず、旧アプリでも崩れない |
| C. `metadata.record_ref` + 両アプリのカード描画 | HealthKit 由来の記録を構造化メタデータで参照し、Web / Mobile がカードとして描画する | **見送り（拡張2）**。レジストリ文書の新設と Mobile リリースを伴う。B の引用テキストは、後で `record_ref` を添える際にそのまま流用できる |

案 B の引用を「入力欄への直接プリフィル」ではなく **入力欄の上に出す取り消し可能な引用チップ** にするのは、既存の `ReplyPreview` と同じ操作感にするため、および将来 `record_ref` を添える継ぎ目を1箇所にするため。

## 3. スコープ

### 入るもの

1. **記録サイドパネル → 返信で触れる**（案A）
2. **顧客詳細の睡眠（直近7日）カード → メッセージで触れる**（案B、7日サマリーの引用）
3. **顧客詳細 睡眠タブの「最近の記録」各行 → この記録についてメッセージ**（案B、1晩の引用）
4. `/message` の `record` クエリの解釈と引用チップ、送信時の本文合成
5. 上記の純関数（クエリの解釈・要約文の生成・本文合成・7日サマリー）の単体テスト
6. `SummaryTab` の 7日睡眠サマリー計算を純関数へ切り出す（挙動は変えない。メッセージ画面と同じ数字を出すため）

### 入らないもの

- `SleepChart` / `WeightChart` のデータ点クリック（拡張1）
- `metadata.record_ref` と Mobile のカード描画（拡張2）
- 体重・食事・運動の **DB 記録**（HealthKit 由来の体重など、メッセージを持たない記録）からの引用。`record=` の文法は `sleep` 以外を受け付けない
- 元メッセージへのスクロール（`ReplyQuote.onClick` は今も未使用）
- 9.1 の睡眠悪化アラート（未実装）との接続

## 4. UI 設計

### 4.1 記録サイドパネル（`RecordSidePanel`）

各記録カードの下の日時行を左右に分け、右端に小さなテキストボタン **「返信で触れる」**（lucide `Reply` アイコン + ラベル）を常時表示する。

- hover 時のみ表示にしない（iPad などタッチ環境では hover が無い。既存 `MessageBubble` の hover 返信ボタンとは違い、パネルは一覧なので常時表示でも邪魔にならない）
- 見た目は低強調: `text-[11px] text-[#64748B] hover:text-[#14B8A6]`、`focus-visible:ring-2 ring-[#14B8A6]`、`transition-colors`、`cursor-pointer`
- クリックで `onReplyStart(item.message)` を呼ぶ。ページ側は既存の `handleReplyStart`（`setReplyToMessage` + textarea フォーカス）をそのまま渡す
- `RecordCard` 自体（顧客詳細タブへの `Link` で包まれている）は変えない。ボタンは `Link` の外（`<li>` 内の日時行）に置き、`Link` とのネストを避ける
- `RecordSidePanel` の props に `onReplyStart?: (msg: Message) => void` を追加。未指定ならボタンを出さない

送信後の見え方は既存の返信と同じ: Web はトレーナー吹き出しの中に `ReplyQuote`（元メッセージの本文 = `#体重 65.2` などのタグ付き本文）、Mobile も既存の引用表示。

### 4.2 顧客詳細（`SummaryTab` / `SleepTab`）

**SummaryTab 睡眠（直近7日）カード**: 見出し行の右側（「改善余地あり」バッジの隣）に **「メッセージで触れる」** リンクボタン（`next/link`、lucide `MessageSquare` + ラベル）。`recentCount === 0` のときは出さない。遷移先は `/message?clientId=<id>&record=sleep:7d`。

**SleepTab 最近の記録（最新5件）**: 各行の右端（ソースバッジの右）にアイコンのみのリンクボタン（`MessageSquare`、`aria-label` と `title` は「この記録についてメッセージ」）。遷移先は `/message?clientId=<id>&record=sleep:<recorded_date>`。

- 両コンポーネントに `clientId?: string` を追加し、`clients/[client_id]/page.tsx` から渡す。`clientId` が無ければボタンを出さない
- スタイルはページ内の既存ボタン（`PeriodSelector` 等）に合わせた低強調のセカンダリ: `text-xs text-[#0F766E] hover:bg-[#F0FDFA] rounded-md px-2 py-1`（テキストリンク。AA コントラスト）/ 睡眠タブの行はアイコンのみ `text-[#64748B] hover:text-[#14B8A6] h-8 w-8`、`focus-visible:ring-2`。角丸 6px、グラデーション・影なし

### 4.3 メッセージ画面（`/message`）の引用チップ

`ReplyPreview` の下（textarea の上）に **`RecordQuotePreview`** を出す。

```
┌ 🌙 睡眠 9/22(火)                                   ✕ ┐
│ 【睡眠 9/22(火)】4時間12分・目覚め: だるい              │
└───────────────────────────────────────────────────────┘
[ メッセージを入力...                              ] [送信]
```

- 見た目は `ReplyPreview` と同系（`bg-[#F0FDFA] border-l-[3px] border-[#14B8A6] rounded-md p-3 mb-2`）。左に lucide `Moon`、見出しは `label`、本文は `text` を1行省略なしで表示（要約は短いので truncate 不要）
- ✕（`aria-label="引用を取り消す"`）でチップを消す。返信（`ReplyPreview`）とは独立で、両方同時に出てもよい
- 引用が用意できたら textarea にフォーカスする
- 送信ボタンの活性条件は変えない（本文か画像が必要）。引用だけの送信はできない

## 5. データフローと契約

### 5.1 `record` クエリの文法

`/message?clientId=<uuid>&record=<ref>`

| `ref` | 意味 |
| --- | --- |
| `sleep:YYYY-MM-DD` | その日付（`sleep_records.recorded_date`）の1晩 |
| `sleep:7d` | 直近7日のサマリー（SummaryTab のカードと同じ計算） |

それ以外（空・別種別・日付の形式違い）は無視する（引用なしで通常どおり会話を開く。`console.warn` のみ）。URL に載せるのは日付だけで、睡眠時間などの値は載せない。

### 5.2 メッセージ画面の状態と処理

```ts
type RecordQuote = { label: string; text: string }   // 例 { label: '睡眠 9/22(火)', text: '【睡眠 9/22(火)】4時間12分・目覚め: だるい' }
const [recordQuote, setRecordQuote] = useState<RecordQuote | null>(null)
```

1. `searchParams.get('record')` を `parseRecordQuoteRef()` で解釈する
2. `selectedClient.client_id === client_id` になったら（顧客の自動選択が済んでから）
   - `getSleepRecordsInRange(clientId, from, to)` で必要な範囲だけ取る（1晩: `from = to = 日付` / 7日: `from = 今日 - 8日, to = 今日`。8日にするのは SummaryTab の判定 `new Date(recorded_date) >= now - 7日` を同じ関数で再現し、境界で取りこぼさないため）。`今日` は **ローカル日付**（`format(now, 'yyyy-MM-dd')`）。UTC 日付にすると JST 0:00〜9:00 は当日の記録が `.lte` から漏れ、SummaryTab と数字がずれる
   - `buildSleepQuote(ref, records, now)` で `RecordQuote | null` を作り、`setRecordQuote`。null なら何もしない
   - **取得中に顧客が切り替わったら結果を捨てる**: 栄養サマリーの effect と同じ `cancelled` フラグ（cleanup で true）に加え、`set` と `replace` の直前に `selectedClientRef.current?.client_id === clientId` を照合する。`/message?clientId=X&record=…` に着地して fetch 完了前にサイドバーで Y を選ぶと、遅れて解決した fetch が X の引用を出してしまうため（`client_id` は不変なので再選択も起きない）。React StrictMode の二重実行対策も兼ねる
   - 消費したら `router.replace(\`/message?clientId=${encodeURIComponent(clientId)}\`)` でクエリから `record` を落とす（再読み込みで引用が復活しない。同じ URL なので `client_id` の effect は再実行されない）。`{ scroll: false }` を渡す（既定ではナビゲーション確定時に Next がページ先頭へスクロール／フォーカスしようとするため。引用チップと textarea のフォーカスを保つ）
3. 送信時: `content = composeMessageContent(recordQuote?.text, input)`（`text + '\n' + input.trim()`。引用が無ければ `input` のまま）。楽観表示の `newMsg.content` と `lastMessages` の本文も合成後の値にする
4. 送信成功で `setRecordQuote(null)`。顧客を切り替えたら `setRecordQuote(null)`（`selectedClient.client_id` の変化で）

### 5.3 引用文（純関数、`src/lib/sleep/sleepQuote.ts`）

- 1晩: `【睡眠 M/d(曜)】{時間}・目覚め: {評価}`
  - `時間` = `total_sleep_minutes` を `H時間M分`（ゼロ埋めなし。例 `4時間12分`・`7時間5分`。分が 0 なら `7時間`、60分未満は `45分`、0 分は `0分`）。null なら省く
  - `評価` = `WAKEUP_RATING_OPTIONS[wakeup_rating]`（だるい / まあまあ / すっきり）。null なら省く
  - 両方 null は DB 制約上あり得ないが、その場合は null を返す（引用しない）
- 7日: `【睡眠 直近7日】平均 {H時間M分}・目覚め評価 {x.x}/3・記録 {n}日`（平均は分に丸めてから同じ書式）
  - 数値は `summarizeRecentSleep()` の結果。`avgMinutes`（分。時間に直してから戻すと丸めがずれるので分のまま丸める）/ `avgWakeupRating` が null の項は省く。`recentCount === 0` は null
- `label`: `睡眠 M/d(曜)` / `睡眠 直近7日`
- 曜日は `date-fns` の `format(parseISO(date), 'M/d(E)', { locale: ja })`

### 5.4 7日サマリー（純関数、`src/lib/sleep/sleepSummary.ts`）

`summarizeRecentSleep(records: readonly SleepRecord[], now = new Date(), days = 7): RecentSleepSummary`（`readonly` フィールド `avgMinutes` / `avgHours` / `avgWakeupRating` / `hasWarning` / `recentCount`。返り値は `Object.freeze` 済み）

`SummaryTab` の `useMemo` の中身をそのまま移す（`new Date(r.recorded_date) >= now - days`、null を除いた平均、`avgHours < 6 || avgWakeupRating <= 1.5` で警告）。`SummaryTab` はこの関数を呼ぶだけにする。

### 5.5 クエリの解釈とリンク生成（純関数、`src/lib/message/recordQuoteRef.ts`）

```ts
type RecordQuoteRef = { kind: 'sleep_night'; date: string } | { kind: 'sleep_week' }
parseRecordQuoteRef(param: string | null): RecordQuoteRef | null   // 'sleep:2026-09-22' / 'sleep:7d' のみ。日付は \d{4}-\d{2}-\d{2} かつ有効な暦日
formatRecordQuoteRef(ref): string                                   // 逆変換
recordQuoteHref(clientId, ref): string                              // `/message?clientId=…&record=…`（encodeURIComponent）
```

### 5.6 取得関数（`src/lib/supabase/getSleepRecordsInRange.ts`）

既存 `getSleepRecords` と同じ流儀（browser client・RLS 委任・`select('*')`）。`.gte('recorded_date', from).lte('recorded_date', to).order('recorded_date', { ascending: false })`。RLS は既存の `sleep_records_trainer_select` で担当トレーナーのみ読める。日付は `'yyyy-MM-dd'`（`date` 列なので時刻の混入はない。lessons の「timestamptz を素の日付で `.lte` すると終了日が漏れる」は該当しない）。

### 5.7 本文合成（純関数、`src/lib/message/composeMessageContent.ts`）

`composeMessageContent(quoteText: string | null | undefined, input: string): string` → 引用があれば `${quoteText}\n${input.trim()}`、なければ `input`（既存挙動を変えない）。

## 6. エラー処理

- 睡眠の取得に失敗 → `console.error`、引用なしで会話は開く（送信機能は影響を受けない）
- 記録が無い / `record` が不正 → 引用なし、警告ログのみ。トーストは出さない（トレーナーは会話に着地しているので致命的ではない）
- 送信失敗時は既存どおり alert。引用チップは残す（再送できるように）

## 7. テスト

vitest（node）。既存の `recordLog.test.ts` の流儀（フィクスチャ関数）に合わせる。

| ファイル | 観点 |
| --- | --- |
| `src/lib/sleep/sleepSummary.test.ts` | 空配列 / 7日境界（含む・含まない）/ null 混在の平均 / 警告閾値（6h 未満・1.5 以下・両方 null）/ `now` 固定 |
| `src/lib/sleep/sleepQuote.test.ts` | 1晩（両方あり / 時間のみ / 評価のみ / 60分未満）/ 7日（通常 / 記録なしで null / 一方 null で項を省く）/ 曜日と日付の書式 |
| `src/lib/message/recordQuoteRef.test.ts` | `sleep:YYYY-MM-DD` / `sleep:7d` / 不正（空・`weight:…`・`sleep:2026-13-40`・`sleep:`）/ `recordQuoteHref` のエンコード |
| `src/lib/message/composeMessageContent.test.ts` | 引用あり / なし / 入力の前後空白 |

UI（サイドパネルのボタン・チップ・顧客詳細のリンク）はコンポーネントテスト基盤が無いため、`chrome-web-qa` でブラウザ確認する。ログインが要るのでオーナー実施の可能性あり。

## 8. 変更ファイル

新規:
- `src/lib/sleep/sleepSummary.ts` / `.test.ts`
- `src/lib/sleep/sleepQuote.ts` / `.test.ts`
- `src/lib/message/recordQuoteRef.ts` / `.test.ts`
- `src/lib/message/composeMessageContent.ts` / `.test.ts`
- `src/lib/supabase/getSleepRecordsInRange.ts`
- `src/components/message/RecordQuotePreview.tsx`

変更:
- `src/components/message/RecordSidePanel.tsx`（`onReplyStart` prop とボタン）
- `src/app/(user_console)/message/page.tsx`（`record` の解釈・`recordQuote` 状態・チップ・本文合成・`onReplyStart` の受け渡し）
- `src/app/(user_console)/clients/[client_id]/_components/SummaryTab.tsx`（サマリー計算の切り出し・リンクボタン・`clientId` prop）
- `src/app/(user_console)/clients/[client_id]/_components/SleepTab.tsx`（行のリンクボタン・`clientId` prop）
- `src/app/(user_console)/clients/[client_id]/page.tsx`（`clientId` を渡す）
- `docs/tasks/IMPLEMENTATION_TASKS.md`（9.2 を完了に、9.3 を MVP 完了に）

## 9. 将来の拡張との継ぎ目

- **拡張1**（チャートのデータ点クリック）: `recordQuoteHref(clientId, { kind: 'sleep_night', date })` を呼ぶだけ
- **拡張2**（`record_ref`）: 送信時に `metadata.record_ref = { type: 'sleep_record', date, summary: recordQuote.text }` を添える。レジストリ文書の新設と Mobile のカード描画が前提。本文の平文引用は旧アプリ向けのフォールバックとしてそのまま残せる
- **9.1 睡眠悪化アラート**: アラート行の「メッセージで触れる」も `sleep:7d` のリンクに乗せられる
