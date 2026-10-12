---
name: android-emulator-qa
description: |
  Android Emulator QA - コード変更後のAndroidアプリ動作確認スキル。
  fit-connect-mobileの実装タスク完了後に、`dev_login.json` 付きビルド（テストログイン有効）を
  fvm 経由でAndroidエミュレータに起動し、adb（screencap / uiautomator dump / input tap 等）で
  画面操作・動作検証を行う。computer use は不要で、ユーザーが Mac を操作中でも実行できる。

  以下の場面で必ず使用すること:
  - Flutterコードの実装・修正が完了し、Android での確認が必要な時
  - 「エミュレータで確認」「Androidで確認」「Androidで動作確認して」と言われた時
  - Android 固有の挙動（戻るボタン、権限、ディープリンク等）に関わる変更をした時
  - 実装タスクの完了報告前の最終チェック（Android）

  iOS での確認は ios-simulator-qa スキルを使う。

  重要: サブエージェントによるコード変更完了後は、ユーザーから「確認不要」「スキップして」と
  指示されない限り、自動的に QA を実行すること。
---

# Android Emulator QA Skill

コード変更後に `dev_login.json` 付きビルドでAndroidエミュレータにアプリを起動し、
adb コマンドで画面確認・操作を行うスキル。
不具合発見時はスクリーンショットと logcat を保存し、Explore エージェントに調査を委託する。

## 全体フロー

```
1. テスト計画の作成（変更内容に基づく）
2. エミュレータの確認・起動（adb devices）
3. ビルド & 起動（fvm flutter run + dev_login.json）
4. ログイン状態の判定 & テストログイン
5. adb で各テスト項目を実行
6. 不具合発見時 → スクリーンショット + logcat 保存 → Explore エージェントに調査委託
7. 結果レポート
```

## 前提・共通ルール

- 作業ディレクトリ: リポジトリルート直下の `fit-connect-mobile/`
- Flutter は **fvm 経由** で実行する（`fvm flutter ...`）
- 動作確認は **必ず `--dart-define-from-file=dev_login.json` 付きビルド** で行う
  - ログイン画面に「テストログイン（開発用）」ボタンが表示される
  - 値はコンパイル時に埋め込まれるため **ホットリロードでは反映されない**。付け忘れたら再起動すること
  - `dev_login.json` には認証情報が含まれるため **中身を読まない**。存在確認のみ: `test -f dev_login.json`
- applicationId: `com.fitconnect.fit_connect_mobile`
- ディープリンクスキーム: `fitconnectmobile://`（例: `fitconnectmobile://login-callback`）
- 既定のエミュレータ: `emulator-5556`（`adb devices` で確認し、異なれば置き換える）
- **adb は PATH に無い**。各コマンドの先頭で変数を定義して使う:

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
DEV=emulator-5556
```

- スクリーンショット・UI ダンプの保存先はリポジトリ外のスクラッチ領域（例: セッションの scratchpad）にする。以下 `<scratch>` と表記

> **computer use は不要**。adb のみで画面取得・操作が完結するため、ユーザーが Mac を使っている最中でも検証できる。

## Step 1: テスト計画の作成

変更されたファイル・機能に基づいてテスト項目を作成する。

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
4. **回帰テスト** — 全タブ遷移、Android の戻るボタン挙動

### テスト項目テンプレート

```markdown
## テスト計画: [変更内容の要約]

### 直接テスト
- [ ] T-001: [変更した画面]を開き、[変更内容]が正しく表示されることを確認
- [ ] T-002: [変更した機能]を操作し、期待通り動作することを確認

### 回帰テスト
- [ ] T-R01: 全5タブ（ホーム→メッセージ→プラン→記録→設定）の遷移確認
- [ ] T-R02: 戻るボタン（KEYCODE_BACK）で想定通り前画面に戻ること
- [ ] T-R03: アプリがクラッシュせず安定動作すること
```

## Step 2: エミュレータの確認・起動

```bash
ADB=~/Library/Android/sdk/platform-tools/adb
$ADB devices
```

`emulator-5556  device` のように表示されていれば起動済み。何も無ければ AVD を起動する:

```bash
# AVD 一覧
~/Library/Android/sdk/emulator/emulator -list-avds

