import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/data/weight_repository.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';

part 'health_sync_provider.g.dart';

/// 日付をキー文字列に変換するヘルパー
String dateKey(DateTime dt) =>
    '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';

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

    final startDate = settings.lastSyncAt ??
        DateTime.now().subtract(const Duration(days: 30));

    bool weightOk = false;
    bool sleepOk = false;

    // 体重同期（独立try/catch）
    if (settings.isWeightEnabled) {
      try {
        await _syncWeight(clientId, startDate);
        weightOk = true;
      } catch (e, st) {
        debugPrint('[HealthSync] Weight sync failed: $e\n$st');
      }
    } else {
      weightOk = true; // 無効化されてるので成功扱い
    }

    // 睡眠同期（独立try/catch）
    if (settings.isSleepEnabled) {
      try {
        await _syncSleep(clientId, startDate);
        sleepOk = true;
      } catch (e, st) {
        debugPrint('[HealthSync] Sleep sync failed: $e\n$st');
      }
    } else {
      sleepOk = true;
    }

    // 両方成功時のみ lastSyncAt 更新（失敗した片方は次回再試行）
    if (weightOk && sleepOk) {
      await ref
          .read(healthSettingsProvider.notifier)
          .updateLastSyncAt(DateTime.now());
    }
  }

  /// 体重同期ロジック（元の _sync から切り出し、振る舞いは同一）
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

    final filterResult = filterHealthData(
      healthDataDates: healthData.map((dp) => dp.dateFrom).toList(),
      existingRecords: existingRecords,
    );
    debugPrint(
      '[HealthSync] Weight: ${filterResult.importIndices.length} to import',
    );

    int inserted = 0;
    for (final index in filterResult.importIndices) {
      final dataPoint = healthData[index];
      final weightValue =
          (dataPoint.value as NumericHealthValue).numericValue.toDouble();

      try {
        await weightRepo.createWeightRecordWithSource(
          clientId: clientId,
          weight: weightValue,
          recordedAt: dataPoint.dateFrom,
          source: 'healthkit',
        );
        inserted++;
      } catch (e) {
        debugPrint('[HealthSync] Weight insert failed at $index: $e');
      }
    }

    if (inserted > 0) {
      ref.invalidate(weightRecordsProvider);
      ref.invalidate(latestWeightRecordProvider);
      ref.invalidate(weightStatsProvider);
    }
    debugPrint('[HealthSync] Weight: inserted $inserted');
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
