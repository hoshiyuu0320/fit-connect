import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/health/providers/health_sync_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';

/// テスト用のWeightRecordを生成するヘルパー
WeightRecord _makeRecord({
  required DateTime recordedAt,
  required String source,
  double weight = 65.0,
}) {
  return WeightRecord(
    id: 'test-${recordedAt.toIso8601String()}-$source',
    clientId: 'client-1',
    weight: weight,
    recordedAt: recordedAt,
    source: source,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

void main() {
  group('filterHealthData', () {
    test('メッセージ記録がある日のHealthKitデータをスキップする', () {
      final healthDataDates = [
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 2),
        DateTime(2026, 4, 3),
      ];

      final existingRecords = [
        _makeRecord(recordedAt: DateTime(2026, 4, 2), source: 'message'),
      ];

      final result = filterHealthData(
        healthDataDates: healthDataDates,
        existingRecords: existingRecords,
      );

      // 4/2はメッセージ記録があるのでスキップ、4/1と4/3はインポート対象
      expect(result.importIndices, [0, 2]);
    });

    test('メッセージ記録がない日のHealthKitデータをインポートする', () {
      final healthDataDates = [
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 2),
      ];

      final existingRecords = <WeightRecord>[];

      final result = filterHealthData(
        healthDataDates: healthDataDates,
        existingRecords: existingRecords,
      );

      expect(result.importIndices, [0, 1]);
    });

    test('ヘルスケア連携が無効の場合は空のインデックスを返す（設定チェックはProvider側）', () {
      // filterHealthData自体は設定を見ないが、データが空なら空を返す
      final result = filterHealthData(
        healthDataDates: [],
        existingRecords: [],
      );

      expect(result.importIndices, isEmpty);
    });

    test('既にHealthKit記録がある日は重複インポートしない', () {
      final healthDataDates = [
        DateTime(2026, 4, 1),
        DateTime(2026, 4, 2),
        DateTime(2026, 4, 3),
      ];

      final existingRecords = [
        _makeRecord(recordedAt: DateTime(2026, 4, 1), source: 'healthkit'),
        _makeRecord(recordedAt: DateTime(2026, 4, 3), source: 'healthkit'),
      ];

      final result = filterHealthData(
        healthDataDates: healthDataDates,
        existingRecords: existingRecords,
      );

      // 4/1と4/3は既にHealthKit記録があるのでスキップ、4/2のみインポート
      expect(result.importIndices, [1]);
    });

    test('メッセージ記録とHealthKit記録の両方がある場合の複合ケース', () {
      final healthDataDates = [
        DateTime(2026, 4, 1), // 既存HealthKit → スキップ
        DateTime(2026, 4, 2), // 既存メッセージ → スキップ
        DateTime(2026, 4, 3), // 記録なし → インポート
        DateTime(2026, 4, 4), // 記録なし → インポート
        DateTime(2026, 4, 5), // 既存HealthKit → スキップ
      ];

      final existingRecords = [
        _makeRecord(recordedAt: DateTime(2026, 4, 1), source: 'healthkit'),
        _makeRecord(recordedAt: DateTime(2026, 4, 2), source: 'message'),
        _makeRecord(recordedAt: DateTime(2026, 4, 5), source: 'healthkit'),
      ];

      final result = filterHealthData(
        healthDataDates: healthDataDates,
        existingRecords: existingRecords,
      );

      // 4/3と4/4のみインポート
      expect(result.importIndices, [2, 3]);
    });

    test('同じ日にメッセージとHealthKitの両方の既存記録がある場合はスキップ', () {
      final healthDataDates = [
        DateTime(2026, 4, 1),
      ];

      final existingRecords = [
        _makeRecord(recordedAt: DateTime(2026, 4, 1), source: 'message'),
        _makeRecord(recordedAt: DateTime(2026, 4, 1), source: 'healthkit'),
      ];

      final result = filterHealthData(
        healthDataDates: healthDataDates,
        existingRecords: existingRecords,
      );

      expect(result.importIndices, isEmpty);
    });
  });

  group('dateKey', () {
    test('日付を正しいフォーマットに変換する', () {
      expect(dateKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(dateKey(DateTime(2026, 12, 31)), '2026-12-31');
      expect(dateKey(DateTime(2026, 4, 1, 14, 30)), '2026-04-01');
    });

    test('時刻が異なっても同じ日なら同じキーになる', () {
      final morning = DateTime(2026, 4, 1, 8, 0);
      final evening = DateTime(2026, 4, 1, 20, 0);
      expect(dateKey(morning), dateKey(evening));
    });
  });
}
