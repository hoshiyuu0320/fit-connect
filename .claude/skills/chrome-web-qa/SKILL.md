---
name: chrome-web-qa
description: |
  Web QA - コード変更後のWebアプリ動作確認スキル。
  fit-connect（Next.js Trainer Web App）の実装タスク完了後に、
  Claude デスクトップアプリの内蔵ブラウザ（mcp__Claude_Browser__*）で devサーバーを起動・表示し、
  開発用「テストログイン」ボタンでログインして、ブラウザ上で画面操作・動作検証を行う。
  ユーザーの Chrome やそのログイン状態には触れない（Chrome での確認を明示的に頼まれた時のみ Claude in Chrome を使う）。

  以下の場面で必ず使用すること:
  - Next.jsコードの実装・修正が完了した時（ユーザーの指示を待たず自動実行）
  - UIの変更をブラウザで確認したい時
  - 「動作確認して」「テストして」「ブラウザで確認」と言われた時
  - 実装タスクの完了報告前の最終チェック
  - 「devサーバーで確認」「画面確認して」と言われた時
  - fit-connect（Web側）に関する動作検証全般

  重要: サブエージェントによるコード変更完了後は、ユーザーから「確認不要」「スキップして」と
  指示されない限り、自動的にこのスキルを実行すること。
---

# Web QA Skill（内蔵ブラウザ）

コード変更後に Claude デスクトップアプリの **内蔵ブラウザ**（`mcp__Claude_Browser__*`）で Next.js devサーバーを起動・表示し、
開発用「テストログイン」でログインして動作確認を行うスキル。
不具合発見時はスクリーンショット・コンソールログを記録し、Explore エージェントに調査を委託する。

## 全体フロー

```
1. テスト計画の作成（変更内容に基づく）
2. devサーバー起動 & 内蔵ブラウザで表示（preview_start name: "web"）
3. ログイン状態の判定 & テストログイン
4. 内蔵ブラウザで各テスト項目を実行
5. 不具合発見時 → スクリーンショット + コンソールログ → Explore エージェントに調査委託
6. 結果レポート
```

## 前提・共通ルール

- 作業ディレクトリ: リポジトリルート。Webアプリはリポジトリルート直下の `fit-connect/`
- devサーバーはリポジトリルートの `.claude/launch.json` の構成 **`web`**（`npm --prefix fit-connect run dev`、ポート 3000）で起動する
- 既定のブラウザは **内蔵ブラウザ**（Claude デスクトップアプリのブラウザペイン）。ユーザーの Chrome とは分離されており、Chrome のログイン状態・Cookie には触れない
- 内蔵ブラウザのツール（`mcp__Claude_Browser__*`）は最初からロード済み。**ToolSearch は不要**
- 内蔵ブラウザは **セッション（ログイン状態）を実行間で保持する**。毎回ログインする前に、まずログイン状態を確認する
- `.env*` ファイルは **読まない**（`fit-connect/.env.local` も含む）
- パスワード等の認証情報は **絶対に自分で入力しない**。ログインは「テストログイン」ボタンのクリックのみで行う

## Step 1: テスト計画の作成

変更されたファイル・機能に基づいてテスト項目を作成する。

### テスト項目の構成

各テスト項目には以下を含める:

| 項目 | 内容 |
|------|------|
| ID | T-001, T-002, ... |
| 対象ページ/画面 | ダッシュボード、顧客管理、メッセージ、レポート、チケット、スケジュール、設定 |
| 操作手順 | 具体的なクリック・入力・ナビゲーションの手順 |
| 期待結果 | 正常時に表示されるべき内容 |
| 優先度 | High / Medium / Low |

### テスト項目の決め方

1. **変更したファイルのgit diffを確認** — 何が変わったかを把握
2. **直接影響するページ** — 変更したComponent/Page/Storeが表示されるページ
3. **間接影響するページ** — 変更したAPIやStoreに依存する他のページ
4. **回帰テスト** — 基本的なナビゲーション（全サイドバーメニュー遷移）が壊れていないか

### テスト項目テンプレート

```markdown
## テスト計画: [変更内容の要約]

### 直接テスト
- [ ] T-001: [変更したページ]を開き、[変更内容]が正しく表示されることを確認
- [ ] T-002: [変更した機能]を操作し、期待通り動作することを確認

### 回帰テスト
- [ ] T-R01: サイドバーメニュー全項目（ダッシュボード→顧客管理→メッセージ→レポート→チケット→スケジュール→設定）の遷移確認
- [ ] T-R02: ページがクラッシュ（エラー画面）せず安定表示されること
- [ ] T-R03: （レイアウト変更時）モバイル幅（resize_window preset: mobile）で崩れないこと
```

## Step 2: devサーバー起動 & 内蔵ブラウザで表示

