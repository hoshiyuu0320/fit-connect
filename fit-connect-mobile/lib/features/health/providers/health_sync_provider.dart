import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/data/weight_repository.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/services/notification_service.dart';

part 'health_sync_provider.g.dart';

/// 日付をキー文字列に変換するヘルパー（必ずローカル時刻ベース）
///
/// HealthKit の dateFrom と DB から復元した recordedAt のタイムゾーンが
/// ばらつく可能性があるため、`.toLocal()` で正規化してから日付化する。
String dateKey(DateTime dt) {
  final local = dt.toLocal();
  return '${local.year}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

/// HealthKitデータのフィルタリング結果
class HealthDataFilterResult {
  /// インポートすべきデータポイントのインデックスリスト
  final List<int> importIndices;

  const HealthDataFilterResult({required this.importIndices});
}

/// HealthKitデータの重複排除フィルタ（テスト可能な純粋関数）
///
/// ルール:
/// 1. メッセージ由来の記録がある日はスキップ（メッセージ優先）
/// 2. 既にHealthKit由来の記録がある日はスキップ（重複インポート防止）
/// 3. 上記に該当しない日のデータのみインポート対象
HealthDataFilterResult filterHealthData({
  required List<DateTime> healthDataDates,
  required List<WeightRecord> existingRecords,
}) {
  // 既存のメッセージ由来記録の日付セット
  final existingMessageDates = <String>{};
  for (final record in existingRecords) {
    if (record.source == 'message') {
      existingMessageDates.add(dateKey(record.recordedAt));
    }
  }

  // 既存のHealthKit由来記録の日付セット
  final existingHealthDates = <String>{};
  for (final record in existingRecords) {
    if (record.source == 'healthkit') {
      existingHealthDates.add(dateKey(record.recordedAt));
    }
  }

  final importIndices = <int>[];
  for (var i = 0; i < healthDataDates.length; i++) {
    final key = dateKey(healthDataDates[i]);
    // メッセージ記録がある日はスキップ
    if (existingMessageDates.contains(key)) continue;
    // 既にHealthKitインポート済みの日はスキップ
    if (existingHealthDates.contains(key)) continue;
    importIndices.add(i);
  }

  return HealthDataFilterResult(importIndices: importIndices);
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
    final settingsAsync = ref.read(healthSettingsProvider);
    final settings = settingsAsync.valueOrNull;
    if (settings == null || !settings.isEnabled) {
      debugPrint('[HealthSync] Skipped: master toggle off');
      return;
    }

    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) {
      debugPrint('[HealthSync] Skipped: no clientId');
      return;
    }

    final settingsNotifier = ref.read(healthSettingsProvider.notifier);

    // 同期開始: status を syncing に
    await settingsNotifier.updateSyncResult(
      status: HealthSyncStatus.syncing,
    );

    // HealthKit/Health Connect のクエリ範囲は常に過去30日。
    // `lastSyncAt` を startDate に使うと、ユーザーが Apple Health で
    // バックデート登録したサンプル（例: 朝8:57に体重を記録 → 9:35にアプリ起動 →
    // lastSyncAt=9:35 で次回 sync すると 8:57 のサンプルがクエリ範囲外）を
    // 取りこぼすため、毎回フル30日を読み直して `filterHealthData` /
    // `upsertObjectiveData` の冪等性に依存する。
    final startDate = DateTime.now().subtract(const Duration(days: 30));

    String? weightError;
    String? sleepError;

    // 体重同期（リトライ付き）
    if (settings.isWeightEnabled) {
      try {
        await _runWithRetry(
          () => _syncWeight(clientId, startDate),
          label: 'Weight',
        );
      } catch (e) {
        weightError = '体重: $e';
        debugPrint('[HealthSync] Weight sync failed after retries: $e');
      }
    }

    // 睡眠同期（リトライ付き）
    if (settings.isSleepEnabled) {
      try {
        await _runWithRetry(
          () => _syncSleep(clientId, startDate),
          label: 'Sleep',
        );
      } catch (e) {
        sleepError = '睡眠: $e';
        debugPrint('[HealthSync] Sleep sync failed after retries: $e');
      }
    }

    final hasError = weightError != null || sleepError != null;

    if (!hasError) {
      // 全成功 → lastSyncAt 更新 + status=success
      await settingsNotifier.updateSyncResult(
        status: HealthSyncStatus.success,
        error: null,
        syncedAt: DateTime.now(),
      );
    } else {
      // 一部または全失敗 → status=error, lastSyncAt は更新しない
      final combinedMessage =
          [weightError, sleepError].whereType<String>().join(' / ');
      await settingsNotifier.updateSyncResult(
        status: HealthSyncStatus.error,
        error: combinedMessage,
      );

      // ローカル通知（iOS/Android のみ）
      if (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.android)) {
        await NotificationService.showSyncErrorNotification(combinedMessage);
      }
    }
  }

  /// 指数バックオフでリトライ。最大3回（初回 + 2リトライ）、1s/2s 待機。
  Future<void> _runWithRetry(
    Future<void> Function() task, {
    required String label,
  }) async {
    const maxAttempts = 3;
    Duration delay = const Duration(seconds: 1);
    Object? lastError;
    StackTrace? lastStack;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await task();
        if (attempt > 1) {
          debugPrint('[HealthSync] $label: succeeded on attempt $attempt');
        }
        return;
      } catch (e, st) {
        lastError = e;
        lastStack = st;
        debugPrint(
          '[HealthSync] $label attempt $attempt/$maxAttempts failed: $e',
        );
        if (attempt < maxAttempts) {
          await Future.delayed(delay);
          delay *= 2;
        }
      }
    }
    Error.throwWithStackTrace(lastError!, lastStack ?? StackTrace.current);
  }

  /// 体重同期ロジック
  /// - 既存に message/manual レコードあり → skip（ユーザー入力優先）
  /// - 既存に healthkit レコードあり & 値が変わっている → UPDATE
  /// - 既存に healthkit レコードあり & 値が同じ → skip
  /// - 既存なし → INSERT
  Future<void> _syncWeight(String clientId, DateTime startDate) async {
    final repo = ref.read(healthRepositoryProvider);
    final hasPermission = await repo.hasPermission();
    if (!hasPermission) {
      debugPrint('[HealthSync] Weight: no HealthKit permission');
      return;
    }

    debugPrint('[HealthSync] Weight: fetching from $startDate');
    final healthData = await repo.getWeightData(startDate: startDate);
    debugPrint('[HealthSync] Weight: fetched ${healthData.length} points');

    if (healthData.isEmpty) return;

    final weightRepo = WeightRepository();
    final existingRecords = await weightRepo.getWeightRecords(clientId: clientId);

    // 日付 → 既存レコード のマップを構築（同じ日に複数あれば message/manual 優先）
    final existingByDate = <String, WeightRecord>{};
    for (final r in existingRecords) {
      final key = dateKey(r.recordedAt);
      final current = existingByDate[key];
      if (current == null) {
        existingByDate[key] = r;
      } else {
        // 優先度: message > manual > healthkit
        final priority = {'message': 3, 'manual': 2, 'healthkit': 1};
        final newP = priority[r.source] ?? 0;
        final curP = priority[current.source] ?? 0;
        if (newP > curP) existingByDate[key] = r;
      }
    }

    int inserted = 0;
    int updated = 0;
    int skippedNoChange = 0;
    int skippedUserSource = 0;

    for (final dataPoint in healthData) {
      final weightValue =
          (dataPoint.value as NumericHealthValue).numericValue.toDouble();
      final key = dateKey(dataPoint.dateFrom);
      final existing = existingByDate[key];

      try {
        if (existing == null) {
          await weightRepo.createWeightRecordWithSource(
            clientId: clientId,
            weight: weightValue,
            recordedAt: dataPoint.dateFrom,
            source: 'healthkit',
          );
          inserted++;
        } else if (existing.source == 'message' ||
            existing.source == 'manual') {
          skippedUserSource++;
        } else if (existing.source == 'healthkit') {
          // 値が違うときだけ UPDATE（== 比較は浮動小数誤差に弱いため小数2桁で比較）
          final sameValue =
              (existing.weight - weightValue).abs() < 0.005;
          if (sameValue) {
            skippedNoChange++;
          } else {
            await weightRepo.updateWeightRecord(
              id: existing.id,
              weight: weightValue,
              recordedAt: dataPoint.dateFrom,
            );
            updated++;
            debugPrint(
              '[HealthSync] Weight: $key updated ${existing.weight} → $weightValue',
            );
          }
        } else {
          // 未知の source → 安全側で skip
          skippedUserSource++;
        }
      } catch (e) {
        debugPrint('[HealthSync] Weight write failed for $key: $e');
      }
    }

    debugPrint(
      '[HealthSync] Weight: inserted=$inserted updated=$updated '
      'skipped(user)=$skippedUserSource skipped(noChange)=$skippedNoChange',
    );

    if (inserted > 0 || updated > 0) {
      ref.invalidate(weightRecordsProvider);
      ref.invalidate(latestWeightRecordProvider);
      ref.invalidate(weightStatsProvider);
    }
  }

  /// 睡眠同期ロジック（HealthKit から取得 → UPSERT）
  Future<void> _syncSleep(String clientId, DateTime startDate) async {
    final repo = ref.read(healthRepositoryProvider);
    final hasPermission = await repo.hasPermission(forSleep: true);
    if (!hasPermission) {
      debugPrint('[HealthSync] Sleep: no HealthKit permission');
      return;
    }

    debugPrint('[HealthSync] Sleep: fetching from $startDate');
    final sessionsByDate = await repo.getSleepData(startDate: startDate);
    debugPrint(
      '[HealthSync] Sleep: fetched ${sessionsByDate.length} sessions',
    );

    if (sessionsByDate.isEmpty) return;

    final sleepNotifier = ref.read(sleepRecordsProvider().notifier);
    int upserted = 0;
    for (final entry in sessionsByDate.entries) {
      final recordedDate = entry.key;
      final s = entry.value;
      try {
        await sleepNotifier.upsertObjectiveData(
          recordedDate: recordedDate,
          bedTime: s.bedTime,
          wakeTime: s.wakeTime,
          totalSleepMinutes: s.totalSleepMinutes,
          deepMinutes: s.deepMinutes,
          lightMinutes: s.lightMinutes,
          remMinutes: s.remMinutes,
          awakeMinutes: s.awakeMinutes,
        );
        upserted++;
      } catch (e) {
        debugPrint('[HealthSync] Sleep upsert failed for $recordedDate: $e');
      }
    }

    if (upserted > 0) {
      ref.invalidate(todaySleepRecordProvider);
      ref.invalidate(recentSleepRecordsProvider);
    }
    debugPrint('[HealthSync] Sleep: upserted $upserted');
  }
}