# 起動（Bash の run_in_background: true で実行。終了しないプロセス）
~/Library/Android/sdk/emulator/emulator -avd <AVD名>

# 起動完了待ち（1 が返れば完了）
$ADB wait-for-device shell getprop sys.boot_completed
```

起動後のシリアル（`emulator-5554` 等）を `adb devices` で確認し、以降の `DEV` / `-d` に使う。
`fvm flutter devices` でも Flutter から見えるデバイス ID を確認できる。

## Step 3: ビルド & 起動

### 3-1. 依存関係 & コード生成（必要な場合のみ）

```bash
cd fit-connect-mobile
fvm flutter pub get
fvm dart run build_runner build --delete-conflicting-outputs
```

### 3-2. ビルド & 起動（標準コマンド）

```bash
cd fit-connect-mobile
test -f dev_login.json && echo "dev_login.json OK"
fvm flutter run -d emulator-5556 --dart-define-from-file=dev_login.json
```

- `flutter run` は対話型で終了しないプロセスなので、**Bash の `run_in_background: true` で実行**する
- 出力に `Syncing files to device` などが出てアプリが起動するまで待つ（ブロックしない。Monitor 等で出力を確認）
- 初回の Gradle ビルドは数分かかることがある
- コード修正後はバックグラウンドの `flutter run` を停止して再実行する

## Step 4: ログイン状態の判定 & テストログイン

起動後、スクリーンショット（Step 5 参照）と UI ダンプで画面を確認する。

### 判定基準

| 表示画面 | 状態 | 対応 |
|----------|------|------|
| 下部に5タブ（ホーム/メッセージ/プラン/記録/設定）が見える | **ログイン済み** | → Step 5 へ |
| 「FIT-CONNECT」ロゴ + 「新規登録」ボタン | **ウェルカム画面**（未ログイン） | → 下記へ |
| ログイン画面（メール入力 等） | **ログイン画面**（未ログイン） | → 下記へ |

### アプリのログイン分岐（app.dart）

- ログイン済み + `clients` 行あり → MainScreen（ホーム）
- ログイン済み + 登録途中（新規登録で招待コード入力済み） → ProfileSetupScreen
- ログイン済み + どちらでもない → アプリがサインアウトし WelcomeScreen に戻る

### A) 登録済みテストクライアントでログイン（通常はこちら）

1. ウェルカム画面で「ログインはこちら」をタップ
2. ログイン画面の「**テストログイン（開発用）**」をタップ
3. ホーム画面（5タブ）が表示されたら → Step 5 へ

ボタンの座標は UI ダンプ（`content-desc` にラベルが入る）から求める。
ボタンが無い場合は `dev_login.json` 無しでビルドされている。Step 3-2 のコマンドで再起動すること。

### B) 新規アカウントのフロー（登録フロー自体をテストする場合）

1. ウェルカム画面で「新規登録」→ 招待コード入力 → トレーナー確認
2. 「メールアドレス認証」画面で「**テストログイン（開発用）**」をタップ
3. プロフィール設定画面（ProfileSetupScreen）へ進む

### 禁止事項

- マジックリンク（メールアドレス入力）経路は使わない
- パスワード等の認証情報は **絶対に自分で入力しない**。ログインはテストログインボタンのタップのみで行う

## Step 5: adb による動作確認

### 5-1. スクリーンショット

```bash
$ADB -s $DEV exec-out screencap -p > <scratch>/shot.png
```

保存した PNG を Read ツールで開いて画面を確認する。

- screencap は **物理ピクセル**（`emulator-5556` は 1080x2400）。Read で表示される画像は縮小されることがあり、その場合は表示上の座標に倍率（例: 900x2000 表示なら ×1.2）を掛けて物理ピクセルに戻す
- 画面サイズは `$ADB -s $DEV shell wm size` で確認

### 5-2. UI 要素の位置取得（uiautomator dump）

```bash
$ADB -s $DEV shell uiautomator dump /sdcard/ui.xml
$ADB -s $DEV exec-out cat /sdcard/ui.xml > <scratch>/ui.xml
```

**Flutter の場合、ラベルは `text` ではなく `content-desc` に入る**（`text=""`、`class="android.view.View"`）。
各ノードの `bounds="[x1,y1][x2,y2]"` の中心 `((x1+x2)/2, (y1+y2)/2)` をタップすればよい。
ラベル付きノードと中心座標を一覧するスクリプト:

```bash
python3 -I - <scratch>/ui.xml <<'PY'
import re, sys, html
xml = open(sys.argv[1], encoding="utf-8").read()
for n in re.findall(r"<node [^>]*>", xml):
    a = dict(re.findall(r'([\w-]+)="([^"]*)"', n))
    label = html.unescape(a.get("text") or a.get("content-desc") or "")
    x1, y1, x2, y2 = map(int, re.findall(r"\d+", a["bounds"]))
    if label or a.get("clickable") == "true":
        print(f"{(x1+x2)//2},{(y1+y2)//2}\tclickable={a.get('clickable')}\t{label!r}")
