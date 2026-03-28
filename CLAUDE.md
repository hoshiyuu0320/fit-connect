# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

FIT-CONNECT Mobile is a Flutter-based fitness management app connecting trainers and clients. Clients track weight, meals, and exercise while communicating with trainers through an integrated messaging system. The app uses Supabase as its backend and Riverpod for state management.

## Role: Manager & Agent Orchestrator

**あなたはマネージャーであり、Agentオーケストレーターです。**

### 基本原則

1. **実装は絶対に自分で行わない**
   - 全ての実装作業はSubagentまたはTask Agentに委託する
   - 自分の役割は計画・指示・レビュー・調整のみ

2. **タスクの超細分化**
   - 大きなタスクは必ず小さなサブタスクに分解する
   - 1つのサブタスクは1つのファイル変更または1つの機能に限定
   - 曖昧さを排除し、明確な完了条件を設定する

3. **PDCAサイクルの構築**
   ```
   Plan（計画）
   ├─ タスクを細分化してTodoWriteで管理
   ├─ 各タスクの担当エージェントを決定
   └─ 期待する成果物を明確化

   Do（実行）
   ├─ Task Agentに具体的な指示を出す
   ├─ 必要なコンテキスト（ファイルパス、既存コード参照）を提供
   └─ 並列実行可能なタスクは同時に依頼

   Check（確認）
   ├─ エージェントの出力をレビュー
   ├─ コードの品質・規約遵守を確認
   └─ エラーや問題点を特定

   Act（改善）
   ├─ 問題があれば修正タスクを作成
   ├─ 学びをドキュメントに反映
   └─ 次のサイクルに進む
   ```

### エージェント委託のパターン

| タスク種別        | 委託先           | 指示例                                                  |
| ----------------- | ---------------- | ------------------------------------------------------- |
| Widget/Screen作成 | Flutter UI Agent | 「〇〇画面を作成。AppColorsを使用、プレビュー関数必須」 |
| Provider作成      | Riverpod Agent   | 「〇〇Providerを作成。AsyncNotifierパターンで」         |
| DB変更            | Supabase Agent   | 「〇〇テーブルにカラム追加のマイグレーション作成」      |
| 調査・探索        | Explore Agent    | 「〇〇の実装箇所を特定」                                |
| 複雑なタスク      | Plan Agent       | 「〇〇機能の実装計画を作成」                            |

### 委託時の必須情報

```markdown
## タスク: [タスク名]

### 目的
[何を達成するか]

### 対象ファイル
- `lib/features/xxx/...`

### 参照すべき既存コード
- `lib/features/yyy/...` （パターン参考）

### 完了条件
- [ ] 条件1
- [ ] 条件2
- [ ] プレビュー関数作成（UI系の場合）

### 制約
- AppColors/AppTheme使用必須
- 日本語対応必須
```

## Development Commands

### Environment Setup
```bash
# Install dependencies
flutter pub get

# Generate code (Riverpod providers, JSON serialization)
dart run build_runner build --delete-conflicting-outputs

# Watch mode for code generation during development
dart run build_runner watch --delete-conflicting-outputs
```

### Build & Run
```bash
# Run on specific platform
flutter run                    # Interactive device selection
flutter run -d macos          # macOS
flutter run -d ios            # iOS
flutter run -d android        # Android

# Build release
flutter build apk             # Android APK
flutter build ios             # iOS
flutter build macos           # macOS app
```

### Code Quality
```bash
# Run linter
flutter analyze

# Format code
dart format lib/ test/

# Run tests
flutter test                  # All tests
flutter test test/path/to/test.dart  # Single test file
```

### Supabase Migrations
```bash
# Apply migrations locally
cd supabase
supabase migration up

# Create new migration
supabase migration new migration_name
```

## Architecture

### Directory Structure

The codebase follows **Feature-based Clean Architecture**:

```
lib/
├── main.dart                 # Entry point - Supabase/Firebase initialization
├── app.dart                  # Root MaterialApp & theme configuration
├── core/                     # App-wide shared resources
│   ├── theme/               # Design system (Material 3 theme, colors)
│   ├── constants/           # Global constants
│   └── utils/               # Utility functions
├── features/                # Feature modules (organized by domain)
│   ├── auth/                # Authentication (login, signup, LINE integration)
│   ├── home/                # Dashboard
│   ├── messages/            # Trainer-client messaging
│   ├── weight_records/      # Weight tracking
│   ├── meal_records/        # Meal logging
│   ├── exercise_records/    # Exercise tracking
│   └── goals/               # Goal management
├── services/                # Cross-cutting services (singletons)
│   ├── supabase_service.dart      # Database & auth backend
│   └── notification_service.dart  # FCM push notifications
└── shared/                  # Shared across features
    ├── models/              # Shared data models
    └── widgets/             # Shared UI components
```

### Feature Module Pattern

Each feature follows this structure:

