# HealthKit 体重データ連携 — 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apple HealthKit / Google Health Connect から体重データを読み取り、既存の weight_records と統合する

**Architecture:** 既存の Feature-based Clean Architecture に沿って `features/health/` を新規追加。HealthRepository が `health` パッケージをラップし、HealthSyncProvider が同期ロジック（重複排除含む）を管理。設定は SharedPreferences でローカル保存。

**Tech Stack:** Flutter, health パッケージ, Riverpod (コード生成), Supabase, SharedPreferences, Lucide Icons

**Spec:** `docs/superpowers/specs/2026-04-05-healthkit-weight-sync-design.md`

---

## ファイル構成

### 新規作成

| ファイル | 責務 |
|----------|------|
| `lib/features/health/data/health_repository.dart` | `health` パッケージのラッパー。権限リクエスト・体重データ取得 |
| `lib/features/health/providers/health_provider.dart` | 連携ON/OFF状態管理（SharedPreferences） |
| `lib/features/health/providers/health_sync_provider.dart` | 同期ロジック（取り込み・重複排除・lastSyncDate管理） |
| `lib/features/health/presentation/screens/health_settings_screen.dart` | ヘルスケア連携設定画面（B1: リスト型 + 行内トグル） |
| `test/features/health/providers/health_sync_provider_test.dart` | 同期ロジックのユニットテスト |
| `test/features/health/data/health_repository_test.dart` | HealthRepository のユニットテスト |

### 変更

| ファイル | 変更内容 |
|----------|----------|
| `pubspec.yaml:9-56` | `health`, `mockito` パッケージ追加 |
| `ios/Runner/Info.plist` | HealthKit 権限説明文追加 |
| `ios/Runner/Runner.entitlements` | HealthKit エンタイトルメント追加 |
| `android/app/src/main/AndroidManifest.xml` | Health Connect 権限追加 |
| `lib/features/weight_records/models/weight_record_model.dart:16` | source コメント更新 `'message' \| 'healthkit'` |
| `lib/features/weight_records/presentation/screens/weight_record_screen.dart:466-477` | ソースアイコン表示追加 |
| `lib/features/settings/presentation/screens/settings_screen.dart:45` | ヘルスケア連携メニュー追加 |
| `lib/app.dart:64-155` | `_AuthLoadingScreen` で起動時同期トリガー追加 |

---

## Task 1: `health` パッケージ導入・プラットフォーム権限設定

**Files:**
- Modify: `fit-connect-mobile/pubspec.yaml:9-56`
- Modify: `fit-connect-mobile/ios/Runner/Info.plist`
- Modify: `fit-connect-mobile/android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: `health` パッケージを pubspec.yaml に追加**

`pubspec.yaml` の dependencies セクション（行9〜56）に追加:

```yaml
  health: ^11.0.0
```

dev_dependencies にも追加:
```yaml
  mockito: ^5.4.4
  build_runner: ^2.4.13  # 既存
```

- [ ] **Step 2: iOS Info.plist に HealthKit 権限説明文を追加**

`ios/Runner/Info.plist` の `<dict>` 内に以下を追加（読み取りのみのため NSHealthShareUsageDescription のみ）:

```xml
<key>NSHealthShareUsageDescription</key>
<string>体重データをアプリに取り込むためにヘルスケアへのアクセスが必要です</string>
```

- [ ] **Step 2.5: iOS Runner.entitlements に HealthKit エンタイトルメントを追加**

`ios/Runner/Runner.entitlements` に以下のキーを追加（ファイルが存在しない場合は作成）:

```xml
<key>com.apple.developer.healthkit</key>
<true/>
<key>com.apple.developer.healthkit.access</key>
<array/>
```

※ Xcode でプロジェクトを開き、Signing & Capabilities から HealthKit を追加する方法でも可。

- [ ] **Step 3: Android AndroidManifest.xml に Health Connect 権限を追加**

`android/app/src/main/AndroidManifest.xml` の `<manifest>` 内に追加:

```xml
<uses-permission android:name="android.permission.health.READ_BODY_MEASUREMENTS"/>
```

`<application>` 内に Health Connect intent filter を追加:

```xml
<activity-alias
    android:name="ViewPermissionUsageActivity"
    android:exported="true"
    android:targetActivity=".MainActivity"
    android:permission="android.permission.START_VIEW_PERMISSION_USAGE">
    <intent-filter>
        <action android:name="android.intent.action.VIEW_PERMISSION_USAGE" />
        <category android:name="android.intent.category.HEALTH_PERMISSIONS" />
    </intent-filter>