PY
```

出力例（ホーム画面・下部タブ）:

```
139,2229	clickable=true	'ホーム'
361,2229	clickable=true	'メッセージ'
584,2229	clickable=true	'プラン'
771,2229	clickable=true	'記録'
949,2229	clickable=true	'設定'
```

注意点:
- 複数行のテキストを持つカード等は、子テキストが改行区切り（`&#10;`）で1つの `content-desc` にまとまることがある
- アイコンのみのボタン（閉じる × 等）はラベルが空（`content-desc=""`, `clickable=true`）。位置関係かスクリーンショットで判断する
- ノードが見つからない場合はスクリーンショット座標（物理ピクセル）でタップする
- 座標はすべて物理ピクセル。`uiautomator` の bounds・`screencap`・`input tap` は同じ座標系

### 5-3. 操作コマンド

| 操作 | コマンド |
|------|----------|
| タップ | `$ADB -s $DEV shell input tap <x> <y>` |
| スワイプ/スクロール | `$ADB -s $DEV shell input swipe <x1> <y1> <x2> <y2> 300` |
| 長押し | `$ADB -s $DEV shell input swipe <x> <y> <x> <y> 800` |
| テキスト入力 | `$ADB -s $DEV shell input text 'hello%sworld'`（スペースは `%s`） |
| 戻る | `$ADB -s $DEV shell input keyevent KEYCODE_BACK` |
| ホーム | `$ADB -s $DEV shell input keyevent KEYCODE_HOME` |
| ディープリンク | `$ADB -s $DEV shell am start -a android.intent.action.VIEW -d 'fitconnectmobile://...'` |
| アプリ起動 | `$ADB -s $DEV shell monkey -p com.fitconnect.fit_connect_mobile -c android.intent.category.LAUNCHER 1` |

- **日本語は `input text` で入力できない**（クリップボード経由も不安定）。テストデータは ASCII（英数字）で用意する
- テキスト入力前に入力欄をタップしてフォーカスする
- 下方向スクロール例: `input swipe 540 1600 540 600 300`（画面端から始めない）

### テスト実行の進め方

テスト計画の各項目について:

1. UI ダンプで対象要素の座標を取得 → `input tap` で遷移
2. 1-2秒待機
3. スクリーンショットを撮影して Read で確認（必要なら UI ダンプでテキストも確認）
4. 期待結果と照合
5. 問題なければ次のテスト項目へ
6. 問題があれば → Step 6 へ