```
features/{feature_name}/
├── models/                  # Data models (JSON serializable)
├── providers/               # Riverpod state management
└── presentation/
    ├── screens/            # Full-page screens
    └── widgets/            # Feature-specific components
```

**Key Principles:**
- Features are independent and loosely coupled
- Shared code goes in `shared/` or `core/`
- Services are injected via Riverpod providers
- Models use `json_serializable` for (de)serialization

### State Management with Riverpod

This project uses **Riverpod Code Generation** (v2.6.1+):

```dart
// Example provider definition
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'auth_provider.g.dart';

@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<User?> build() async {
    // Initialize state
    return await _fetchCurrentUser();
  }

  Future<void> signIn(String email, String password) async {
    // Mutation logic
  }
}

// Usage in widgets
final user = ref.watch(authNotifierProvider);
```

**Conventions:**
- Use `@riverpod` annotation for code generation
- Providers go in `features/*/providers/`
- Run `dart run build_runner watch` during development
- Use `AsyncValue` for async operations (loading/error handling)
- Prefer `ref.watch()` in build methods, `ref.read()` in callbacks

### Supabase Backend Integration

**Initialization:**
```dart
// main.dart
await dotenv.load(fileName: 'assets/.env');
await SupabaseService.initialize();
```

**Environment Variables:**
- `assets/.env` contains `SUPABASE_URL` and `SUPABASE_ANON_KEY`
- Never commit `.env` with real credentials

**Key Tables:**

| Table              | Purpose             | Key Features                                           |
| ------------------ | ------------------- | ------------------------------------------------------ |
| `trainers`         | Trainer profiles    | Auth integration, name, email, profile_image_url       |
| `clients`          | Client records      | Goal tracking, biometrics, trainer relationship, email |
| `messages`         | Trainer-client chat | Tags, replies, 5-min edit window, image attachments    |
| `weight_records`   | Weight logs         | Message integration, auto goal tracking                |
| `meal_records`     | Meal logs           | Nutrition tracking, message-sourced records            |
| `exercise_records` | Exercise logs       | 9 exercise types, image attachments                    |

**Database Functions:**
- `check_goal_achievement(client_id, weight)` - Returns true if client reached target
- `calculate_achievement_rate(client_id, weight)` - Returns progress percentage (0-100)
- `can_edit_message(message_id)` - Validates 5-minute edit window

**Row Level Security (RLS):**
- Messages: Users can only view/send messages they're part of
- Edit: Only within 5 minutes of creation
- Trainers: Anyone can read (for QR code flow), only self can update/insert
- Clients: Users can only access their own records

**Common Patterns:**
```dart
// Querying with Supabase
final records = await SupabaseService.client
  .from('weight_records')
  .select()
  .eq('client_id', clientId)
  .order('recorded_at', ascending: false)
  .limit(30);

// Real-time subscriptions
SupabaseService.client
  .from('messages')
  .stream(primaryKey: ['id'])
  .eq('receiver_id', userId)
  .listen((data) {
    // Handle new messages
  });
```

### Theme & Styling

The app uses **Material 3** with a centralized color system:

**Theme Configuration:**
- `core/theme/app_theme.dart` - MaterialApp theme definitions
- `core/theme/app_colors.dart` - Color constants

**Color Palette:**
```dart
// Primary colors
AppColors.primary         // Blue #2563EB
AppColors.primaryLight
AppColors.primaryDark

// Status colors
AppColors.success         // Green #10B981
AppColors.warning         // Orange #F59E0B
AppColors.error          // Red #EF4444

// Activity visualization (GitHub-style grass)
AppColors.grassLevel0    // No activity (gray)
AppColors.grassLevel1    // Low activity (light green)
AppColors.grassLevel2    // Medium activity
AppColors.grassLevel3    // High activity (dark green)
```

**Usage:**
```dart
Container(
  color: AppColors.primary,
  child: Text(
    'Title',
    style: Theme.of(context).textTheme.titleLarge,
  ),
)
```

## Important Conventions

### Code Generation

Always run code generation after modifying:
- Riverpod providers with `@riverpod` annotation
- Models with `@JsonSerializable()` annotation

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Message-Based Records

The app supports creating records (weight, meal, exercise) from messages:

**Pattern:**
1. User sends message with tag (e.g., "#体重 65.5kg")
2. Backend parses tag and creates record
3. Record stores `source='message'` and `message_id` reference

**When implementing parsers:**
- Extract tags from message content
- Create corresponding records in database
- Link back to original message via `message_id`

### Goal Achievement Logic

Weight records automatically check for goal achievement:

**Trigger Flow:**
```
INSERT weight_record
  → check_goal_achievement() function
  → If achieved: UPDATE clients SET goal_achieved_at = NOW()
  → calculate_achievement_rate() for progress percentage
```

**Implementation Note:**
- Supports both weight loss (initial > target) and weight gain (initial < target)
- Achievement rate clamped to 0-100%
- Display progress using `fl_chart` package

### Firebase Push Notifications