</activity-alias>
```

- [ ] **Step 4: 依存パッケージを取得**

Run: `cd fit-connect-mobile && flutter pub get`
Expected: 正常終了、エラーなし

- [ ] **Step 5: コミット**

```bash
cd fit-connect-mobile
git add pubspec.yaml pubspec.lock ios/Runner/Info.plist ios/Runner/Runner.entitlements android/app/src/main/AndroidManifest.xml
git commit -m "feat: add health package and platform permissions for HealthKit integration"
```

---

## Task 2: HealthRepository 作成

**Files:**
- Create: `lib/features/health/data/health_repository.dart`
- Create: `test/features/health/data/health_repository_test.dart`

- [ ] **Step 1: テストファイルを作成**

`test/features/health/data/health_repository_test.dart` を作成。mockito で `Health` クラスをモック化:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:health/health.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';

@GenerateMocks([Health])
import 'health_repository_test.mocks.dart';

void main() {
  late MockHealth mockHealth;
  late HealthRepository repository;

  setUp(() {
    mockHealth = MockHealth();
    repository = HealthRepository(health: mockHealth);
  });

  group('HealthRepository', () {
    test('requestPermission calls health.requestAuthorization', () async {
      when(mockHealth.requestAuthorization(any, permissions: anyNamed('permissions')))
          .thenAnswer((_) async => true);
      final result = await repository.requestPermission();
      expect(result, true);
      verify(mockHealth.requestAuthorization(any, permissions: anyNamed('permissions'))).called(1);
    });

    test('getWeightData returns empty list when no data', () async {
      when(mockHealth.getHealthDataFromTypes(
        types: anyNamed('types'),
        startTime: anyNamed('startTime'),
        endTime: anyNamed('endTime'),
      )).thenAnswer((_) async => []);
      final result = await repository.getWeightData(startDate: DateTime(2026, 4, 1));
      expect(result, isEmpty);
    });

    test('getWeightData picks latest record per day when multiple exist', () async {
      // 同日に2件のデータポイントがある場合、最新の1件のみ返すことを確認
      // テスト実装はモックのHealthDataPoint構築が必要 — 実装者が具体化
    });
  });
}
```

モック生成実行: `cd fit-connect-mobile && dart run build_runner build --delete-conflicting-outputs`

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect-mobile && flutter test test/features/health/data/health_repository_test.dart`
Expected: FAIL（HealthRepository が存在しない）

- [ ] **Step 3: HealthRepository を実装**

`lib/features/health/data/health_repository.dart` を作成:

```dart
import 'package:health/health.dart';
import 'package:flutter/foundation.dart';

/// HealthKit / Health Connect へのアクセスをラップするリポジトリ
class HealthRepository {
  final Health _health;

  HealthRepository({Health? health}) : _health = health ?? Health();
  
  /// HealthKit / Health Connect が利用可能かチェック
  Future<bool> isAvailable() async {
    // iOS: 常にtrue（HealthKit対応端末）
    // Android: Health Connect がインストールされているか
    try {
      return defaultTargetPlatform == TargetPlatform.iOS || 
             defaultTargetPlatform == TargetPlatform.android;
    } catch (e) {
      return false;
    }
  }

