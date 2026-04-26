---
name: chrome-web-qa
description: |
  Chrome Web QA - コード変更後のWebアプリ動作確認スキル。
  fit-connect（Next.js Trainer Web App）の実装タスク完了後に、
  devサーバーを起動し、claude-in-chrome MCP を使ってブラウザ上で画面操作・動作検証を行う。

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

# Chrome Web QA Skill

コード変更後にNext.js devサーバーを起動し、claude-in-chrome MCPでブラウザ上の動作確認を行うスキル。
不具合発見時はスクリーンショットを保存し、exploreエージェントに調査を委託する。

## 全体フロー

```
1. テスト計画の作成（変更内容に基づく）
2. devサーバー起動 & ブラウザでアクセス
3. ログイン状態の判定 & 対応
4. claude-in-chromeで各テスト項目を実行
5. 不具合発見時 → スクリーンショット保存 → explore エージェントに調査委託
6. 結果レポート
```

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
```

## Step 2: devサーバー起動 & ブラウザでアクセス

### 前提条件

プロジェクトルート: `/Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect`

### 2-1. devサーバーの起動

まず既にdevサーバーが起動していないか確認する:

```bash
# ポート3000が使われているか確認
lsof -ti:3000
```

起動していなければ、バックグラウンドで起動:

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
npm run dev
```

`run_in_background: true` で実行し、数秒後にサーバーが `Ready` になったことを確認する。

### 2-2. サーバーの応答確認

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:3000
```

200が返ればOK。

### 2-3. Chrome拡張の接続確認 & タブ作成

claude-in-chromeツールを使う前に、必ずToolSearchでツールをロードすること:

```
ToolSearch: select:mcp__claude-in-chrome__tabs_context_mcp
```

接続確認:

```
mcp__claude-in-chrome__tabs_context_mcp:
  createIfEmpty: true
```

「No Chrome extension connected.」エラーが出た場合は、ユーザーに以下を依頼:

```
「Chrome拡張機能（Claude in Chrome）が接続されていません。
Chromeを起動して拡張機能が有効になっているか確認してください。」
```

### 2-4. localhost:3000 を開く

新しいタブを作成するか、既存タブでナビゲート:

```
# ツールのロード
ToolSearch: select:mcp__claude-in-chrome__navigate

# ナビゲート
mcp__claude-in-chrome__navigate:
  url: "http://localhost:3000"
  tabId: <取得したtabId>
```

## Step 3: ログイン状態の判定と対応

ページ読み込み後、`read_page` でページ内容を確認する。

### ツールのロード

初回は必ずToolSearchでツールをロード:

```
ToolSearch: select:mcp__claude-in-chrome__read_page
ToolSearch: select:mcp__claude-in-chrome__computer
ToolSearch: select:mcp__claude-in-chrome__find
```

### 判定基準

| 表示内容 | 状態 | 対応 |
|----------|------|------|
| サイドバーに「ダッシュボード」「顧客管理」等のメニュー | **ログイン済み** | → Step 4 へ進む |
| 「おかえりなさい」+ メール/パスワード入力フォーム | **ログイン画面**（未ログイン） | → 下記「ログイン対応」へ |
| その他のエラー画面 | **エラー** | → 原因調査 |

### ログイン対応

#### A) テスト対象がログイン不要の画面の場合

ログイン画面自体が変更対象であれば、そのままテストを実行できる。

#### B) テスト対象がログイン必須の画面の場合

Googleログインを使用する:

1. `find` ツールで「Googleでログイン」ボタンを探す
2. `computer` ツールの `left_click` でボタンをクリック
3. Googleアカウント選択画面が表示されたら:
   - `find` ツールでユーザー名（「星田優哉」）を検索
   - 該当アカウントを `left_click` でクリック
4. OAuth同意画面が表示されたら「次へ」をクリック
5. **パスワード入力画面が表示された場合は、ユーザーに手動入力を依頼:**

```
ユーザーへのメッセージ:
「Googleログインのパスワード入力画面が表示されました。セキュリティ上、
パスワードの入力はご自身でお願いします。ブラウザ上でパスワードを入力して
ログインしてください。完了したら教えてください。」
```

6. ダッシュボード（`/dashboard`）にリダイレクトされたことを確認
7. → Step 4 へ進む

**ポイント:** パスワード等の認証情報は絶対に自分で入力しない。アカウント選択や同意ボタンなど、認証情報を含まない操作のみ行う。

## Step 4: claude-in-chrome による動作確認

### 使用ツールの概要

| ツール | 用途 |
|--------|------|
| `read_page` | ページのアクセシビリティツリーを取得。要素の確認に使う |
| `find` | 自然言語でページ上の要素を検索（ボタン、リンク等） |
| `computer` (screenshot) | 現在の画面をスクリーンショット撮影 |
| `computer` (left_click) | 要素をクリック（ref指定またはcoordinate指定） |
| `computer` (type) | テキスト入力 |
| `computer` (scroll) | スクロール操作 |
| `computer` (wait) | 画面遷移やデータ読み込みの待機 |
| `form_input` | フォーム要素への入力（テキスト、セレクト、チェックボックス等） |

### サイドバーナビゲーション

アプリの左サイドバーには以下のメニューがある:

| メニュー | パス |
|----------|------|
| ダッシュボード | /dashboard |
| 顧客管理 | /clients |
| メッセージ | /messages |
| レポート | /reports |
| チケット | /tickets |
| スケジュール | /schedule |
| 設定 | /settings |

メニュー遷移は `find` でメニュー項目を探して `left_click` するか、`navigate` でURLを直接指定する。

### 操作のコツ

- **操作前にread_pageまたはscreenshot** — 必ず最新の状態を確認してから操作
- **find + ref で要素を特定** — テキストやロールで要素を検索し、ref_idでクリックするのが確実
- **画面遷移後は1-2秒待機** — `computer` の `wait` アクションで待ってから次の操作
- **大きなページはdepthを制限** — `read_page` の depth パラメータを5程度に設定してコンテキスト節約
- **インタラクティブ要素のフィルタ** — `read_page` の filter を "interactive" にするとボタン・リンク・入力のみ取得

### テスト実行の進め方

テスト計画の各項目について:

1. 対象ページに遷移（サイドバークリック or navigate）
2. 1-2秒待機（`computer` wait）
3. `read_page` または `screenshot` で画面状態を確認
4. 期待結果と照合
5. 問題なければ次のテスト項目へ
6. 問題があれば → Step 5 へ

## Step 5: 不具合発見時の対応

### 5-1. 証拠の保存

不具合を発見したら、スクリーンショットを保存する:

```
mcp__claude-in-chrome__computer:
  action: screenshot
  tabId: <tabId>
