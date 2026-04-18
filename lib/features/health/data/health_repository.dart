import 'package:health/health.dart';
import 'package:flutter/foundation.dart';

/// HealthKit / Health Connect へのアクセスをラップするリポジトリ
class HealthRepository {
  final Health _health;

  HealthRepository({Health? health}) : _health = health ?? Health();

  /// HealthKit / Health Connect が利用可能かチェック
  Future<bool> isAvailable() async {
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
      if (defaultTargetPlatform == TargetPlatform.iOS) {
        return granted ?? true;
      }
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
    // Apple Health等は当日分レコードに end-of-day の timestamp を付けることがあるため、
    // 明日の 00:00 まで範囲を広げて取りこぼしを防ぐ（日付でdedupされるので二重インポートの心配はない）
    final end = endDate ?? DateTime.now().add(const Duration(days: 1));

    try {
      final dataPoints = await _health.getHealthDataFromTypes(
        types: [HealthDataType.WEIGHT],
        startTime: startDate,
        endTime: end,
      );

      // 日ごとにグループ化し、各日の最新1件を採用
      final Map<String, HealthDataPoint> latestPerDay = {};
      for (final point in dataPoints) {
        final dateKey =
            '${point.dateFrom.year}-${point.dateFrom.month.toString().padLeft(2, '0')}-${point.dateFrom.day.toString().padLeft(2, '0')}';
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
