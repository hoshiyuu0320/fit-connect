---
name: ios-simulator-qa
description: |
  iOS Simulator QA - コード変更後のiOSアプリ動作確認スキル。
  fit-connect-mobileの実装タスク完了後に、`dev_login.json` 付きビルド（テストログイン有効）を
  fvm 経由でiOSシミュレータに起動し、専用ツール `mcp__Claude_Code_iOS_Simulator__control`
  （attach / screenshot / tap / swipe / text 等）で画面操作・動作検証を行う。
  computer use は使わない（最終手段のみ）。

  以下の場面で必ず使用すること:
  - Flutterコードの実装・修正が完了した時（ユーザーの指示を待たず自動実行）
  - UIの変更をシミュレータで確認したい時
  - 「動作確認して」「テストして」「シミュレータで確認」「iOSで確認」と言われた時
  - 実装タスクの完了報告前の最終チェック
  - 「ビルドして確認」「アプリを起動して」と言われた時

  Android での確認は android-emulator-qa スキルを使う。

  重要: サブエージェントによるコード変更完了後は、ユーザーから「確認不要」「スキップして」と
  指示されない限り、自動的にこのスキルを実行すること。
---

# iOS Simulator QA Skill

コード変更後に `dev_login.json` 付きビルドでiOSシミュレータにアプリを起動し、
専用ツール `mcp__Claude_Code_iOS_Simulator__control` で動作確認を行うスキル。
不具合発見時はスクリーンショットを保存し、Explore エージェントに調査を委託する。

## 全体フロー

```
1. テスト計画の作成（変更内容に基づく）
2. ライブパネルを開く（attach）→ ビルド & 起動（fvm flutter run + dev_login.json）
3. ログイン状態の判定 & テストログイン
4. 専用ツールで各テスト項目を実行
5. 不具合発見時 → スクリーンショット保存 → Explore エージェントに調査委託
6. 結果レポート
```

## 前提・共通ルール

- 作業ディレクトリ: リポジトリルート直下の `fit-connect-mobile/`（以降のコマンドはここで実行）
- Flutter は **fvm 経由** で実行する（`flutter ...` ではなく `fvm flutter ...`）
- 動作確認は **必ず `--dart-define-from-file=dev_login.json` 付きビルド** で行う
  - これでログイン画面に「テストログイン（開発用）」ボタンが表示される
  - 値はコンパイル時に埋め込まれるため **ホットリロードでは反映されない**。付け忘れたら再起動（再ビルド）すること
  - `dev_login.json` には認証情報が含まれるため **中身を読まない**。存在確認のみ: `test -f dev_login.json`
- Bundle ID: `com.fitconnect.fitConnectMobile`
- 既定のシミュレータ UDID: `CFF5D783-5EF1-45A1-ABDA-ECA48644267B`
  - 環境によって異なる場合は `xcrun simctl list devices booted` / `fvm flutter devices` で確認して置き換える

## Step 1: テスト計画の作成

変更されたファイル・機能に基づいてテスト項目を作成する。

### テスト項目の構成

各テスト項目には以下を含める:

| 項目 | 内容 |
|------|------|
| ID | T-001, T-002, ... |
| 対象タブ/画面 | ホーム、メッセージ、プラン、記録、設定 |
| 操作手順 | 具体的なタップ・スクロール・入力の手順 |
| 期待結果 | 正常時に表示されるべき内容 |
| 優先度 | High / Medium / Low |

### テスト項目の決め方

1. **変更したファイルのgit diffを確認** — 何が変わったかを把握
2. **直接影響する画面** — 変更したWidget/Screen/Providerが表示される画面
3. **間接影響する画面** — 変更したモデルやProviderに依存する他の画面
4. **回帰テスト** — 基本的なナビゲーション（全タブ遷移）が壊れていないか

### テスト項目テンプレート

```markdown
## テスト計画: [変更内容の要約]

### 直接テスト
- [ ] T-001: [変更した画面]を開き、[変更内容]が正しく表示されることを確認
- [ ] T-002: [変更した機能]を操作し、期待通り動作することを確認

### 回帰テスト
- [ ] T-R01: 全5タブ（ホーム→メッセージ→プラン→記録→設定）の遷移確認
- [ ] T-R02: アプリがクラッシュせず安定動作すること
```

