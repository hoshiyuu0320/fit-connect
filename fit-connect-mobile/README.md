# fit_connect_mobile

FIT-CONNECT のクライアント向け Flutter アプリ。

## 開発環境セットアップ

### 必要なツールとバージョン

| ツール | バージョン | 備考 |
| --- | --- | --- |
| **Flutter** | **3.41.9（固定）** | fvm でピン留め（`.fvmrc`）。最新版は使わないこと（下記参照） |
| Dart | 3.11.5 | Flutter 3.41.9 に同梱 |
| **Xcode** | **26.x / 27.x** | iOSビルドに必須。実機ビルドは端末のiOSに対応した版が必要（下記参照）。27.x は下記「Xcode 27 の注意点」参照 |
| CocoaPods | 1.16.x | iOSビルド用（`brew install cocoapods`） |
| **OpenJDK** | **21** | Android/Gradle用（`brew install openjdk@21`）。Android Studio 同梱の JDK（25）では Gradle 8.14 が動かないため必須。下記参照 |
| Android SDK | platform 36 / build-tools 36 | Androidビルド用 |

### ⚠️ Flutter は 3.41.9 に固定（fvm 管理）

このプロジェクトは **Flutter 3.41.9** でビルドする。**3.44.0 以降では `flutter run` / `flutter build` が失敗する。**

- **理由**: Flutter 3.44.0 で `IconData` が `final class` 化され、依存パッケージ `lucide_icons 0.257.0`（`IconData` を継承、約47ファイルで使用）がコンパイルエラーになる。`lucide_icons` は 0.257.0 が最新でメンテ停止しており互換版が無い。
- 互換範囲は Flutter 3.35.0〜3.43.x。3.44 直前の安定版が 3.41.9。
- 3.44+ へ上げたい場合は `lucide_icons` → `lucide_icons_flutter`（API別物、全使用箇所の改修）への移行が必須。

#### fvm の使い方

```bash
# fvm 未インストールなら
brew tap leoafarias/fvm && brew install fvm

# プロジェクトの Flutter（.fvmrc の 3.41.9）をインストール
fvm install

# 以降、このプロジェクトでは fvm 経由で Flutter を実行
fvm flutter pub get
fvm flutter run
```

`fvm global 3.41.9` で素の `flutter` も 3.41.9 に向けられる（PATH に `~/fvm/default/bin` を追加）。

### 初回ビルド前の準備

1. **依存取得 & コード生成**
   ```bash
   fvm flutter pub get
   fvm dart run build_runner build --delete-conflicting-outputs
   ```
2. **`assets/.env` を作成**（Git管理外）。Supabase接続情報を記載:
   ```
   SUPABASE_URL=...
   SUPABASE_ANON_KEY=...
   GOOGLE_WEB_CLIENT_ID=...
   ```
   これが無いとアセット束ね処理でビルドが失敗する。
   - `GOOGLE_WEB_CLIENT_ID` は Google ログイン用（`lib/features/auth/data/auth_repository.dart` で参照）。Google Cloud Console の認証情報にある **Web クライアント ID** を記載する。
3. **iOS依存（CocoaPods）** は `flutter build/run` 時に自動で `pod install` される。

### ビルド & 実行

```bash
# シミュレータ（署名不要・反復が速い。開発はこれが基本）
fvm flutter run -d "iPhone 16 Pro"

# Android
fvm flutter run -d <android-device>

# 実機（iPhone）
fvm flutter run -d <device-id>
```

開発中はアプリを起動したまま、ターミナルで `r`（hot reload）/ `R`（hot restart）で反映するのが最速。

### 開発用テストログイン

マジックリンクを使わずに検証用クライアントでログインするためのボタン（デバッグビルド限定）。

1. `dev_login.example.json` を `dev_login.json` にコピーし、検証用アカウントのメールアドレス・パスワードを記入（Git管理外）
2. `fvm flutter run -d <device> --dart-define-from-file=dev_login.json` で起動
3. ログイン画面に「テストログイン（開発用）」ボタンが表示される

認証情報は `assets/.env` に書かないこと（アセットとしてリリースビルドに同梱されるため）。dart-define 未指定時やリリースビルドではボタンは表示されない。

### 実機（iPhone）ビルド時の注意

実機ビルドはシミュレータより手順が多い。初回に以下が必要:

1. **デバイスの信頼**: iPhoneを接続 → 「このコンピュータを信頼」→ デベロッパモードをオン（設定 → プライバシーとセキュリティ → デベロッパモード）。
2. **コード署名**: Xcode → Settings → Accounts に Apple ID をサインイン。署名チームは `DEVELOPMENT_TEAM = HNKWT8DU57`（自動署名）。
3. **Rosetta（Apple Silicon Mac のみ）**: 実機転送用バイナリが x86_64 のため必要。
   ```bash
   sudo softwareupdate --install-rosetta --agree-to-license
   ```