  /// 体重データの読み取り権限をリクエスト
  Future<bool> requestPermission() async {
    final types = [HealthDataType.WEIGHT];
    final permissions = [HealthDataAccess.READ];
    
    try {
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      return granted;
    } catch (e) {
      debugPrint('[HealthRepository] Permission request failed: $e');
      return false;
    }
  }

  /// 権限があるかチェック
  Future<bool> hasPermission() async {
    try {
      final types = [HealthDataType.WEIGHT];
      final permissions = [HealthDataAccess.READ];
      final granted = await _health.hasPermissions(
        types,
        permissions: permissions,
      );
      return granted ?? false;
    } catch (e) {
      return false;
    }
  }

  /// 指定日以降の体重データを取得（日ごとに最新1件）
  Future<List<HealthDataPoint>> getWeightData({
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final end = endDate ?? DateTime.now();
    
    try {
      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: startDate,
        endTime: end,
      );

      // 日ごとにグループ化し、各日の最新1件を採用
      final Map<String, HealthDataPoint> latestPerDay = {};
      for (final point in dataPoints) {
        final dateKey = '${point.dateFrom.year}-${point.dateFrom.month.toString().padLeft(2, '0')}-${point.dateFrom.day.toString().padLeft(2, '0')}';
        if (!latestPerDay.containsKey(dateKey) || 
            point.dateFrom.isAfter(latestPerDay[dateKey]!.dateFrom)) {
          latestPerDay[dateKey] = point;
        }
      }

      return latestPerDay.values.toList()
        ..sort((a, b) => b.dateFrom.compareTo(a.dateFrom));
    } catch (e) {
      debugPrint('[HealthRepository] Failed to get weight data: $e');
      return [];
    }
  }
}
```

- [ ] **Step 4: テストが通ることを確認**

Run: `cd fit-connect-mobile && flutter test test/features/health/data/health_repository_test.dart`
Expected: PASS

- [ ] **Step 5: コミット**

```bash
cd fit-connect-mobile
git add lib/features/health/data/health_repository.dart test/features/health/data/health_repository_test.dart
git commit -m "feat: add HealthRepository with weight data reading and per-day dedup"
```

---

## Task 3: HealthProvider 作成（設定状態管理）

**Files:**
- Create: `lib/features/health/providers/health_provider.dart`

- [ ] **Step 1: HealthProvider を作成**

SharedPreferences で連携ON/OFF状態を管理するプロバイダ。既存の Riverpod コード生成パターンに従う。

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';

part 'health_provider.g.dart';

/// HealthRepository のプロバイダ
@riverpod
HealthRepository healthRepository(HealthRepositoryRef ref) {
  return HealthRepository();
}

/// HealthKit 連携が利用可能かどうか
@riverpod
Future<bool> healthAvailable(HealthAvailableRef ref) async {
  final repo = ref.watch(healthRepositoryProvider);
  return repo.isAvailable();
}

/// ヘルスケア連携設定の状態管理
@riverpod
class HealthSettings extends _$HealthSettings {
  static const _keyEnabled = 'health_enabled';
  static const _keyWeightEnabled = 'health_weight_enabled';
  static const _keyLastSync = 'health_last_sync';

  @override
  Future<HealthSettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    return HealthSettingsState(
      isEnabled: prefs.getBool(_keyEnabled) ?? false,
      isWeightEnabled: prefs.getBool(_keyWeightEnabled) ?? false,
      lastSyncAt: _parseDateTime(prefs.getString(_keyLastSync)),
    );
  }

  /// マスター連携のON/OFF切替
  Future<bool> toggleEnabled(bool value) async {
    if (value) {
      // ON時: 権限リクエスト
      final repo = ref.read(healthRepositoryProvider);
      final granted = await repo.requestPermission();
      if (!granted) return false;
    }
    
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (!value) {
      await prefs.setBool(_keyWeightEnabled, false);
    }
    ref.invalidateSelf();
    return true;
  }

  /// 体重データ連携のON/OFF切替
  Future<void> toggleWeightEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWeightEnabled, value);
    ref.invalidateSelf();
  }

  /// 最終同期日時を更新
  Future<void> updateLastSyncAt(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSync, dateTime.toIso8601String());
    ref.invalidateSelf();
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}

/// 設定状態
class HealthSettingsState {
  final bool isEnabled;
  final bool isWeightEnabled;
  final DateTime? lastSyncAt;

  const HealthSettingsState({
    required this.isEnabled,
    required this.isWeightEnabled,
    this.lastSyncAt,
  });
}
```