## Step 6: 不具合発見時の対応

### 6-1. 証拠の保存

```bash
$ADB -s $DEV exec-out screencap -p > <scratch>/bug-T-001.png
$ADB -s $DEV logcat -d -t 300 | grep -iE "flutter|error|exception" > <scratch>/bug-T-001-logcat.txt
```

あわせてバックグラウンドの `flutter run` 出力の例外も確認する。

### 6-2. 不具合の記録

```markdown
## 不具合レポート: [不具合ID]

- **発見画面**: [タブ名/画面名]
- **操作手順**: [再現手順]
- **期待結果**: [本来表示されるべき内容]
- **実際の結果**: [実際に起きたこと]
- **スクリーンショット**: [保存パス]
- **エラーログ**: [logcat / flutter run 出力の該当部分]
```

### 6-3. Explore エージェントに調査を委託

```
Agent:
  subagent_type: Explore
  prompt: |
    fit-connect-mobileアプリ（Android）で以下の不具合が発生しています。原因を調査してください。

    ## 不具合内容
    [不具合の詳細]

    ## 発生画面
    [画面名・タブ名]

    ## 再現手順
    [操作手順]

    ## 期待結果 vs 実際の結果
    - 期待: [...]
    - 実際: [...]

    ## エラーログ（logcat）
    [該当部分]

    ## 調査のヒント
    - 変更されたファイル: [git diff で確認した変更ファイル一覧]
    - 関連しそうなProvider/Widget: [推測される関連コード]

    プロジェクトルート: fit-connect-mobile/（リポジトリルート相対）
```

### 6-4. 調査結果に基づく修正

1. 原因箇所を特定
2. 修正が必要なら適切なサブエージェント（flutter-ui, riverpod等）に修正を委託
3. 修正後、再度ビルド & テスト（Step 3-2 からやり直し）

## Step 7: 結果レポート

```markdown
## QA結果レポート（Android）

### テスト環境
- デバイス: [AVD名 / シリアル]
- Android: [バージョン（`$ADB -s $DEV shell getprop ro.build.version.release`）]
- ビルド: Debug（dev_login.json 付き）

### テスト結果サマリー
- 合格: X / Y 項目
- 不合格: Z 項目
- スキップ: W 項目

### 不合格項目の詳細
| ID | 内容 | ステータス | 備考 |
|----|------|-----------|------|
| T-001 | ... | FAIL | [不具合内容] |

### スクリーンショット・ログ
- [保存パス一覧]
```

## トラブルシューティング

### `adb: command not found`

PATH に無い。`ADB=~/Library/Android/sdk/platform-tools/adb` を定義してフルパスで実行する。

### 「テストログイン（開発用）」ボタンが表示されない

`--dart-define-from-file=dev_login.json` 無しでビルドされている（またはホットリロードで済ませた）。
`flutter run` を停止し、Step 3-2 のコマンドで再起動する。`fit-connect-mobile/` で実行しているかも確認。

### `adb devices` で `offline` / 何も表示されない

```bash
$ADB kill-server && $ADB start-server
$ADB devices
```

それでも出なければエミュレータを再起動する（Step 2）。

### uiautomator dump が `ERROR: could not get idle state` で失敗する

アニメーション中などで UI がアイドルにならない。1-2秒待って再実行する。続く場合はスクリーンショット座標で操作する。

### UI ダンプに目的のノードが無い

- Flutter のセマンティクスが付いていない Widget（アイコンのみ等）はラベルが空になる
- 画面外（スクロールが必要）の要素はダンプに含まれないことがある。スクロールしてから再ダンプする
- 取得できない場合はスクリーンショットの座標（物理ピクセル換算）でタップする

### タップ位置がずれる

- Read で表示した画像が縮小されている場合は倍率を掛けて物理ピクセルに戻す（`wm size` で実サイズ確認）
- 可能な限り UI ダンプの bounds から座標を求める
