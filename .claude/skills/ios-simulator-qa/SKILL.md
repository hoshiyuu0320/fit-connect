---
name: ios-simulator-qa
description: |
  iOS Simulator QA - コード変更後のiOSアプリ動作確認スキル。
  fit-connect-mobileの実装タスク完了後に、iOSシミュレータ上でアプリをビルド・インストールし、
  computer useを使って画面操作・動作検証を行う。
  
  以下の場面で必ず使用すること:
  - Flutterコードの実装・修正が完了した時（ユーザーの指示を待たず自動実行）
  - UIの変更をシミュレータで確認したい時
  - 「動作確認して」「テストして」「シミュレータで確認」と言われた時
  - 実装タスクの完了報告前の最終チェック
  - 「ビルドして確認」「アプリを起動して」と言われた時
  
  重要: サブエージェントによるコード変更完了後は、ユーザーから「確認不要」「スキップして」と
  指示されない限り、自動的にこのスキルを実行すること。
---

# iOS Simulator QA Skill

コード変更後にiOSシミュレータでアプリをビルド・インストールし、computer useで動作確認を行うスキル。
不具合発見時はスクリーンショットを保存し、exploreエージェントに調査を委託する。

## 全体フロー

```
1. テスト計画の作成（変更内容に基づく）
2. ビルド & シミュレータインストール
3. ログイン状態の判定 & 対応
4. computer useで各テスト項目を実行
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

## Step 2: ビルド & シミュレータインストール

### 前提条件

プロジェクトルート: `/Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile`

### ビルド手順

以下の手順を順番に実行する。各ステップでエラーが出たら次に進まず原因を調査すること。

#### 2-1. 依存関係インストール & コード生成

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile

# 依存関係取得
flutter pub get

# Riverpod/JSON Serializableコード生成
dart run build_runner build --delete-conflicting-outputs
```

#### 2-2. iOSシミュレータの起動

```bash
# 利用可能なシミュレータ一覧
xcrun simctl list devices available | grep iPhone

# iPhone 16 Pro (iOS 18.6) を起動（環境依存、利用可能なデバイスを選ぶ）
xcrun simctl boot <DEVICE_UDID>

# Simulator.appを前面に
open -a Simulator
```

**デバイス選択の優先順位:**
1. iOS 18.x 系の iPhone シミュレータ（安定）
2. 最新iOS のシミュレータ（Xcode beta との互換性問題に注意）

#### 2-3. SUPPORTED_PLATFORMS の確認

Xcode 26+ 環境では、シミュレータビルドに `iphonesimulator` が `SUPPORTED_PLATFORMS` に含まれている必要がある。

```bash
grep "SUPPORTED_PLATFORMS" ios/Runner.xcodeproj/project.pbxproj
```

もし `iphoneos` のみの場合、`"iphoneos iphonesimulator"` に修正する:

```
SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
```

#### 2-4. Pod インストール

```bash
cd ios
pod install
cd ..
```

#### 2-5. Flutter でビルド & 実行

```bash
flutter run -d <DEVICE_UDID>
```

**flutter run が失敗する場合（Xcode 26 互換性問題）:**

xcodebuildで直接ビルドしてから手動インストールする:

```bash
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

# シミュレータにインストール
xcrun simctl install <DEVICE_UDID> <Runner.app のパス>

# アプリを起動
xcrun simctl launch <DEVICE_UDID> com.fitconnect.fitConnectMobile
```

#### 2-6. ビルド成功の確認

シミュレータでアプリが起動したことを確認する。
起動直後はウェルカム画面またはホーム画面が表示される（ログイン状態による）。

## Step 3: ログイン状態の判定と対応

アプリ起動後、スクリーンショットを撮って現在の画面を確認する。

### 判定基準

| 表示画面 | 状態 | 対応 |
|----------|------|------|
| 下部に5タブ（ホーム/メッセージ/プラン/記録/設定）が見える | **ログイン済み** | → Step 4 へ進む |
| 「FIT-CONNECT」ロゴ + 「新規登録」ボタン | **ウェルカム画面**（未ログイン） | → 下記「未ログイン時の対応」へ |
| 「メールアドレスを入力」+ 「Googleでログイン」 | **ログイン画面**（未ログイン） | → 下記「未ログイン時の対応」へ |

### 未ログイン時の対応

#### A) テスト対象がログイン不要の画面の場合

ウェルカム画面・ログイン画面・オンボーディング画面など、認証前の画面が変更対象であれば、
そのままログインせずにテストを実行できる。

**テスト可能な画面:**
- ウェルカム画面（WelcomeScreen）
- ログイン画面（LoginScreen）
- オンボーディング画面（OnboardingScreen）

#### B) テスト対象がログイン必須の画面の場合

ホーム、メッセージ、プラン、記録、設定タブの確認にはログインが必要。

**対応手順:**

1. Googleログインボタンをタップしてフローを開始する
2. Google OAuth のダイアログ（「"fit_connect_mobile" がサインインのために "google.com" を使用しようとしています」）が出たら「続ける」をタップ
3. **Google のログインフォームが表示されたら、ユーザーに手動入力を依頼する:**