4. **Xcodeのバージョン**: 実機の iOS に対応した Xcode が必要（例: iOS 26.5 の端末には Xcode 26.x）。古すぎる Xcode では新しい iOS 実機に流せない。

### Xcode 27 の注意点

- **Simulator.app が廃止**され、Device Hub（`Xcode.app/Contents/Applications/DeviceHub.app`）に置き換わった。`open -a Simulator` は失敗するので `open -a DeviceHub` を使う。
- Flutter 3.41.9 の `flutter emulators --launch` も旧 Simulator を探すため失敗する。先に simctl で起動しておく:
  ```bash
  xcrun simctl list devices available
  xcrun simctl boot "iPhone 18 Pro"
  open -a DeviceHub
  fvm flutter devices
  fvm flutter run -d <device-id>
  ```
- deployment target 15.0 未満の Pods はエラーになるが、`ios/Podfile` の `post_install` で 15.0 に揃えて対応済み。
- iOS シミュレータランタイムは Xcode → Settings → Components から、または以下で取得:
  ```bash
  xcodebuild -downloadPlatform iOS
  ```

### Android ビルドの準備

1. **Android Studio と JDK 21 をインストール**
   ```bash
   brew install --cask android-studio
   brew install openjdk@21
   ```
2. **SDK Manager で取得**
   - SDK Platforms: Android 16.0 (API 36.0)
   - SDK Tools: Build-Tools 36.0.0 / Command-line Tools (latest) / Android Emulator
   - NDK は初回ビルド時に Gradle が自動取得するので手動インストール不要。
3. **Flutter に JDK 21 を指定（必須）**
   ```bash
   fvm flutter config --jdk-dir "$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"
   ```
   - 未指定だと Android Studio 同梱の JDK 25 が使われ、`What went wrong: 25.0.3` のような意味不明なエラーでビルド失敗する。
   - JDK を切り替えた後は Gradle デーモンを止める:
     ```bash
     pkill -f GradleDaemon
     ```
4. **エミュレータは API 36 で作成**（arm64-v8a）。API 37 (Android 17) のエミュレータは Flutter 3.41.9 では `flutter run` の対象外になった（原因未特定）（`flutter devices` には出るが `No supported devices found`）。

- `minSdk` は health プラグインの要求で **26 固定**（`android/app/build.gradle.kts`）。
- 既知の無害な警告:
  - Command-line Tools 23 以降では `flutter doctor` が `Android license status unknown` を出すが、`~/Library/Android/sdk/licenses/` にファイルがあれば同意済みでビルドに影響なし。
  - `SDK XML versions up to 3 but ... version 4` 警告も無害。

### Android で Google ログインを使う（debug 署名の SHA-1）

Android の Google ログインは、Google Cloud Console の **Android 用 OAuth クライアント**に登録された「パッケージ名 `com.fitconnect.fit_connect_mobile` + 署名鍵の SHA-1」と一致しないと失敗する（`PlatformException(sign_in_failed, ... 10: ...)` / DEVELOPER_ERROR）。debug ビルドはマシンごとの `~/.android/debug.keystore` で署名されるため、**新しいマシンではそのままでは失敗する**。

- **対処A（推奨）**: 既存マシンの `~/.android/debug.keystore` を新マシンの同じパスへコピーする（Git には入れない）。
- **対処B**: 新マシンの SHA-1 を取得し、Google Cloud Console → APIs とサービス → 認証情報 で、同じパッケージ名・新しい SHA-1 の Android OAuth クライアントを**追加作成**する（既存クライアントの SHA-1 を書き換えると旧マシンで使えなくなる）。
  ```bash
  keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA1
  ```
  反映まで数分〜数十分かかることがある。
- 初回セットアップ手順の詳細は [`docs/superpowers/GOOGLE_AUTH_MANUAL_SETUP.md`](docs/superpowers/GOOGLE_AUTH_MANUAL_SETUP.md) を参照。
- 本番リリース時は本番署名鍵（Play App Signing 使用時は Play Console の「アプリの署名鍵」）の SHA-1 も登録が必要。

### マシン間でビルドを揃えるには

- **Flutter**: `.fvmrc` をコミットしてあるので、どのマシンでも `fvm install` で 3.41.9 が揃う（手動調整不要）。
- **Xcode**: プロジェクト単位の固定機構が無いため、各マシンで**同じメジャー版（26.x）に手動で揃える**こと。Xcode版がズレると `Runner.xcscheme` / `project.pbxproj` に差分が出ることがある。
- `ios/Runner.xcodeproj/project.pbxproj` と `Runner.xcscheme` の差分は、Flutterバージョンや Xcode版が変わった**初回ビルド時の一度きりの移行**で発生する（通常のコード編集・再ビルドでは再発しない）。

## アーキテクチャ等の詳細

`CLAUDE.md` および `docs/` を参照。