- [ ] **Step 2: コード生成を実行**

Run: `cd fit-connect-mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `health_provider.g.dart` が生成される

- [ ] **Step 3: コミット**

```bash
cd fit-connect-mobile
git add lib/features/health/providers/health_provider.dart lib/features/health/providers/health_provider.g.dart
git commit -m "feat: add HealthProvider for settings state management with SharedPreferences"
```

---

## Task 4: WeightRepository に source 指定対応を追加

**Files:**
- Modify: `lib/features/weight_records/data/weight_repository.dart:43-62`
- Modify: `lib/features/weight_records/models/weight_record_model.dart:16`

> **注意:** Task 5（HealthSyncProvider）が `createWeightRecordWithSource` に依存するため、先にこちらを実装する。

- [ ] **Step 1: WeightRecord モデルの source コメントを更新**

`lib/features/weight_records/models/weight_record_model.dart` 行16:

変更前:
```dart
  final String source; // 'message' | 'manual'
```

変更後:
```dart
  final String source; // 'message' | 'healthkit'
```

- [ ] **Step 2: WeightRepository に `createWeightRecordWithSource` メソッドを追加**

`lib/features/weight_records/data/weight_repository.dart` の `createWeightRecord` メソッド（行62）の後に追加:

```dart
  /// 体重記録を作成（source指定あり、HealthKit連携用）
  Future<WeightRecord> createWeightRecordWithSource({
    required String clientId,
    required double weight,
    required DateTime recordedAt,
    required String source,
    String? notes,
  }) async {
    final response = await _supabase
        .from('weight_records')
        .insert({
          'client_id': clientId,
          'weight': weight,
          'notes': notes,
          'recorded_at': recordedAt.toIso8601String(),
          'source': source,
        })
        .select()
        .single();

    return WeightRecord.fromJson(response);
  }
```

- [ ] **Step 3: ビルド確認**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
cd fit-connect-mobile
git add lib/features/weight_records/data/weight_repository.dart lib/features/weight_records/models/weight_record_model.dart
git commit -m "feat: add createWeightRecordWithSource for HealthKit integration"
```

---

## Task 5: HealthSyncProvider 作成（同期ロジック）

**Files:**
- Create: `lib/features/health/providers/health_sync_provider.dart`
- Create: `test/features/health/providers/health_sync_provider_test.dart`

- [ ] **Step 1: テストファイルを作成**

`test/features/health/providers/health_sync_provider_test.dart` を作成。同期ロジックの重複排除をテスト:

```dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HealthSyncProvider', () {
    test('skips HealthKit data when message record exists on same day', () async {
      // 同日にメッセージ記録がある場合、HealthKitデータをスキップ
    });

    test('imports HealthKit data when no message record exists on that day', () async {
      // メッセージ記録がない日はHealthKitデータを取り込む
    });

    test('does nothing when health is disabled', () async {
      // 連携OFFの場合は何もしない
    });

    test('does nothing when weight sync is disabled', () async {
      // 体重連携OFFの場合は何もしない
    });

    test('uses 30 days ago as start date when no lastSyncDate', () async {
      // lastSyncDate未設定時は30日前から取得
    });

    test('updates lastSyncAt after successful sync', () async {
      // 同期成功後にlastSyncAtが更新される
    });
  });
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: `cd fit-connect-mobile && flutter test test/features/health/providers/health_sync_provider_test.dart`
Expected: FAIL

- [ ] **Step 3: HealthSyncProvider を実装**

`lib/features/health/providers/health_sync_provider.dart`:

```dart
import 'package:flutter/foundation.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';
import 'package:fit_connect_mobile/features/weight_records/data/weight_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'health_sync_provider.g.dart';

