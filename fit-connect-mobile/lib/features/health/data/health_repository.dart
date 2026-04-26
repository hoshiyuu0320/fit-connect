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

  /// 体重（+任意で睡眠）データの読み取り権限をリクエスト
  Future<bool> requestPermission({bool includeSleep = false}) async {
    final types = <HealthDataType>[HealthDataType.WEIGHT];
    if (includeSleep) {
      types.addAll([
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
        HealthDataType.SLEEP_IN_BED,
      ]);
    }
    final permissions = List.filled(types.length, HealthDataAccess.READ);

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
  Future<bool> hasPermission({bool forSleep = false}) async {
    try {
      final types = forSleep
          ? <HealthDataType>[
              HealthDataType.SLEEP_ASLEEP,
              HealthDataType.SLEEP_DEEP,
              HealthDataType.SLEEP_LIGHT,
              HealthDataType.SLEEP_REM,
              HealthDataType.SLEEP_AWAKE,
              HealthDataType.SLEEP_IN_BED,
            ]
          : <HealthDataType>[HealthDataType.WEIGHT];
      final permissions = List.filled(types.length, HealthDataAccess.READ);
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

  /// 起床日ごとにメインセッション1件の集計を返す。
  /// 返却: `Map<recordedDate(YYYY-MM-DD JST), SleepSessionData>`
  Future<Map<String, SleepSessionData>> getSleepData({
    required DateTime startDate,
    DateTime? endDate,
  }) async {
    final end = endDate ?? DateTime.now().add(const Duration(days: 1));

    const sleepTypes = [
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_IN_BED,
    ];

    try {
      final data = await _health.getHealthDataFromTypes(
        types: sleepTypes,
        startTime: startDate,
        endTime: end,
      );

      // 起床日キー（wake側=dateTo の JST 日付）でグループ化
      final byDate = <String, List<HealthDataPoint>>{};
      for (final p in data) {
        final jst = p.dateTo.toUtc().add(const Duration(hours: 9));
        final key = '${jst.year.toString().padLeft(4, '0')}-'
            '${jst.month.toString().padLeft(2, '0')}-'
            '${jst.day.toString().padLeft(2, '0')}';
        byDate.putIfAbsent(key, () => []).add(p);
      }

      final result = <String, SleepSessionData>{};
      byDate.forEach((date, points) {
        final session = _aggregateMainSession(points);
        if (session != null) result[date] = session;
      });
      return result;
    } catch (e) {
      debugPrint('[HealthRepository] Failed to get sleep data: $e');
      return {};
    }
  }

  /// メインセッション集計。
  /// その日の全 sleep セグメントを dateFrom 順にソートし、
  /// 最早開始〜最遅終了 を主セッションとみなし、ステージ別合計分を算出
  SleepSessionData? _aggregateMainSession(List<HealthDataPoint> points) {
    if (points.isEmpty) return null;

    points.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
    final bed = points.first.dateFrom;
    final wake = points.map((p) => p.dateTo).reduce((a, b) => a.isAfter(b) ? a : b);

    var deep = 0, light = 0, rem = 0, awake = 0, asleep = 0;
    for (final p in points) {
      final mins = p.dateTo.difference(p.dateFrom).inMinutes;
      switch (p.type) {
        case HealthDataType.SLEEP_DEEP:
          deep += mins;
          break;
        case HealthDataType.SLEEP_LIGHT:
          light += mins;
          break;
        case HealthDataType.SLEEP_REM:
          rem += mins;
          break;
        case HealthDataType.SLEEP_AWAKE:
          awake += mins;
          break;
        case HealthDataType.SLEEP_ASLEEP:
          asleep += mins;
          break;
        case HealthDataType.SLEEP_IN_BED:
          // 時間計算には含めない（在床時間は総睡眠時間とは別概念）
          break;
        default:
          break;
      }
    }

    // ステージ明細あり → 合算、無ければ ASLEEP に寄せる
    final total = (deep + light + rem) > 0
        ? deep + light + rem + awake
        : asleep + awake;
    if (total <= 0) return null;

    return SleepSessionData(
      bedTime: bed,
      wakeTime: wake,
      totalSleepMinutes: total,
      deepMinutes: deep,
      lightMinutes: light,
      remMinutes: rem,
      awakeMinutes: awake,
    );
  }
}

/// HealthKit/Health Connect から集計された1日分の睡眠セッション
class SleepSessionData {
  final DateTime bedTime;
  final DateTime wakeTime;
  final int totalSleepMinutes;
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;

  const SleepSessionData({
    required this.bedTime,
    required this.wakeTime,
    required this.totalSleepMinutes,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
  });
}
