import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/data/weight_repository.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';

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
    try {
      final settingsAsync = ref.read(healthSettingsProvider);
      final settings = settingsAsync.valueOrNull;
      if (settings == null ||
          !settings.isEnabled ||
          !settings.isWeightEnabled) {
        debugPrint(
          '[HealthSync] Skipped: settings not enabled '
          '(settings=${settings != null}, isEnabled=${settings?.isEnabled}, isWeightEnabled=${settings?.isWeightEnabled})',
        );
        return;
      }

      final repo = ref.read(healthRepositoryProvider);
      final hasPermission = await repo.hasPermission();
      if (!hasPermission) {
        debugPrint('[HealthSync] Skipped: no HealthKit permission');
        return;
      }

      final clientId = ref.read(currentClientIdProvider);
      if (clientId == null) {
        debugPrint('[HealthSync] Skipped: no clientId');
        return;
      }

      final startDate = settings.lastSyncAt ??
          DateTime.now().subtract(const Duration(days: 30));
      debugPrint('[HealthSync] Fetching HealthKit data from $startDate');

      final healthData = await repo.getWeightData(startDate: startDate);
      debugPrint(
        '[HealthSync] Fetched ${healthData.length} data points from HealthKit',
      );

      if (healthData.isEmpty) {
        await ref
            .read(healthSettingsProvider.notifier)
            .updateLastSyncAt(DateTime.now());
        return;
      }

      final weightRepo = WeightRepository();
      final existingRecords =
          await weightRepo.getWeightRecords(clientId: clientId);

      final filterResult = filterHealthData(
        healthDataDates: healthData.map((dp) => dp.dateFrom).toList(),
        existingRecords: existingRecords,
      );
      debugPrint(
        '[HealthSync] ${filterResult.importIndices.length} points to import after filtering',
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
          debugPrint('[HealthSync] Insert failed at index $index: $e');
        }
      }
      debugPrint('[HealthSync] Inserted $inserted rows');

      await ref
          .read(healthSettingsProvider.notifier)
          .updateLastSyncAt(DateTime.now());

      if (inserted > 0) {
        ref.invalidate(weightRecordsProvider);
        ref.invalidate(latestWeightRecordProvider);
        ref.invalidate(weightStatsProvider);
      }

      debugPrint(
        '[HealthSync] Sync completed. Imported $inserted records from HealthKit.',
      );
    } catch (e, st) {
      debugPrint('[HealthSync] Sync failed: $e\n$st');
    }
  }
}