```
ユーザーへのメッセージ:
「Googleログイン画面が表示されました。セキュリティ上、パスワードの入力は
ご自身でお願いします。シミュレータ上でメールアドレスとパスワードを入力して
ログインしてください。完了したら教えてください。」
```

4. ユーザーがログイン完了を報告したら、スクリーンショットを撮ってホーム画面が表示されていることを確認
5. → Step 4 へ進む

**ポイント:** パスワード等の認証情報は絶対に自分で入力しない。OAuth フローの「続ける」ボタンなど、認証情報を含まない操作のみ行う。

## Step 4: Computer Use による動作確認

### 準備

1. **Simulator アプリへのアクセス許可を取得**

```
mcp__computer-use__request_access:
  apps: ["Simulator"]
  reason: "iOSアプリの動作確認のためシミュレータを操作します"
```

2. **スクリーンショットを撮って現在の状態を確認**

```
mcp__computer-use__screenshot
```

### 操作パターン

#### タブ切り替え

アプリの下部ナビゲーションバーには5つのタブがある:

| タブ | アイコン | 位置（左から） |
|------|----------|----------------|
| ホーム | home | 1番目 |
| メッセージ | messageSquare | 2番目 |
| プラン | dumbbell | 3番目 |
| 記録 | barChart2 | 4番目 |
| 設定 | settings | 5番目 |

タブをタップするには、スクリーンショットで下部バーの位置を確認してから `left_click` する。

#### 記録タブのサブタブ

記録タブ内には4つのサブタブがある:
- 体重 / 食事 / 運動 / ノート

#### 操作のコツ

- **クリック前にスクリーンショット** — 必ず最新のスクリーンショットでUI位置を確認してからクリック
- **ズームで確認** — 小さいテキストやボタンは `mcp__computer-use__zoom` で拡大して確認
- **待機** — 画面遷移後は1-2秒待ってからスクリーンショット
- **シミュレータの外をクリックしない** — 座標がシミュレータ画面外に当たると別アプリがフォーカスされる

### テスト実行の進め方

テスト計画の各項目について:

1. 対象画面に遷移（タブタップ、ボタンタップ等）
2. 1-2秒待機
3. スクリーンショットを撮影
4. 期待結果と照合
5. 問題なければ次のテスト項目へ
6. 問題があれば → Step 5 へ

## Step 5: 不具合発見時の対応

### 5-1. 証拠の保存

不具合を発見したら、スクリーンショットを保存する:

```
mcp__computer-use__screenshot:
  save_to_disk: true
```

保存されたパスを記録しておく。

### 5-2. 不具合の記録

以下の情報をまとめる:

```markdown
## 不具合レポート: [不具合ID]

- **発見画面**: [タブ名/画面名]
- **操作手順**: [再現手順]
- **期待結果**: [本来表示されるべき内容]
- **実際の結果**: [実際に起きたこと]
- **スクリーンショット**: [保存パス]
- **エラーログ**: [コンソールにエラーがあれば]
```

### 5-3. Explore エージェントに調査を委託

不具合の原因調査をexploreエージェントに委託する。

```
Agent:
  subagent_type: explore  
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

    ## 調査のヒント
    - 変更されたファイル: [git diff で確認した変更ファイル一覧]
    - 関連しそうなProvider/Widget: [推測される関連コード]

    プロジェクトルート: /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile
    エージェント定義: /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile/.claude/agents/explore.md
```

### 5-4. 調査結果に基づく修正

exploreエージェントの調査結果を受けて:
1. 原因箇所を特定
2. 修正が必要なら適切なサブエージェント（flutter-ui, riverpod等）に修正を委託
3. 修正後、再度ビルド & テスト（Step 2 からやり直し）

## Step 6: 結果レポート

全テスト項目の実行が完了したら、結果をまとめて報告する。

```markdown
## QA結果レポート

### テスト環境
- デバイス: [シミュレータ名]
- iOS: [バージョン]
- ビルド: Debug

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

### flutter run が "Unable to find destination" で失敗する

Xcode 26 と Flutter の互換性問題。Step 2-5 のフォールバック手順（xcodebuild直接ビルド）を使う。

### Pod install が失敗する

```bash
cd ios
pod deintegrate
pod install --repo-update
cd ..
```

### シミュレータが起動しない

```bash
# 全シミュレータをシャットダウンしてから再起動
xcrun simctl shutdown all
xcrun simctl boot <DEVICE_UDID>
open -a Simulator
```

### ビルド成果物にRunner.appが見つからない

DerivedData内を検索:
```bash
find ~/Library/Developer/Xcode/DerivedData -name "Runner.app" -path "*Debug-iphonesimulator*" -type d
```

### クリックがシミュレータの外に当たる

- 必ず最新のスクリーンショットで座標を確認
- zoom ツールで対象のUI要素を拡大して正確な位置を把握
- シミュレータウィンドウのサイズが変わっていないか確認