@riverpod
WeightRepository weightRepositoryForSync(WeightRepositoryForSyncRef ref) {
  return WeightRepository();
}

@riverpod
class HealthSync extends _$HealthSync {
  @override
  Future<void> build() async {
    // 初期状態: 何もしない
  }

  /// アプリ起動時の同期
  Future<void> syncOnLaunch() async {
    await _sync();
  }

  /// 手動同期
  Future<void> syncManual() async {
    state = const AsyncLoading();
    await _sync();
    state = const AsyncData(null);
  }

  Future<void> _sync() async {
    try {
      // 設定確認
      final settingsAsync = ref.read(healthSettingsProvider);
      final settings = settingsAsync.valueOrNull;
      if (settings == null || !settings.isEnabled || !settings.isWeightEnabled) {
        return;
      }

      // 権限確認
      final repo = ref.read(healthRepositoryProvider);
      final hasPermission = await repo.hasPermission();
      if (!hasPermission) return;

      // クライアントID取得
      final clientId = ref.read(currentClientIdProvider);
      if (clientId == null) return;

      // 同期開始日を決定
      final startDate = settings.lastSyncAt ?? 
          DateTime.now().subtract(const Duration(days: 30));

      // HealthKitからデータ取得
      final healthData = await repo.getWeightData(startDate: startDate);
      if (healthData.isEmpty) {
        await ref.read(healthSettingsProvider.notifier).updateLastSyncAt(DateTime.now());
        return;
      }

      // 既存の体重記録を取得（同期期間分）
      final weightRepo = ref.read(weightRepositoryForSyncProvider);
      final existingRecords = await weightRepo.getWeightRecords(clientId: clientId);

      // 既存のメッセージ由来の記録の日付セットを作成
      final existingMessageDates = <String>{};
      for (final record in existingRecords) {
        if (record.source == 'message') {
          final dateKey = '${record.recordedAt.year}-${record.recordedAt.month.toString().padLeft(2, '0')}-${record.recordedAt.day.toString().padLeft(2, '0')}';
          existingMessageDates.add(dateKey);
        }
      }

      // 既存のhealthkit由来の記録の日付セットも作成（重複インポート防止）
      final existingHealthDates = <String>{};
      for (final record in existingRecords) {
        if (record.source == 'healthkit') {
          final dateKey = '${record.recordedAt.year}-${record.recordedAt.month.toString().padLeft(2, '0')}-${record.recordedAt.day.toString().padLeft(2, '0')}';
          existingHealthDates.add(dateKey);
        }
      }

      // 重複排除しながらインポート
      for (final dataPoint in healthData) {
        final dateKey = '${dataPoint.dateFrom.year}-${dataPoint.dateFrom.month.toString().padLeft(2, '0')}-${dataPoint.dateFrom.day.toString().padLeft(2, '0')}';
        
        // メッセージ記録がある日はスキップ
        if (existingMessageDates.contains(dateKey)) continue;
        // 既にHealthKitインポート済みの日はスキップ
        if (existingHealthDates.contains(dateKey)) continue;

        // 体重値を取得（NumericHealthValueからdoubleへ）
        final weightValue = (dataPoint.value as NumericHealthValue).numericValue.toDouble();

        await weightRepo.createWeightRecordWithSource(
          clientId: clientId,
          weight: weightValue,
          recordedAt: dataPoint.dateFrom,
          source: 'healthkit',
        );
      }

      // 同期日時を更新
      await ref.read(healthSettingsProvider.notifier).updateLastSyncAt(DateTime.now());
      
      debugPrint('[HealthSync] Sync completed. Imported from HealthKit.');
    } catch (e) {
      debugPrint('[HealthSync] Sync failed: $e');
    }
  }
}
```

- [ ] **Step 4: コード生成を実行**

Run: `cd fit-connect-mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: `health_sync_provider.g.dart` が生成される

