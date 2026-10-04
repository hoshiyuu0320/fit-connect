import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/data/meal_repository.dart';
import 'package:fit_connect_mobile/features/meal_records/models/meal_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// 食事の画面テスト用の偽リポジトリ（Supabase に出ない）。
/// 本物と同じ向きで期間・日付の範囲を絞る。
class FakeMealRepository implements MealRepository {
  FakeMealRepository(this.records, {this.failWith});

  final List<MealRecord> records;

  /// 非 null なら一覧の取得がこの例外で失敗する
  Object? failWith;

  /// 一覧の取得を呼んだ回数
  int listCalls = 0;

  /// 非 null のあいだは一覧の取得が完了しない（読込中の見た目を確かめる）
  Completer<void>? gate;

  @override
  Future<List<MealRecord>> getMealRecords({
    required String clientId,
    PeriodFilter? period,
    String? mealType,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    listCalls++;
    if (gate != null) await gate!.future;
    if (failWith != null) throw failWith!;
    final result = records.where((r) {
      if (startDate != null || endDate != null) {
        if (startDate != null && r.recordedAt.isBefore(startDate)) {
          return false;
        }
        if (endDate != null && r.recordedAt.isAfter(endDate)) return false;
        return true;
      }
      if (period != null && period != PeriodFilter.all) {
        return !r.recordedAt.isBefore(period.getStartDate());
      }
      return true;
    }).toList()
      ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));
    return result;
  }

  @override
  Future<Map<DateTime, int>> getMealRecordCounts({
    required String clientId,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    final counts = <DateTime, int>{};
    for (final r in records) {
      if (r.recordedAt.isBefore(startDate) || r.recordedAt.isAfter(endDate)) {
        continue;
      }
      final day =
          DateTime(r.recordedAt.year, r.recordedAt.month, r.recordedAt.day);
      counts[day] = (counts[day] ?? 0) + 1;
    }
    return counts;
  }

  @override
  Future<int> getTodayMealCount(String clientId) async => 0;

  @override
  Future<MealRecord> createMealRecord({
    required String clientId,
    required String mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<MealRecord> updateMealRecord({
    required String id,
    String? mealType,
    String? notes,
    List<String>? images,
    double? calories,
    DateTime? recordedAt,
  }) =>
      throw UnimplementedError();

  @override
  Future<void> deleteMealRecord(String id) => throw UnimplementedError();
}

MealRecord testMeal(
  String id,
  String type,
  DateTime recordedAt, {
  String? notes,
  List<String>? images,
  double? calories,
  double? protein,
  double? fat,
  double? carbs,
  bool estimatedByAi = false,
}) {
  return MealRecord(
    id: id,
    clientId: 'client-1',
    mealType: type,
    notes: notes,
    images: images,
    calories: calories,
    proteinG: protein,
    fatG: fat,
    carbsG: carbs,
    estimatedByAi: estimatedByAi,
    recordedAt: recordedAt,
    source: 'message',
    createdAt: recordedAt,
    updatedAt: recordedAt,
  );
}

/// 今日の指定時刻
DateTime todayAt(int hour, int minute) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day, hour, minute);
}

/// 縦に長い画面（一覧の下の方まで作られるように）で pump する
Future<void> pumpMealScreen(
  WidgetTester tester,
  Widget screen, {
  required FakeMealRepository repository,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 2600),
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentClientIdProvider.overrideWith((ref) => 'client-1'),
        mealRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(body: screen),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
