# FIT-CONNECT-MOBILE セットアップガイド

**プロジェクト名**: FIT-CONNECT-MOBILE  
**フレームワーク**: Flutter  
**対象プラットフォーム**: iOS / Android  
**作成日**: 2025年12月20日

---

## 目次

1. [前提条件](#1-前提条件)
2. [プロジェクト作成](#2-プロジェクト作成)
3. [依存パッケージのインストール](#3-依存パッケージのインストール)
4. [プロジェクト構造](#4-プロジェクト構造)
5. [Supabase接続設定](#5-supabase接続設定)
6. [環境変数管理](#6-環境変数管理)
7. [ディープリンク設定](#7-ディープリンク設定)
8. [プッシュ通知設定](#8-プッシュ通知設定)
9. [初期実装](#9-初期実装)
10. [動作確認](#10-動作確認)

---

## 1. 前提条件

### 必要なツール

- **Flutter SDK**: 3.24以降
- **Dart SDK**: 3.5以降（Flutterに含まれる）
- **IDE**: 
  - VS Code + Flutter拡張機能
  - または Android Studio + Flutter Plugin
- **iOS開発** (Macのみ):
  - Xcode 15以降
  - CocoaPods
- **Android開発**:
  - Android Studio
  - Android SDK

### インストール確認

```bash
flutter --version
dart --version
flutter doctor
```

`flutter doctor` で問題がないことを確認してください。

---

## 2. プロジェクト作成

### 2.1 プロジェクト生成

```bash
# プロジェクトを作成したいディレクトリに移動
cd ~/projects  # 例

# Flutterプロジェクト作成
flutter create --org com.fitconnect fit_connect_mobile

# プロジェクトディレクトリに移動
cd fit_connect_mobile
```

**パラメータ説明**:
- `--org com.fitconnect`: Bundle Identifier のプレフィックス
  - iOS: `com.fitconnect.fitConnectMobile`
  - Android: `com.fitconnect.fit_connect_mobile`
- `fit_connect_mobile`: プロジェクト名（snake_case）

### 2.2 初期動作確認

```bash
# デバイス確認
flutter devices

# アプリ実行（デバイスまたはシミュレータ）
flutter run
```

カウンターアプリが起動すればOK!

---

## 3. 依存パッケージのインストール

### 3.1 pubspec.yaml の編集

`pubspec.yaml` を以下の内容に更新:

```yaml
name: fit_connect_mobile
description: "FIT-CONNECT クライアント向けモバイルアプリ"
publish_to: 'none'
version: 1.0.0+1

environment:
  sdk: '>=3.5.0 <4.0.0'

dependencies:
  flutter:
    sdk: flutter

  # 状態管理
  flutter_riverpod: ^2.6.1
  riverpod_annotation: ^2.5.0

  # Supabase連携
  supabase_flutter: ^2.9.1

  # UI・アニメーション
  confetti: ^0.7.0  # 目標達成時の紙吹雪
  fl_chart: ^0.70.1  # グラフ表示

  # 画像処理
  image_picker: ^1.1.2
  image_cropper: ^8.0.2
  cached_network_image: ^3.4.1

  # ユーティリティ
  intl: ^0.19.0  # 日付フォーマット
  url_launcher: ^6.3.1  # URL起動
  share_plus: ^10.1.1  # 共有機能
  path_provider: ^2.1.5  # ファイルパス取得

  # QRコード
  mobile_scanner: ^5.2.3  # QRコードスキャン
  qr_flutter: ^4.1.0  # QRコード生成（デバッグ用）

  # プッシュ通知
  firebase_core: ^3.8.1
  firebase_messaging: ^15.1.5

  # その他
  flutter_dotenv: ^5.2.1  # 環境変数
  logger: ^2.5.0  # ログ出力

dev_dependencies:
  flutter_test:
    sdk: flutter

  # Linter
  flutter_lints: ^5.0.0

  # Code Generation
  build_runner: ^2.4.13
  riverpod_generator: ^2.5.0
  json_serializable: ^6.9.2

flutter:
  uses-material-design: true

  # assets:
  #   - assets/images/
  #   - .env

  # fonts:
  #   - family: NotoSansJP
  #     fonts:
  #       - asset: assets/fonts/NotoSansJP-Regular.ttf
  #       - asset: assets/fonts/NotoSansJP-Bold.ttf
  #         weight: 700
```

### 3.2 パッケージインストール

```bash
flutter pub get
```

---

## 4. プロジェクト構造

### 4.1 推奨ディレクトリ構造

```
fit_connect_mobile/
├─ lib/
│  ├─ main.dart                      # エントリーポイント
│  ├─ app.dart                       # アプリルート
│  │
│  ├─ core/                          # 共通機能
│  │  ├─ constants/
│  │  │  ├─ app_constants.dart       # 定数
│  │  │  ├─ storage_keys.dart        # Storageキー
│  │  │  └─ tag_constants.dart       # タグ定義
│  │  │
│  │  ├─ theme/
│  │  │  ├─ app_theme.dart           # テーマ設定
│  │  │  └─ app_colors.dart          # カラーパレット
│  │  │
│  │  └─ utils/
│  │     ├─ date_utils.dart          # 日付ユーティリティ
│  │     ├─ validators.dart          # バリデーション
│  │     └─ extensions.dart          # 拡張メソッド
│  │
│  ├─ features/                      # 機能別（Feature-first）
│  │  ├─ auth/                       # 認証
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  ├─ qr_scan_screen.dart
│  │  │  │  │  ├─ email_input_screen.dart
│  │  │  │  │  └─ registration_complete_screen.dart
│  │  │  │  └─ widgets/
│  │  │  ├─ providers/
│  │  │  │  └─ auth_provider.dart
│  │  │  └─ models/
│  │  │
│  │  ├─ home/                       # ホーム
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  └─ home_screen.dart
│  │  │  │  └─ widgets/
│  │  │  │     ├─ goal_card.dart
│  │  │  │     └─ summary_card.dart
│  │  │  └─ providers/
│  │  │
│  │  ├─ messages/                   # メッセージ
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  └─ messages_screen.dart
│  │  │  │  └─ widgets/
│  │  │  │     ├─ message_input.dart
│  │  │  │     ├─ tag_suggestions.dart
│  │  │  │     └─ message_bubble.dart
│  │  │  ├─ providers/
│  │  │  └─ models/
│  │  │     └─ message.dart
│  │  │
│  │  ├─ meal_records/               # 食事記録
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  ├─ meal_records_screen.dart
│  │  │  │  │  └─ meal_detail_screen.dart
│  │  │  │  └─ widgets/
│  │  │  │     └─ meal_calendar.dart
│  │  │  ├─ providers/
│  │  │  └─ models/
│  │  │
│  │  ├─ weight_records/             # 体重記録
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  └─ weight_records_screen.dart
│  │  │  │  └─ widgets/
│  │  │  │     ├─ weight_chart.dart
│  │  │  │     └─ weight_stats_card.dart
│  │  │  ├─ providers/
│  │  │  └─ models/
│  │  │
│  │  ├─ exercise_records/           # 運動記録
│  │  │  ├─ presentation/
│  │  │  │  ├─ screens/
│  │  │  │  │  └─ exercise_records_screen.dart
│  │  │  │  └─ widgets/
│  │  │  ├─ providers/
│  │  │  └─ models/
│  │  │
│  │  └─ goals/                      # 目標管理
│  │     ├─ presentation/
│  │     │  ├─ screens/
│  │     │  │  └─ goal_achievement_screen.dart
│  │     │  └─ widgets/
│  │     ├─ providers/
│  │     └─ models/
│  │
│  ├─ shared/                        # 共有コンポーネント
│  │  ├─ widgets/
│  │  │  ├─ loading_indicator.dart
│  │  │  ├─ error_view.dart
│  │  │  ├─ custom_button.dart
│  │  │  └─ bottom_navigation.dart
│  │  │
│  │  └─ models/
│  │     ├─ base_response.dart
│  │     └─ api_error.dart
│  │
│  └─ services/                      # サービス層
│     ├─ supabase_service.dart       # Supabase全般
│     ├─ auth_service.dart           # 認証
│     ├─ message_service.dart        # メッセージ
│     ├─ record_service.dart         # 記録CRUD
│     ├─ storage_service.dart        # 画像アップロード
│     └─ notification_service.dart   # プッシュ通知
│
├─ assets/
│  ├─ images/
│  └─ .env                           # 環境変数（.gitignore追加）
│
├─ android/                          # Android設定
├─ ios/                              # iOS設定
│
└─ test/                             # テストコード
   ├─ unit/
   ├─ widget/
   └─ integration/
```

### 4.2 ディレクトリ作成

```bash
# coreディレクトリ
mkdir -p lib/core/{constants,theme,utils}

# featuresディレクトリ
mkdir -p lib/features/auth/{presentation/{screens,widgets},providers,models}
mkdir -p lib/features/home/{presentation/{screens,widgets},providers}
mkdir -p lib/features/messages/{presentation/{screens,widgets},providers,models}
mkdir -p lib/features/meal_records/{presentation/{screens,widgets},providers,models}
mkdir -p lib/features/weight_records/{presentation/{screens,widgets},providers,models}
mkdir -p lib/features/exercise_records/{presentation/{screens,widgets},providers,models}
mkdir -p lib/features/goals/{presentation/{screens,widgets},providers,models}

# sharedディレクトリ
mkdir -p lib/shared/{widgets,models}

# servicesディレクトリ
mkdir -p lib/services

# assetsディレクトリ
mkdir -p assets/images
```

---

## 5. Supabase接続設定

### 5.1 環境変数ファイル作成

`assets/.env` を作成:

```env
# Supabase設定
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key-here

# ディープリンク
DEEP_LINK_SCHEME=fitconnectmobile
DEEP_LINK_HOST=login-callback
```

**重要**: `.gitignore` に追加して、機密情報を保護!

```bash
echo "assets/.env" >> .gitignore
```

### 5.2 pubspec.yaml にアセット追加

```yaml
flutter:
  assets:
    - assets/.env
    - assets/images/
```

### 5.3 Supabase初期化

`lib/services/supabase_service.dart` を作成:

```dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;
  
  static Future<void> initialize() async {
    // 環境変数読み込み
    await dotenv.load(fileName: "assets/.env");
    
    final supabaseUrl = dotenv.env['SUPABASE_URL']!;
    final supabaseAnonKey = dotenv.env['SUPABASE_ANON_KEY']!;
    
    await Supabase.initialize(
      url: supabaseUrl,
      anonKey: supabaseAnonKey,
      authOptions: FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
        autoRefreshToken: true,
      ),
      realtimeClientOptions: const RealtimeClientOptions(
        logLevel: RealtimeLogLevel.info,
      ),
    );
  }
}
```

---

## 6. 環境変数管理

### 6.1 環境別の設定

開発環境と本番環境で分ける場合:

```
assets/
├─ .env                  # デフォルト（開発）
├─ .env.development      # 開発環境
├─ .env.production       # 本番環境
└─ .env.example          # サンプル（Gitにコミット）
```

**`.env.example`** (Gitにコミット):
```env
SUPABASE_URL=https://your-project.supabase.co
SUPABASE_ANON_KEY=your-anon-key
DEEP_LINK_SCHEME=fitconnectmobile
DEEP_LINK_HOST=login-callback
```

### 6.2 環境変数の読み込み

```dart
// 開発環境
await dotenv.load(fileName: "assets/.env.development");

// 本番環境
await dotenv.load(fileName: "assets/.env.production");
```

---

## 7. ディープリンク設定

認証完了時にアプリに戻るために必要。

### 7.1 iOS設定

`ios/Runner/Info.plist` に追加:

```xml
<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleTypeRole</key>
    <string>Editor</string>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>fitconnectmobile</string>
    </array>
  </dict>
</array>

<!-- Universal Links用（オプション） -->
<key>com.apple.developer.associated-domains</key>
<array>
  <string>applinks:your-domain.com</string>
</array>
```

### 7.2 Android設定

`android/app/src/main/AndroidManifest.xml` に追加:

```xml
<activity
    android:name=".MainActivity"
    ...>
    
    <!-- 既存のIntent Filter -->
    <intent-filter>
        <action android:name="android.intent.action.MAIN"/>
        <category android:name="android.intent.category.LAUNCHER"/>
    </intent-filter>
    
    <!-- ディープリンク用 -->
    <intent-filter>
        <action android:name="android.intent.action.VIEW" />
        <category android:name="android.intent.category.DEFAULT" />
        <category android:name="android.intent.category.BROWSABLE" />
        <data
            android:scheme="fitconnectmobile"
            android:host="login-callback" />
    </intent-filter>
    
</activity>
```

---

## 8. プッシュ通知設定

### 8.1 Firebase プロジェクト作成

1. [Firebase Console](https://console.firebase.google.com/) でプロジェクト作成
2. iOS / Android アプリを追加
3. 設定ファイルをダウンロード
   - iOS: `GoogleService-Info.plist`
   - Android: `google-services.json`

### 8.2 設定ファイル配置

**iOS**:
```
ios/Runner/GoogleService-Info.plist
```

**Android**:
```
android/app/google-services.json
```

### 8.3 Android Gradle設定

`android/build.gradle` に追加:

```gradle
buildscript {
    dependencies {
        // ...
        classpath 'com.google.gms:google-services:4.4.2'
    }
}
```

`android/app/build.gradle` の最後に追加:

```gradle
apply plugin: 'com.google.gms.google-services'
```

### 8.4 通知サービス実装

`lib/services/notification_service.dart`:

```dart
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  
  static Future<void> initialize() async {
    // 権限リクエスト
    await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    
    // FCMトークン取得
    final token = await _messaging.getToken();
    print('FCM Token: $token');
    
    // フォアグラウンド通知
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('メッセージ受信: ${message.notification?.title}');
      // ローカル通知表示
    });
    
    // バックグラウンド通知
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }
}

// バックグラウンドハンドラ（トップレベル関数）
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  print('バックグラウンドメッセージ: ${message.notification?.title}');
}
```

---

## 9. 初期実装

### 9.1 main.dart の実装

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'services/supabase_service.dart';
import 'services/notification_service.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 環境変数読み込み
  await dotenv.load(fileName: "assets/.env");
  
  // Supabase初期化
  await SupabaseService.initialize();
  
  // プッシュ通知初期化（後で実装）
  // await NotificationService.initialize();
  
  runApp(
    const ProviderScope(
      child: MyApp(),
    ),
  );
}
```

### 9.2 app.dart の実装

```dart
import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FIT-CONNECT',
      theme: AppTheme.lightTheme,
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        body: Center(
          child: Text('FIT-CONNECT Mobile'),
        ),
      ),
    );
  }
}
```

### 9.3 テーマ設定

`lib/core/theme/app_theme.dart`:

```dart
import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppTheme {
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.primary,
        brightness: Brightness.light,
      ),
      scaffoldBackgroundColor: AppColors.background,
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        selectedItemColor: AppColors.primary,
        unselectedItemColor: Colors.grey,
      ),
    );
  }
}
```

`lib/core/theme/app_colors.dart`:

```dart
import 'package:flutter/material.dart';

class AppColors {
  // Primary
  static const Color primary = Color(0xFF2563EB); // Blue
  static const Color primaryLight = Color(0xFF60A5FA);
  static const Color primaryDark = Color(0xFF1E40AF);
  
  // Success / Progress
  static const Color success = Color(0xFF10B981); // Green
  static const Color warning = Color(0xFFF59E0B); // Orange
  static const Color error = Color(0xFFEF4444); // Red
  
  // GitHub Grass Colors
  static const Color grassLevel0 = Color(0xFFEBEDF0); // グレー
  static const Color grassLevel1 = Color(0xFF9BE9A8); // 薄い緑
  static const Color grassLevel2 = Color(0xFF39D353); // 中くらいの緑
  static const Color grassLevel3 = Color(0xFF26A641); // 濃い緑
  
  // Background
  static const Color background = Color(0xFFFAFAFA);
  static const Color cardBackground = Colors.white;
  
  // Text
  static const Color textPrimary = Color(0xFF1F2937);
  static const Color textSecondary = Color(0xFF6B7280);
  static const Color textHint = Color(0xFF9CA3AF);
}
```

---

## 10. 動作確認

### 10.1 アプリ起動

```bash
flutter run
```

### 10.2 確認事項

- ✅ アプリが起動する
- ✅ "FIT-CONNECT Mobile" の文字が表示される
- ✅ Supabaseに接続できる（ログで確認）

### 10.3 Supabase接続確認

`lib/app.dart` を一時的に修正:

```dart
import 'package:flutter/material.dart';
import 'services/supabase_service.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Supabase接続確認
    final client = SupabaseService.client;
    print('Supabase URL: ${client.supabaseUrl}');
    
    return MaterialApp(
      title: 'FIT-CONNECT',
      home: Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('FIT-CONNECT Mobile'),
              const SizedBox(height: 16),
              Text('Connected to: ${client.supabaseUrl}'),
            ],
          ),
        ),
      ),
    );
  }
}
```

コンソールに Supabase URL が表示されればOK!

---

## 次のステップ

セットアップが完了したら、実装フェーズに進みます:

### フェーズ1: 認証機能
1. QRコードスキャン画面
2. メールアドレス入力画面
3. 認証フロー実装

### フェーズ2: ボトムナビゲーション
1. ホーム画面
2. メッセージ画面
3. 記録画面（タブ切り替え）

### フェーズ3: メッセージ機能
1. メッセージ一覧表示
2. タグ入力UI
3. 画像添付
4. リアルタイム更新

---

## トラブルシューティング

### よくあるエラー

#### 1. `flutter pub get` が失敗する
```bash
flutter clean
flutter pub get
```

#### 2. iOS ビルドエラー
```bash
cd ios
pod install
cd ..
flutter run
```

#### 3. Android ビルドエラー
- `android/gradle.properties` に追加:
```properties
org.gradle.jvmargs=-Xmx2048m
```

#### 4. Supabase接続エラー
- `.env` ファイルの内容を確認
- URL・ANON KEYが正しいか確認

---

**以上でセットアップ完了です! 🎉**