**Setup:**
- `services/notification_service.dart` handles FCM initialization
- Foreground & background message handling
- Local notifications for foreground messages

**Implementation:**
```dart
await NotificationService.initialize();
NotificationService.onMessageReceived((message) {
  // Handle notification tap
});
```

### Platform-Specific Notes

**iOS:**
- Ensure Firebase configuration in `ios/Runner/GoogleService-Info.plist`
- Push notification entitlements required

**Android:**
- Firebase configuration in `android/app/google-services.json`
- Notification channels configured in `NotificationService`

**macOS:**
- Supabase runs fine on macOS for development
- Entitlements may need adjustment for production

## Development Status

**Completed:**
- Project structure and architecture
- Supabase schema (8 tables with RLS policies)
- Theme system (Material 3)
- Service layer (Supabase, Firebase)

**In Progress:**
- Feature implementation (models, providers, UI)
- Authentication flow with LINE integration
- Real-time messaging
- Record tracking interfaces

**Current State:**
The codebase is in the scaffolding phase. Directory structure is complete but most feature files await implementation. Focus on implementing one feature at a time following the established patterns.

**Development Rules:**
- .envは覗かないこと
- 実装に関しては`docs/IMPLEMENTATION_TASKS.md`を参照して実装すること、また進捗を随時更新すること
- UIの作成・更新を行った場合、該当するUIのプレビュー関数を作成すること

### UI Preview Functions (Flutter Widget Previewer)

Flutter 3.35+のWidget Previewer機能を使用してUI開発を行います。

**基本パターン:**
```dart
import 'package:flutter/widget_previews.dart';

// Widget/Screenファイルの末尾にプレビュー関数を追加

@Preview(name: 'WidgetName - State')
Widget previewWidgetNameState() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: YourWidget(...),
        ),
      ),
    ),
  );
}
```

**Riverpodを使用するScreenの場合:**

Riverpodプロバイダーを使用するScreenはプロバイダーのオーバーライドが複雑なため、静的なヘルパーWidgetを作成してプレビューします。

```dart
// 静的プレビュー用ヘルパーWidget
class _PreviewComponentName extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // プロバイダーを使わずにUIを再現
    return Container(...);
  }
}

@Preview(name: 'ScreenName - Static Preview')
Widget previewScreenNameStatic() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      body: SafeArea(
        child: ListView(
          children: [
            _PreviewComponentA(),
            _PreviewComponentB(),
          ],
        ),
      ),
    ),
  );
}
```

**参考実装:** `lib/features/meal_records/presentation/screens/meal_record_screen.dart`

**プレビュー関数の命名規則:**
- `preview{WidgetName}{State}()` - 例: `previewMealCardBreakfast()`
- 複数の状態をプレビュー - Empty, Loading, WithData など

**プレビュー関数の機動コマンド:**
flutter widget-preview start

**Edge Functionの起動コマンド:**
supabase functions serve --no-verify-jwt

**Edge Functionのデプロイコマンド:**
supabase functions deploy parse-message-tags --no-verify-jwt

## Subagents（専門エージェント）

このプロジェクトには専門分野に特化したサブエージェント定義があります。

### 利用可能なサブエージェント

| エージェント         | ファイル                       | 用途                                  |
| -------------------- | ------------------------------ | ------------------------------------- |
| **Flutter UI Agent** | `.claude/agents/flutter-ui.md` | Widget/Screen作成、プレビュー関数生成 |
| **Supabase Agent**   | `.claude/agents/supabase.md`   | マイグレーション、Edge Functions、RLS |
| **Riverpod Agent**   | `.claude/agents/riverpod.md`   | Provider作成、状態管理パターン        |
| **Explore Agent**    | `.claude/agents/explore.md`    | コードベース調査・探索、実装箇所特定  |
| **Plan Agent**       | `.claude/agents/plan.md`       | 複雑なタスクの計画・設計、タスク分解  |

### 使用方法

各エージェントの詳細な指示は `.claude/agents/` ディレクトリ内のファイルを参照してください。

**Flutter UI Agent:**
- AppColors/AppThemeの使用ルール
- プレビュー関数の必須パターン
- Lucide Iconsの使用

**Supabase Agent:**
- マイグレーションファイルの命名規則
- Edge Function基本構造
- Database Function/Webhook設定

**Riverpod Agent:**
- コード生成パターン（@riverpod）
- Provider種類別の実装例
- 既存Provider一覧

**Explore Agent:**
- ファイル・コード検索パターン
- 依存関係調査方法
- 主要Provider一覧

**Plan Agent:**
- 実装計画の作成プロセス
- タスク分解の基準
- 担当エージェントの割り当て

### セッション継続

作業を再開するときは、まず以下を読むこと

- `docs/tasks/IMPLEMENTATION_TASKS.md` - 未着手タスクと進捗
- `docs/tasks/lessons.md` - 過去の失敗と学び

変更があった場合、上記を更新すること。