### 2-1. preview_start で起動（既に起動済みなら再利用）

```
mcp__Claude_Browser__preview_start:
  name: "web"
```

- `.claude/launch.json` の `web` 構成で devサーバーを起動し（起動済みなら再利用）、内蔵ブラウザで `http://localhost:3000` のタブを開く
- 結果に含まれる **serverId** を記録しておく（ログ確認・停止に使う）
- 手動の `npm run dev` / `curl` による起動確認は不要。Bash で devサーバーを起動しないこと

### 2-2. サーバーログの確認

ビルドエラーやサーバー側の例外を確認したい時:

```
mcp__Claude_Browser__preview_logs:
  serverId: <serverId>
  level: error        # エラー行のみ。全体を見るなら all
```

起動済みサーバー一覧は `mcp__Claude_Browser__preview_list` で確認できる。

### 2-3. 停止（必要な場合のみ）

```
mcp__Claude_Browser__preview_stop:
  serverId: <serverId>
```

通常は QA 後も起動したままでよい（次回の preview_start で再利用される）。

## Step 3: ログイン状態の判定 & テストログイン

ページ表示後、`read_page`（`filter: "interactive"`）または `get_page_text` で画面を確認する。

### 判定基準

| 表示内容 | 状態 | 対応 |
|----------|------|------|
| サイドバーに「ダッシュボード」「顧客管理」等のメニュー | **ログイン済み** | → Step 4 へ進む |
| 「おかえりなさい」+ 「Googleでログイン」等のログインフォーム | **ログイン画面**（未ログイン） | → 下記「テストログイン」へ |
| ランディングページ（マーケティング画面） | **未ログイン** | → `/login` へ遷移してテストログイン |
| その他のエラー画面 | **エラー** | → `preview_logs` / `read_console_messages` で原因調査 |

### A) テスト対象がログイン不要の画面の場合

ログイン画面やランディングページ自体が変更対象であれば、そのままテストを実行できる。
ログイン済みでログイン画面を確認したい場合は、設定画面等からログアウトしてから確認する。

### B) テストログイン（ログイン必須の画面の場合）

`/login` の開発用「**テストログイン**」ボタンを使う（`fit-connect/src/components/auth/DevLoginButton.tsx`）。

1. `navigate` で `http://localhost:3000/login` を開く
2. `find` で「テストログイン」を検索し、ref を取得
3. `computer` の `left_click`（ref 指定）でクリック
4. `computer` の `wait` で 2 秒程度待機
5. URL が `/dashboard` になり、挨拶（現在のテストデータでは「こんにちは、テストトレーナーさん！」。時間帯により「おはようございます」「こんばんは」に変わる）が表示されることを `get_page_text` 等で確認
6. → Step 4 へ進む

`browser_batch` でまとめて実行する例:

```
mcp__Claude_Browser__browser_batch:
  actions:
    - name: navigate
      input: { url: "http://localhost:3000/login" }
    - name: find
      input: { query: "テストログイン" }
```

→ 返った ref で:

```
mcp__Claude_Browser__browser_batch:
  actions:
    - name: computer
      input: { action: left_click, ref: <ref_N>, action_summary: "テストログインボタンをクリック" }
    - name: computer
      input: { action: wait, duration: 2 }
    - name: get_page_text
      input: {}
```

### 「テストログイン」ボタンが表示されない場合

このボタンは `next dev`（development）かつ `fit-connect/.env.local` に
`NEXT_PUBLIC_DEV_LOGIN_EMAIL` と `NEXT_PUBLIC_DEV_LOGIN_PASSWORD` の両方が設定されている時のみ表示される。
`.env.local` は読まずに、ユーザーへ設定を依頼する:

```
ユーザーへのメッセージ:
「ログイン画面に開発用『テストログイン』ボタンが表示されていません。
fit-connect/.env.local に、テスト用トレーナーアカウントの
NEXT_PUBLIC_DEV_LOGIN_EMAIL と NEXT_PUBLIC_DEV_LOGIN_PASSWORD を設定してください。
設定後は devサーバーの再起動が必要です。完了したら教えてください。」
```

設定後は `preview_stop` → `preview_start`（name: "web"）で devサーバーを再起動する。

### 禁止事項

- **Googleログインを既定のログイン手段として使わない**（Googleログイン自体のテストをユーザーに明示的に頼まれた場合を除く。その場合もパスワード入力はユーザーに依頼する）
- メールアドレス・パスワードをフォームに入力しない
- `.env*` ファイルを読まない

## Step 4: 内蔵ブラウザによる動作確認

### 使用ツールの概要（`mcp__Claude_Browser__` プレフィックス）