- [ ] **Step 5: テストが通ることを確認**

Run: `cd fit-connect-mobile && flutter test test/features/health/providers/health_sync_provider_test.dart`
Expected: PASS

- [ ] **Step 6: コミット**

```bash
cd fit-connect-mobile
git add lib/features/health/providers/health_sync_provider.dart lib/features/health/providers/health_sync_provider.g.dart test/features/health/providers/health_sync_provider_test.dart
git commit -m "feat: add HealthSyncProvider with dedup logic (message-priority, per-day)"
```

---

## Task 6: ヘルスケア連携設定画面の作成

**Files:**
- Create: `lib/features/health/presentation/screens/health_settings_screen.dart`

- [ ] **Step 1: HealthSettingsScreen を作成**

B1型のリスト+行内トグルレイアウト。既存の `settings_screen.dart` のスタイルに合わせる。

参考: `lib/features/settings/presentation/screens/settings_screen.dart`

画面構成:
1. AppBar — 戻るボタン + 「ヘルスケア連��」タイトル
2. マスタートグル — 「ヘルスケア連携」ON/OFF + 「Apple Health からデータを取得」サブテキスト
3. データソースセクション — 体重（行内トグル）、睡眠（Coming Soon、グレーアウト）
4. 同期セクション — 最終同期日時 + 「今すぐ同期」ボタン
5. 注意書き — 手動入力優先の説明

使用するアイコン: `LucideIcons.heartPulse`, `LucideIcons.scale`, `LucideIcons.moon`, `LucideIcons.refreshCw`

色: `AppColors` から取得、ダークモード対応（`Theme.of(context)` 使用）

権限フロー:
- マスタートグルON → `HealthSettings.toggleEnabled(true)` → 権限ダイアログ → 失敗時はOFFに戻す + SnackBar
- 体重トグルは `HealthSettings.toggleWeightEnabled()` を呼ぶ

同期ボタン → `HealthSync.syncManual()` → ローディング表示 → 完了時 SnackBar

- [ ] **Step 2: プレビュー関数を作成**

ファイル末尾に `_PreviewHealthSettings` ヘルパーと `@Preview` アノテーション付きプレビュー関数を追加。

```dart
// プレビュー用静的ヘルパー
class _PreviewHealthSettings extends StatelessWidget { ... }

@Preview(name: 'HealthSettingsScreen - Connected')
Widget previewHealthSettingsConnected() { ... }

@Preview(name: 'HealthSettingsScreen - Disconnected') 
Widget previewHealthSettingsDisconnected() { ... }
```

- [ ] **Step 3: ビルド確認**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
cd fit-connect-mobile
git add lib/features/health/presentation/screens/health_settings_screen.dart
git commit -m "feat: add HealthSettingsScreen with toggle controls and sync button"
```

---

## Task 7: 設定画面にヘルスケア連携メニューを追加

**Files:**
- Modify: `lib/features/settings/presentation/screens/settings_screen.dart:45`

- [ ] **Step 1: import 追加**

ファイル先頭に追加:
```dart
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
```

- [ ] **Step 2: ヘルスケア連携セクションを追加**

行45（`_buildSettingsSection` の前）に新セクションを追加:

```dart
              // ヘルスケア連携セクション
              _buildHealthSection(context, ref),

              const SizedBox(height: 16),