## Step 2: ライブパネル & ビルド・起動

### 2-1. ライブパネルを開く（ビルドより先に）

ユーザーが画面を見られるよう、**ビルド開始前に** `attach` を呼ぶ。
シミュレータが起動済みなら即座にパネルが開く。未起動ならエラーが返るだけなので、2-2 で起動してから再度 `attach` する。

```
mcp__Claude_Code_iOS_Simulator__control:
  action: attach
  device: CFF5D783-5EF1-45A1-ABDA-ECA48644267B
```

### 2-2. シミュレータの確認・起動

```bash
# 起動中のシミュレータ
xcrun simctl list devices booted

# 未起動なら起動
xcrun simctl boot CFF5D783-5EF1-45A1-ABDA-ECA48644267B
```

### 2-3. 依存関係 & コード生成（必要な場合のみ）

pubspec の変更や `*.g.dart` / `*.freezed.dart` の再生成が必要な変更をした場合:

```bash
cd fit-connect-mobile
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

### 2-4. ビルド & 起動（標準コマンド）

```bash
cd fit-connect-mobile
test -f dev_login.json && echo "dev_login.json OK"
fvm flutter run -d CFF5D783-5EF1-45A1-ABDA-ECA48644267B --dart-define-from-file=dev_login.json
```

- `flutter run` は対話型で終了しないプロセスなので、**Bash の `run_in_background: true` で実行**する
- 出力に `Syncing files to device` などが出てアプリが起動するまで待つ（ブロックしない。Monitor 等で出力を確認）
- 起動後は `screenshot` で画面を確認する
- コード修正後はバックグラウンドの `flutter run` プロセスを止めて再実行する（ホットリロードを使う場合でも dart-define の変更は反映されない点に注意）

#### flutter run が失敗する場合（Xcode 26 互換性問題のフォールバック）

xcodebuild で直接ビルドしてから `launch` でインストール・起動する:

```bash
cd fit-connect-mobile

# DART_DEFINES（dev_login.json）を Generated.xcconfig へ書き出しておく
fvm flutter build ios --simulator --debug --config-only --dart-define-from-file=dev_login.json

cd ios

# ビルド（-sdk iphonesimulator のみ、-destination なし）
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -configuration Debug \
  -sdk iphonesimulator \
  -arch arm64 \
  -derivedDataPath /tmp/fit-connect-sim-build \
  build

cd ..

# ビルド成果物を探す
find /tmp/fit-connect-sim-build -name "Runner.app" -path "*Debug-iphonesimulator*" -type d
```

見つかった `Runner.app` を専用ツールでインストール・起動する（パネルも再アタッチされる）:

```
mcp__Claude_Code_iOS_Simulator__control:
  action: launch
  device: CFF5D783-5EF1-45A1-ABDA-ECA48644267B
  app_path: <Runner.app のパス>