| ツール | 用途 |
|--------|------|
| `navigate` | URL を開く。`"back"` / `"forward"` で履歴移動。同じ URL でリロード |
| `read_page` | アクセシビリティツリーを取得（`filter: "interactive"`、`depth` で絞り込み）。各要素に `ref_N` が付く |
| `find` | テキスト・ロールで要素を検索し `ref_N` を返す |
| `get_page_text` | ページの表示テキストを取得（表示内容の照合に便利） |
| `computer` (screenshot) | スクリーンショット撮影。通常は `scale: 0.5` でトークン節約 |
| `computer` (left_click) | 要素をクリック（`ref` 指定推奨。`action_summary` を必ず付ける） |
| `computer` (type) | フォーカス中の要素へテキスト入力（`action_summary` 付き） |
| `computer` (scroll) | スクロール操作（`coordinate` + `scroll_direction`） |
| `computer` (wait) | 画面遷移やデータ読み込みの待機（`duration` 秒） |
| `form_input` | フォーム要素への入力（テキスト、セレクト、チェックボックス等。`ref` 指定） |
| `read_console_messages` | ブラウザのコンソール出力（`onlyErrors: true` でエラーのみ） |
| `read_network_requests` | ネットワークリクエスト一覧（`urlPattern` で絞り込み、`requestId` でレスポンス本文） |
| `resize_window` | `preset: mobile` / `tablet` でレスポンシブ確認。**終わったら必ず `preset: desktop` に戻す** |
| `javascript_tool` | `action: javascript_exec` でページ内 JS を実行。**状態の調査専用**（UI を書き換える用途に使わない） |
| `browser_batch` | 上記ツールを複数ステップ 1 回の呼び出しで順次実行（途中でエラーなら停止） |

### サイドバーナビゲーション

アプリの左サイドバーには以下のメニューがある（`fit-connect/src/app/(user_console)/layout.tsx`）:

| メニュー | パス |
|----------|------|
| ダッシュボード | /dashboard |
| 顧客管理 | /clients |
| メッセージ | /message |
| レポート | /report |
| チケット | /tickets |
| スケジュール | /schedule |
| 設定 | /settings |

メニュー遷移は `find` でメニュー項目を探して `left_click` するか、`navigate` でURLを直接指定する。

### 操作のコツ

- **操作前に read_page / get_page_text / screenshot** — 必ず最新の状態を確認してから操作
- **find + ref で要素を特定** — 座標クリックより ref 指定のほうが確実。座標で押す場合は直前のスクリーンショットの座標系を使う
- **画面遷移後は1-2秒待機** — `computer` の `wait` で待ってから次の操作
- **大きなページはdepthを制限** — `read_page` の `depth` を5程度にしてコンテキスト節約
- **インタラクティブ要素のフィルタ** — `read_page` の `filter: "interactive"` でボタン・リンク・入力のみ取得
- **先が読める操作は browser_batch でまとめる** — 例: navigate → wait → get_page_text → screenshot
- **テキスト確認は get_page_text / read_page を優先** — スクリーンショットは見た目（レイアウト・色・崩れ）の確認時に使う

### テスト実行の進め方

テスト計画の各項目について:

1. 対象ページに遷移（サイドバークリック or navigate）
2. 1-2秒待機（`computer` wait）
3. `read_page` / `get_page_text` / `screenshot` で画面状態を確認
4. 期待結果と照合（必要に応じて `read_console_messages` でエラーが無いことも確認）
5. 問題なければ次のテスト項目へ
6. 問題があれば → Step 5 へ

## Step 5: 不具合発見時の対応

### 5-1. 証拠の保存

不具合を発見したら、スクリーンショットを撮影する:

```
mcp__Claude_Browser__computer:
  action: screenshot
  scale: 0.5
```

どのテスト項目・どの画面のスクリーンショットかを記録しておく。

### 5-2. コンソールログ・ネットワーク・サーバーログの確認

```
mcp__Claude_Browser__read_console_messages:
  onlyErrors: true

mcp__Claude_Browser__read_network_requests:
  urlPattern: "supabase"     # API 失敗が疑われる場合。例: "/api/" や "supabase"

mcp__Claude_Browser__preview_logs:
  serverId: <serverId>
  level: error
```

### 5-3. 不具合の記録

以下の情報をまとめる:

```markdown
## 不具合レポート: [不具合ID]

- **発見ページ**: [ページ名/パス]
- **操作手順**: [再現手順]
- **期待結果**: [本来表示されるべき内容]
- **実際の結果**: [実際に起きたこと]
- **スクリーンショット**: [どの画面で撮影したか]
- **コンソールエラー**: [エラーがあれば]
- **ネットワーク/サーバーログ**: [失敗したリクエスト・サーバー例外があれば]
```

### 5-4. Explore エージェントに調査を委託

不具合の原因調査を Explore エージェントに委託する。

