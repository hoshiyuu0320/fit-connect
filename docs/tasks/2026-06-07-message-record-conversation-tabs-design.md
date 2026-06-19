# メッセージ画面 会話／記録 表示分離 — 設計書

- **日付**: 2026-06-07
- **対象**: fit-connect（Web / Trainer）、fit-connect-mobile（Mobile / Client）、共有 Supabase
- **ステータス**: 設計合意済み（ブレスト完了）→ 実装計画（writing-plans）待ち

---

## 1. 背景・課題

メッセージ画面で、通常の会話と各種記録（食事・体重・運動）が**同一タイムラインに混在**している。

- 通常の会話中に記録を送ると、**会話が途切れる**
- 記録が**送りづらい** / 後から**記録だけ振り返りにくい**

## 2. コンセプト（死守ライン）

> **「メッセージ上で記録と報告が同時にできる」**

このアプリの核となる体験。**この一体感を壊さないことが最優先**。分離を進めるあまりコンセプトを殺してはならない。

## 3. 設計大原則

- **① 記録を"送る"のは会話と一体** — 入力欄は1つ。記録も会話も同じ場所から送る
- **② 記録を"見る"時だけ分離** — フィルタ / トグル / タブ / パネルで切り替え
- **❌ 完全分離は不採用** — 記録を別画面・別入力に追い出すとコンセプトが壊れるため、候補から除外

> この「① 送信は一体 / ② 閲覧だけ分離」が全設計の判断基準。

---

## 4. 現状（コードベース調査結果）

### 4.1 記録判定が Web / Mobile でバラバラ
- **Mobile**: `tags` カラム（例 `['#食事:朝食']`）で判定
- **Web**: `content` 本文先頭の文字列パース（`recordCardParser.ts`）で判定。`tags` カラムは未使用

### 4.2 `tags` は送信時には入らず、webhook が"後付け"している ⚠️
- 送信コード（Web/Mobile）は `tags` を一切書いていない
- Edge Function `parse-message-tags` が insert 後に**非同期で付与**
- webhook の判定正規表現は **`#食事 / #体重 / #運動` のみ**

### 4.3 ワークアウト達成メッセージは `tags` が付かない ⚠️⚠️
- `本日のワークアウトプラン「…」を達成しました！` は `#` が無いため webhook 対象外 → **`tags` 空のまま**
- Web は `recordCardParser` で記録（achievement）として表示済み
- → このまま `tags` 統一すると、**達成報告が全部「会話」に誤分類される**

### 4.4 `tags` のデフォルトは空配列 `{}`（NULLではない）
- 判定は **`cardinality(tags) > 0`** で行う（`IS NOT NULL` だけだと空配列を記録扱いして全件記録になる）

---

## 5. データ基盤設計（フェーズ1）

### 5.1 判定基準の一本化
- **記録 = `cardinality(tags) > 0` / 会話 = `tags` 空**
- Web / Mobile の「記録か会話か」判定をこの基準に統一する

### 5.2 3点セット（`tags` を"正"として機能させるための前提）
1. **送信時に `tags` を確実に付与する**
   - Mobile: 構造化フォーム（`structured_tag_form`）が生成するタグを `tags` カラムへ**直接書く**
   - Web: 送信API（`messages/send`）で記録形式なら `tags` を埋める（トレーナーは基本記録を送らないが整合のため）
   - webhook は補完/バックアップとして整理。**送信側付与により送信直後から正しく分類**され、リアルタイム表示でも分類がブレない
2. **全種類の記録をタグ対象にする**
   - 特に**ワークアウト達成**に正規タグを付与（タグ規約は実装時に決定。例: `#運動:達成`）
3. **既存データのマイグレーション**
   - `cardinality(tags)=0` かつ `content` が記録パターンのものを、`content` パースで `tags` 補完
   - 対象: webhook 導入前の記録 / ワークアウト達成 / AI食事（`metadata.meal_estimation`）漏れ
   - **規模は実装直前に本番DBで計測**（read-only SQL は調査済み・下記参照）

### 5.3 型 / モデル更新
- Web: `src/types/client.ts` の `Message` 型に `tags` を追加
- Mobile: `message_model.dart` は `tags` 対応済み
- `fit-connect/CLAUDE.md` の **古い `messages` スキーマ記述を修正**（`tags`/`metadata` 未記載・誤記あり）

---

## 6. Mobile UI 設計（フェーズ2）

### 6.1 案A: 混在ベース ＋ 切替トグル
- 画面上部にトグル **「すべて / 記録」**（デフォルト = すべて = 混在）
- フィルタ状態は **enum: `all` / `recordsOnly` / `chatOnly`** で保持
  - 案Aでは `all` / `recordsOnly` を使用。`chatOnly` は将来（案B）で有効化
- **入力欄は一体のまま**（メッセージ＋記録、全状態共通）

