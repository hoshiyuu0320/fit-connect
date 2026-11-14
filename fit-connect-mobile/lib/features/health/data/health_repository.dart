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

  /// 睡眠として扱う型（権限リクエスト・権限チェック・取得で共通）
  /// SLEEP_IN_BED は Health Connect に無い（health 11.1.1 では iOS 専用）ため、
  /// Android ではセッション全体の SLEEP_SESSION（権限は READ_SLEEP）を使う
  List<HealthDataType> get _sleepTypes => [
        HealthDataType.SLEEP_ASLEEP,
        HealthDataType.SLEEP_DEEP,
        HealthDataType.SLEEP_LIGHT,
        HealthDataType.SLEEP_REM,
        HealthDataType.SLEEP_AWAKE,
        defaultTargetPlatform == TargetPlatform.android
            ? HealthDataType.SLEEP_SESSION
            : HealthDataType.SLEEP_IN_BED,
      ];

  /// 体重（+任意で睡眠）データの読み取り権限をリクエスト
  Future<bool> requestPermission({bool includeSleep = false}) async {
    final types = <HealthDataType>[HealthDataType.WEIGHT];
    if (includeSleep) {
      types.addAll(_sleepTypes);
    }
    final permissions = List.filled(types.length, HealthDataAccess.READ);

    try {
      final granted = await _health.requestAuthorization(
        types,
        permissions: permissions,
      );
      // Health Connect は要求のうち1つでも許可済みなら true を返す（睡眠を拒否しても
      // 体重が許可済みなら true）ため、Android では全部許可されたかを確かめ直す
      if (granted && defaultTargetPlatform == TargetPlatform.android) {
        final allGranted = await _health.hasPermissions(
          types,
          permissions: permissions,
        );
        return allGranted ?? false;
      }
      return granted;
    } catch (e) {
      debugPrint('[HealthRepository] Permission request failed: $e');
      return false;
    }
  }

  /// 権限があるかチェック
  Future<bool> hasPermission({bool forSleep = false}) async {
    try {
      final types =
          forSleep ? _sleepTypes : <HealthDataType>[HealthDataType.WEIGHT];
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

    try {
      final data = await _health.getHealthDataFromTypes(
        types: _sleepTypes,
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
    final wake =
        points.map((p) => p.dateTo).reduce((a, b) => a.isAfter(b) ? a : b);

    var deep = 0, light = 0, rem = 0, awake = 0, asleep = 0, session = 0;
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
        case HealthDataType.SLEEP_SESSION:
          // Android のセッション全体。ステージと重なるのでステージ別には足さない
          session += mins;
          break;
        default:
          break;
      }
    }

    // ステージ明細あり → 合算、無ければ ASLEEP に寄せる
    final stageTotal =
        (deep + light + rem) > 0 ? deep + light + rem + awake : asleep + awake;
    // Health Connect ではステージは任意（セッションだけを書くアプリもある）ため、
    // ステージが無いときだけセッションの長さを総睡眠時間とする
    final total = stageTotal > 0 ? stageTotal : session;
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