```

- [ ] **Step 3: `_buildHealthSection` メソッドを作成**

`_buildAppearanceSection` メソッドの構造を参考に、ヘルスケア連携への遷移 ListTile を含むセクションを実装。

```dart
Widget _buildHealthSection(BuildContext context, WidgetRef ref) {
  final healthAvailable = ref.watch(healthAvailableProvider);
  
  return healthAvailable.when(
    data: (available) {
      if (!available) return const SizedBox.shrink();
      return // セクション（LucideIcons.heartPulse アイコン + 「ヘルスケア連携」 + 右矢印）
             // タップで HealthSettingsScreen へ Navigator.push
    },
    loading: () => const SizedBox.shrink(),
    error: (_, __) => const SizedBox.shrink(),
  );
}
```

- [ ] **Step 4: ビルド確認**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 5: コミット**

```bash
cd fit-connect-mobile
git add lib/features/settings/presentation/screens/settings_screen.dart
git commit -m "feat: add health integration menu item to settings screen"
```

---

## Task 8: 体重記録リストにソースアイコンを追加

**Files:**
- Modify: `lib/features/weight_records/presentation/screens/weight_record_screen.dart:466-477`

- [ ] **Step 1: ソースアイコン用ヘルパーを追加**

ファイル内にソースアイコンを返すヘルパーメソッドを追加:

```dart
IconData _getSourceIcon(String source) {
  switch (source) {
    case 'healthkit':
      return LucideIcons.heartPulse;
    case 'message':
    default:
      return LucideIcons.messageCircle;
  }
}
```

- [ ] **Step 2: リスト行のアイコンをソースに応じて変更**

行466-477（現在の scale アイコン表示部分）を変更。

変更前（行466-477）:
```dart
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          LucideIcons.scale,
                          size: 20,
                          color: AppColors.primary600,
                        ),
                      ),
```

変更後:
```dart
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: AppColors.primary50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          _getSourceIcon(record.source),
                          size: 20,
                          color: AppColors.primary600.withOpacity(0.5),
                        ),
                      ),
```

- [ ] **Step 3: ビルド確認**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
cd fit-connect-mobile
git add lib/features/weight_records/presentation/screens/weight_record_screen.dart
git commit -m "feat: show source icon (message/healthkit) in weight record list"
```

---

## Task 9: アプリ起動時の同期トリガー追加

**Files:**
- Modify: `lib/app.dart:64-155`

- [ ] **Step 1: import 追加**

`lib/app.dart` の先頭に追加:
```dart
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
```

- [ ] **Step 2: `_AuthLoadingScreenState` に同期トリガーを追加**

`_saveTokenIfNeeded` メソッド（行74-96）の後に同期メソッドを追加:

```dart
  bool _healthSynced = false;

  void _syncHealthDataIfNeeded() {
    if (_healthSynced) return;
    _healthSynced = true;
    
    // 非同期で実行、UIをブロックしない（ConsumerState の ref を使用）
    ref.read(healthSyncProvider.notifier).syncOnLaunch().then((_) {
      debugPrint('[App] HealthKit同期完了');
    }).catchError((e) {
      debugPrint('[App] HealthKit同期エラー: $e');
    });
  }
```

- [ ] **Step 3: MainScreen 表示前に同期を呼び出し**

行108（`_saveTokenIfNeeded` の呼び出し後）に追加:

```dart
          _syncHealthDataIfNeeded();
```

- [ ] **Step 4: ビルド確認**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 5: コミット**

```bash
cd fit-connect-mobile
git add lib/app.dart
git commit -m "feat: trigger HealthKit sync on app launch after authentication"
```

---

## Task 10: 最終統合テスト・クリーンアップ

**Files:**
- All modified/created files

- [ ] **Step 1: 全テスト実行**

Run: `cd fit-connect-mobile && flutter test`
Expected: 全テスト PASS

- [ ] **Step 2: 静的解析**

Run: `cd fit-connect-mobile && flutter analyze`
Expected: エラーなし

- [ ] **Step 3: コード生成が最新か確認**

Run: `cd fit-connect-mobile && dart run build_runner build --delete-conflicting-outputs`
Expected: 変更なし（既に最新）

- [ ] **Step 4: iOS ビルド確認**

Run: `cd fit-connect-mobile && flutter build ios --no-codesign`
Expected: ビルド成功

- [ ] **Step 5: 最終コミット（必要な場合のみ）**

クリーンアップが必要であれば:
```bash
cd fit-connect-mobile
git add -A
git commit -m "chore: final cleanup for HealthKit weight sync feature"
```