### 6.2 挙動
- **「記録のみ」表示中に通常メッセージを送ったら → 自動で「すべて」に戻す**（送ったものが見えないと混乱するため）
- 記録ゼロ時の**空状態**プレースホルダを用意

### 6.3 将来拡張（案B / スコープ外）
- enum に `chatOnly` を加え、トグルを **3タブ（混合 / 会話 / 記録）** に拡張
- データ層・フィルタロジックは案Aのものを流用（**作り直し不要**）

---

## 7. Web UI 設計（フェーズ3）

### 7.1 案②: 会話メイン ＋ 記録サイドパネル
- **左**: 会話（メイン。横長画面を活かして広く）
- **右**: 記録サイドパネル（**開閉式・デフォルト開**）
- トレーナーは記録を**見る側**なので、パネルは**閲覧専用**（送信フロー不要）

### 7.2 パネル中身（B＋C）
- **上部**: サマリー（今日のカロリー/PFC、体重推移のミニグラフ）
- **中部**: フィルタチップ（全 / 食事 / 体重 / 運動）
- **下部**: 記録ログ（時系列）

---

## 8. 実装フェーズ（依存順）

1. **基盤（tags 統一）** — 送信側付与・全種対応・マイグレーション・判定一本化 ← 土台
2. **Mobile** — 案A トグル
3. **Web** — 案② パネル

※ 各フェーズは別々の実装計画（plan）に分割して進められる。

## 9. スコープ外（今回はやらない / 将来）

- タブ別の未読バッジ・通知
- 記録カードから直接コメント / 返信する機能
- Mobile 案B（3タブ）への拡張（※土台となる enum は今回作る）

---

## 10. 影響を受ける主なファイル（調査済み）

### Backend（共有 Supabase）
- `supabase/functions/parse-message-tags/index.ts` — 判定の真実。全種対応・整理
- `supabase/migrations/20251230131753_remote_schema.sql` — `messages` スキーマ
- `supabase/migrations/`（新規）— 既存データの `tags` 補完マイグレーション

### Mobile（fit-connect-mobile）
- `lib/features/messages/presentation/screens/message_screen.dart` — 一覧描画・トグル設置
- `lib/features/messages/presentation/widgets/message_bubble.dart` — バブル/タグ表示
- `lib/features/messages/presentation/widgets/chat_input.dart` — 入力欄（**一体維持**）
- `lib/features/messages/presentation/widgets/structured_tag_form.dart` — 記録フォーム（tags 付与元）
- `lib/features/messages/providers/messages_provider.dart` — フィルタ enum・絞り込みロジック追加
- `lib/features/messages/models/message_model.dart` — `tags` 対応済み
- `lib/features/workout/presentation/screens/workout_screen.dart`（56行）— ワークアウト達成送信（**tags 付与が必要**）

### Web（fit-connect）
- `src/app/(user_console)/message/page.tsx` — 一覧描画・サイドパネル設置
- `src/components/message/MessageBubble.tsx` — 記録判定（→ `tags` 基準へ）
- `src/components/message/RecordCard.tsx` — 記録カードUI
- `src/components/message/recordCardParser.ts` — 記録判定（→ `tags` 基準へ寄せる）
- `src/lib/supabase/getMessages.ts` — メッセージ取得
- `src/app/api/messages/send/route.ts` — 送信API（→ `tags` 付与）
- `src/types/client.ts` — `Message` 型に `tags` 追加

---

## 11. リスク・要確認

- **マイグレーション規模が未計測** — 実装直前に本番DBで計測（DB接続情報の用意が必要。`.env` は規約で参照不可のため、`PGPASSWORD` 手動指定 or `supabase start` で対応）
- **`sender_type`** — 記録は `client` 発のみ想定。`trainer` 発の記録が存在すると、マイグレーション/付与で `client_id` 取り違えのリスク → 計測で確認
- **webhook と送信側付与の二重化** — 重複付与・競合が起きないよう整理（送信側を主、webhook を補完 or 廃止）
- **リアルタイム表示** — 送信側付与にすることで webhook 待ちによる分類ブレを解消

### 計測用 read-only SQL（規模確認・実装直前に実行）
`messages` テーブルに対し、以下を確認:
- 全件数 / `cardinality(tags)>0` の件数 / `tags` 空の件数
- `tags` 空 かつ `content` が記録パターン（`#食事%` / `#体重%` / `#運動%` / `本日のワークアウトプラン…達成しました`）の件数 = **マイグレーション対象規模**（種類別内訳）
- `sender_type` 別の記録件数（trainer 発の有無）
- `metadata ? 'meal_estimation'` の件数

## 12. テスト方針

- 判定ロジック（`cardinality(tags) > 0`）のユニットテスト
- マイグレーションのドライラン（対象件数の事前確認）
- Mobile: フィルタ切替・「記録のみ時の送信で自動解除」の Widget/統合テスト → **ios-simulator-qa**
- Web: パネル開閉・フィルタ・サマリー表示の動作確認 → **chrome-web-qa**
