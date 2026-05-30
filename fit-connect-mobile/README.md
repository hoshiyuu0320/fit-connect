# fit_connect_mobile

FIT-CONNECT のクライアント向け Flutter アプリ。

## 開発環境セットアップ

### 必要なツールとバージョン

| ツール | バージョン | 備考 |
| --- | --- | --- |
| **Flutter** | **3.41.9（固定）** | fvm でピン留め（`.fvmrc`）。最新版は使わないこと（下記参照） |
| Dart | 3.11.5 | Flutter 3.41.9 に同梱 |
| **Xcode** | **26.x 推奨** | iOSビルドに必須。実機ビルドは端末のiOSに対応した版が必要（下記参照） |
| CocoaPods | 1.16.x | iOSビルド用（`brew install cocoapods`） |
| OpenJDK | 21 | Android/Gradle用（`brew install openjdk@21`） |
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
   ```
   これが無いとアセット束ね処理でビルドが失敗する。
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

### 実機（iPhone）ビルド時の注意

実機ビルドはシミュレータより手順が多い。初回に以下が必要:

1. **デバイスの信頼**: iPhoneを接続 → 「このコンピュータを信頼」→ デベロッパモードをオン（設定 → プライバシーとセキュリティ → デベロッパモード）。
2. **コード署名**: Xcode → Settings → Accounts に Apple ID をサインイン。署名チームは `DEVELOPMENT_TEAM = HNKWT8DU57`（自動署名）。
3. **Rosetta（Apple Silicon Mac のみ）**: 実機転送用バイナリが x86_64 のため必要。
   ```bash
   sudo softwareupdate --install-rosetta --agree-to-license
   ```
4. **Xcodeのバージョン**: 実機の iOS に対応した Xcode が必要（例: iOS 26.5 の端末には Xcode 26.x）。古すぎる Xcode では新しい iOS 実機に流せない。

### マシン間でビルドを揃えるには

- **Flutter**: `.fvmrc` をコミットしてあるので、どのマシンでも `fvm install` で 3.41.9 が揃う（手動調整不要）。
- **Xcode**: プロジェクト単位の固定機構が無いため、各マシンで**同じメジャー版（26.x）に手動で揃える**こと。Xcode版がズレると `Runner.xcscheme` / `project.pbxproj` に差分が出ることがある。
- `ios/Runner.xcodeproj/project.pbxproj` と `Runner.xcscheme` の差分は、Flutterバージョンや Xcode版が変わった**初回ビルド時の一度きりの移行**で発生する（通常のコード編集・再ビルドでは再発しない）。

## アーキテクチャ等の詳細

`CLAUDE.md` および `docs/` を参照。