```

（代替: `xcrun simctl install <UDID> <Runner.app>` → `xcrun simctl launch <UDID> com.fitconnect.fitConnectMobile`）

## Step 3: ログイン状態の判定 & テストログイン

起動後、`screenshot` で現在の画面を確認する。

### 判定基準

| 表示画面 | 状態 | 対応 |
|----------|------|------|
| 下部に5タブ（ホーム/メッセージ/プラン/記録/設定）が見える | **ログイン済み** | → Step 4 へ |
| 「FIT-CONNECT」ロゴ + 「新規登録」ボタン | **ウェルカム画面**（未ログイン） | → 下記へ |
| ログイン画面（メール入力 等） | **ログイン画面**（未ログイン） | → 下記へ |

### アプリのログイン分岐（app.dart）

- ログイン済み + `clients` 行あり → MainScreen（ホーム）
- ログイン済み + 登録途中（新規登録で招待コード入力済み） → ProfileSetupScreen
- ログイン済み + どちらでもない → アプリがサインアウトし WelcomeScreen に戻る

### A) 登録済みテストクライアントでログイン（通常はこちら）

1. ウェルカム画面で「ログインはこちら」をタップ
2. ログイン画面の「**テストログイン（開発用）**」をタップ
3. ホーム画面（5タブ）が表示されたら → Step 4 へ

「テストログイン（開発用）」ボタンが無い場合は `dev_login.json` 無しでビルドされている。Step 2-4 のコマンドで再起動すること。

### B) 新規アカウントのフロー（登録フロー自体をテストする場合）

1. ウェルカム画面で「新規登録」→ 招待コード入力 → トレーナー確認
2. 「メールアドレス認証」画面で「**テストログイン（開発用）**」をタップ
3. プロフィール設定画面（ProfileSetupScreen）へ進む

### 禁止事項

- マジックリンク（メールアドレス入力）経路は使わない
- パスワード等の認証情報は **絶対に自分で入力しない**。ログインはテストログインボタンのタップのみで行う
- Google ログイン等が必要な場合はユーザーに手動操作を依頼する

### C) ログイン不要の画面がテスト対象の場合

ウェルカム画面・ログイン画面・オンボーディング画面などが対象であれば、ログインせずにテストしてよい。

## Step 4: 専用ツールによる動作確認

### 使用ツール: `mcp__Claude_Code_iOS_Simulator__control`

| action | 用途 | 主なパラメータ |
|--------|------|----------------|
| `attach` | ライブパネルを開く（ユーザーが見られる） | `device` |
| `launch` | ビルド済み .app をインストール・起動 | `app_path`, `bundle_id`(任意) |
| `screenshot` | 現在画面の PNG を取得 | - |
| `tap` | タップ（`duration` > 0.5 で長押し） | `x`, `y` |
| `swipe` | スワイプ・スクロール | `x`, `y`, `x2`, `y2`, `duration` |
| `text` | テキスト入力（フォーカス中の入力欄へ） | `text` |
| `button` | ハードウェアボタン | `name`: HOME / LOCK / SIDE_BUTTON 等 |
| `open_url` | ディープリンクを開く | `url` |
| `detach` | パネルを閉じる | - |

- **座標はデバイスポイント**（原点は左上）。スクリーンショットから位置を読み取って指定する
  - `launch` の結果にデバイスのポイントサイズが出る。スクリーンショット画像のピクセルと異なる場合はスケールを換算する
- 画面端 4pt 以内から始まる `swipe` は OS のエッジジェスチャ（戻る・通知センター等）になる。コンテンツのスクロールは端から離して行う
- `screenshot` / 入力操作はパネルが開いていなくても動作する（パネルはユーザー向け）
- 代替のスクリーンショット取得: `xcrun simctl io <UDID> screenshot <保存パス>.png` → Read で表示

> **computer use は最終手段**。専用ツールで対応できない場合（ツールが利用不可 等）に限り使う。
> 専用ツールは Mac の画面を占有しないため、ユーザーが Mac を操作中でも検証できる。

### タブ切り替え

下部ナビゲーションバーの5タブ:

| タブ | アイコン | 位置（左から） |
|------|----------|----------------|
| ホーム | home | 1番目 |
| メッセージ | messageSquare | 2番目 |
| プラン | dumbbell | 3番目 |
| 記録 | barChart2 | 4番目 |
| 設定 | settings | 5番目 |

記録タブ内のサブタブ: 体重 / 食事 / 運動 / ノート

### 操作のコツ

- **タップ前にスクリーンショット** — 必ず最新のスクリーンショットで座標を確認してからタップ
- **待機** — 画面遷移後は1-2秒待ってからスクリーンショット
- **スクロール** — 例: 画面中央付近から `swipe`（y を大→小）で下方向へスクロール
- **テキスト入力** — 入力欄を `tap` でフォーカスしてから `text`

### テスト実行の進め方

テスト計画の各項目について:

1. 対象画面に遷移（タブタップ、ボタンタップ等）
2. 1-2秒待機
3. `screenshot` を撮影
4. 期待結果と照合
5. 問題なければ次のテスト項目へ
6. 問題があれば → Step 5 へ

## Step 5: 不具合発見時の対応

### 5-1. 証拠の保存

スクリーンショットをファイルに保存する（リポジトリ外のスクラッチ領域に保存）:

```bash
xcrun simctl io CFF5D783-5EF1-45A1-ABDA-ECA48644267B screenshot <scratchpad>/bug-T-001.png
```

あわせてバックグラウンドの `flutter run` 出力から例外・エラーログを確認する。

### 5-2. 不具合の記録

```markdown
## 不具合レポート: [不具合ID]