```
Agent:
  subagent_type: Explore
  prompt: |
    fit-connect Webアプリで以下の不具合が発生しています。原因を調査してください。

    ## 不具合内容
    [不具合の詳細]

    ## 発生ページ
    [ページ名・パス]

    ## 再現手順
    [操作手順]

    ## 期待結果 vs 実際の結果
    - 期待: [...]
    - 実際: [...]

    ## コンソールエラー / サーバーログ
    [あれば記載]

    ## 調査のヒント
    - 変更されたファイル: [git diff で確認した変更ファイル一覧]
    - 関連しそうなComponent/Store: [推測される関連コード]

    プロジェクトルート: fit-connect/（リポジトリルート相対）
    共有Supabase設定: supabase/（リポジトリルート相対）
    .env* ファイルは読まないこと。
```

### 5-5. 調査結果に基づく修正

Explore エージェントの調査結果を受けて:
1. 原因箇所を特定
2. 修正が必要なら適切なサブエージェント（nextjs-ui, zustand等）に修正を委託
3. 修正後、`navigate` でページをリロードして再テスト（ホットリロードで反映されない場合は `preview_stop` → `preview_start`）

## Step 6: 結果レポート

全テスト項目の実行が完了したら、結果をまとめて報告する。

```markdown
## QA結果レポート

### テスト環境
- ブラウザ: Claude 内蔵ブラウザ（Chrome で確認した場合は Chrome）
- URL: http://localhost:3000
- ビルド: Development (next dev)
- ログイン: テストログイン（開発用）

### テスト結果サマリー
- 合格: X / Y 項目
- 不合格: Z 項目
- スキップ: W 項目

### 不合格項目の詳細
| ID | 内容 | ステータス | 備考 |
|----|------|-----------|------|
| T-001 | ... | FAIL | [不具合内容] |

### スクリーンショット
- [撮影した画面の一覧]
```

## 代替: Claude in Chrome（ユーザーが Chrome での確認を明示的に求めた場合のみ）

ユーザーが「Chromeで確認して」等と明示した場合に限り、Claude in Chrome（`mcp__claude-in-chrome__*`、ユーザーの実際の Chrome とそのログイン状態を使う）で確認する。

- ツールは遅延ロード。必要なものを **1 回の ToolSearch でまとめてロード**する:
  `select:mcp__claude-in-chrome__tabs_context_mcp,mcp__claude-in-chrome__tabs_create_mcp,mcp__claude-in-chrome__navigate,mcp__claude-in-chrome__computer,mcp__claude-in-chrome__read_page,mcp__claude-in-chrome__find,mcp__claude-in-chrome__read_console_messages`
- `tabs_context_mcp` で接続確認後、**新しいタブを作成**して作業し、ユーザーの既存タブは操作しない
- devサーバーは Step 2 と同じく `preview_start`（name: "web"）で起動しておき、Chrome で `http://localhost:3000` を開く
- ログインは同じく「テストログイン」ボタンを使う（パスワード入力はしない）
- 「No Chrome extension connected.」の場合は、Chrome の起動と拡張機能「Claude in Chrome」が有効かをユーザーに確認してもらう

## トラブルシューティング

### preview_start で devサーバーが起動しない

1. `preview_logs`（serverId 指定）でエラー内容を確認
2. 依存関係が無い場合はインストール（リポジトリルートから）:

```bash
ls fit-connect/node_modules/.package-lock.json || npm --prefix fit-connect install
```

3. ポート3000が別プロセスに使われていないか確認:

```bash
lsof -ti:3000
```

`preview_start` 以外で起動した devサーバーが残っている場合は、ユーザーに確認してから停止する。

### ページが真っ白 / エラー画面

1. `read_console_messages`（`onlyErrors: true`）でJSエラーを確認
2. `preview_logs` で devサーバー側のエラーを確認
3. `navigate` で同じURLを開き直してリロード

### 「テストログイン」ボタンが表示されない

Step 3「テストログインボタンが表示されない場合」を参照。`.env.local` 設定後は devサーバーの再起動が必要。

### テストログインが失敗する（「テストログインに失敗しました」アラート）

`read_console_messages` で `[DevLoginButton]` のエラーを確認し、設定されたテストアカウントが Supabase に存在するか・メール/パスワードが正しいかをユーザーに確認してもらう（値は聞き出さない・入力しない）。

### 内蔵ブラウザが別ユーザーでログインしている

内蔵ブラウザはセッションを保持する。ダッシュボードの挨拶（「〜、テストトレーナーさん！」）でユーザーを確認し、
テストトレーナー以外であればログアウトしてからテストログインし直す。

### read_page の出力が大きすぎる

- `depth` パラメータを3-5に制限
- `filter: "interactive"` でインタラクティブ要素のみ取得
- `ref_id` で特定の部分ツリーのみ取得
- 表示テキストだけで足りる場合は `get_page_text`（`max_chars` で上限指定）