```

スクリーンショットIDを記録しておく。

### 5-2. コンソールログの確認

ブラウザのコンソールにエラーが出ていないか確認:

```
ToolSearch: select:mcp__claude-in-chrome__read_console_messages

mcp__claude-in-chrome__read_console_messages:
  tabId: <tabId>
  pattern: "error|Error|ERROR"
```

### 5-3. 不具合の記録

以下の情報をまとめる:

```markdown
## 不具合レポート: [不具合ID]

- **発見ページ**: [ページ名/パス]
- **操作手順**: [再現手順]
- **期待結果**: [本来表示されるべき内容]
- **実際の結果**: [実際に起きたこと]
- **スクリーンショット**: [スクリーンショットID]
- **コンソールエラー**: [エラーがあれば]
```

### 5-4. Explore エージェントに調査を委託

不具合の原因調査をexploreエージェントに委託する。

```
Agent:
  subagent_type: explore
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

    ## コンソールエラー
    [あれば記載]

    ## 調査のヒント
    - 変更されたファイル: [git diff で確認した変更ファイル一覧]
    - 関連しそうなComponent/Store: [推測される関連コード]

    プロジェクトルート: /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
```

### 5-5. 調査結果に基づく修正

exploreエージェントの調査結果を受けて:
1. 原因箇所を特定
2. 修正が必要なら適切なサブエージェント（nextjs-ui, zustand等）に修正を委託
3. 修正後、ブラウザをリロードして再テスト

## Step 6: 結果レポート

全テスト項目の実行が完了したら、結果をまとめて報告する。

```markdown
## QA結果レポート

### テスト環境
- ブラウザ: Chrome
- URL: http://localhost:3000
- ビルド: Development (next dev)

### テスト結果サマリー
- 合格: X / Y 項目
- 不合格: Z 項目
- スキップ: W 項目

### 不合格項目の詳細
| ID | 内容 | ステータス | 備考 |
|----|------|-----------|------|
| T-001 | ... | FAIL | [不具合内容] |

### スクリーンショット
- [スクリーンショットID一覧]
```

## トラブルシューティング

### Chrome拡張が接続されない

ユーザーに以下を依頼:
1. Chromeが起動しているか確認
2. `chrome://extensions` で「Claude in Chrome」が有効か確認
3. 拡張機能を一度無効→有効にしてリロード

### devサーバーが起動しない

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect

# node_modulesが存在するか確認
ls node_modules/.package-lock.json

# なければインストール
npm install

# ポート3000が既に使われていたらプロセスを確認
lsof -ti:3000
```

### ページが真っ白 / エラー画面

1. `read_console_messages` でJSエラーを確認
2. devサーバーのターミナル出力を確認
3. `navigate` でページをリロード

### Googleログインが別アカウントになる

Google OAuthのアカウント選択画面で:
1. `find` ツールで正しいユーザー名を検索
2. アカウント切り替えリンクがあれば使用
3. 同意画面のアカウント変更ドロップダウンを確認

### read_page の出力が大きすぎる

- `depth` パラメータを3-5に制限
- `filter: "interactive"` でインタラクティブ要素のみ取得
- `ref_id` で特定の部分ツリーのみ取得