- **発見画面**: [タブ名/画面名]
- **操作手順**: [再現手順]
- **期待結果**: [本来表示されるべき内容]
- **実際の結果**: [実際に起きたこと]
- **スクリーンショット**: [保存パス]
- **エラーログ**: [flutter run 出力の例外等]
```

### 5-3. Explore エージェントに調査を委託

```
Agent:
  subagent_type: Explore
  prompt: |
    fit-connect-mobileアプリで以下の不具合が発生しています。原因を調査してください。

    ## 不具合内容
    [不具合の詳細]

    ## 発生画面
    [画面名・タブ名]

    ## 再現手順
    [操作手順]

    ## 期待結果 vs 実際の結果
    - 期待: [...]
    - 実際: [...]

    ## エラーログ
    [flutter run 出力の該当部分]

    ## 調査のヒント
    - 変更されたファイル: [git diff で確認した変更ファイル一覧]
    - 関連しそうなProvider/Widget: [推測される関連コード]

    プロジェクトルート: fit-connect-mobile/（リポジトリルート相対）
```

### 5-4. 調査結果に基づく修正

1. 原因箇所を特定
2. 修正が必要なら適切なサブエージェント（flutter-ui, riverpod等）に修正を委託
3. 修正後、再度ビルド & テスト（Step 2-4 からやり直し）

## Step 6: 結果レポート

```markdown
## QA結果レポート（iOS）

### テスト環境
- デバイス: [シミュレータ名 / UDID]
- iOS: [バージョン]
- ビルド: Debug（dev_login.json 付き）

### テスト結果サマリー
- 合格: X / Y 項目
- 不合格: Z 項目
- スキップ: W 項目

### 不合格項目の詳細
| ID | 内容 | ステータス | 備考 |
|----|------|-----------|------|
| T-001 | ... | FAIL | [不具合内容] |

### スクリーンショット
- [保存パス一覧]
```

## トラブルシューティング

### 「テストログイン（開発用）」ボタンが表示されない

`--dart-define-from-file=dev_login.json` 無しでビルドされている（またはホットリロードで済ませた）。
`flutter run` を停止し、Step 2-4 のコマンドで再起動する。`fit-connect-mobile/` で実行しているか、`test -f dev_login.json` も確認。

### flutter run が "Unable to find destination" で失敗する

Xcode 26 と Flutter の互換性問題。Step 2-4 のフォールバック手順（xcodebuild直接ビルド → `launch`）を使う。

### SUPPORTED_PLATFORMS の問題（Xcode 26+）

シミュレータビルドには `iphonesimulator` が `SUPPORTED_PLATFORMS` に含まれている必要がある。

```bash
grep "SUPPORTED_PLATFORMS" fit-connect-mobile/ios/Runner.xcodeproj/project.pbxproj
```

`iphoneos` のみの場合は `SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";` に修正する。

### Pod install が失敗する

```bash
cd fit-connect-mobile/ios
pod deintegrate
pod install --repo-update
cd ../..
```

### シミュレータが起動しない

```bash
xcrun simctl shutdown all
xcrun simctl boot CFF5D783-5EF1-45A1-ABDA-ECA48644267B
open -a Simulator
```

### `attach` がエラーになる

シミュレータが未起動。`xcrun simctl boot <UDID>` で起動するかビルドを先に進め、その後 `attach` を再実行する。

### ビルド成果物にRunner.appが見つからない

```bash
find ~/Library/Developer/Xcode/DerivedData -name "Runner.app" -path "*Debug-iphonesimulator*" -type d
```

### タップ位置がずれる

- 最新のスクリーンショットで座標を取り直す
- 座標はデバイスポイント。スクリーンショット画像がピクセル（@3x 等）の場合はスケールで割って換算する
