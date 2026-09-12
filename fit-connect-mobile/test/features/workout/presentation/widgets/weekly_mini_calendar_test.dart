import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/workout_assignment_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/widgets/weekly_mini_calendar.dart';

/// 今週の月曜日を返す（WeeklyMiniCalendar内部の _getThisMonday と同じ計算）。
/// 下記フィクスチャは完了済みアサインメントを月曜日そのもの（インデックス0）に置くため、
/// `monday.add(Duration(days: 0))` は恒等写像になり、ウィジェット内部のDST依存な
/// `DateTime.add(Duration(days: n))` 経路は実際には通らない。フィクスチャを他の曜日に
/// 移した場合、DSTで時刻がずれるタイムゾーンに限り DateTime キーの等価比較が壊れうる。
DateTime _getThisMonday() {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final offset = today.weekday - 1;
  return today.subtract(Duration(days: offset));
}

/// assignedDate文字列 "YYYY-MM-DD" を組み立てるヘルパー
String _fmtDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// 完了ステータスの WorkoutAssignment を1件持つ weeklyData を組み立てる
/// (今週の月曜日を完了扱いにする)
Map<DateTime, List<WorkoutAssignment>> _buildWeeklyDataWithCompleted() {
  final monday = _getThisMonday();
  return {
    monday: [
      WorkoutAssignment(
        id: 'test-completed-1',
        clientId: 'client-1',
        trainerId: 'trainer-1',
        planId: 'plan-1',
        assignedDate: _fmtDate(monday),
        status: 'completed',
      ),
    ],
  };
}

Future<void> _pumpCalendar(WidgetTester tester, ThemeData theme) async {
  final weeklyData = _buildWeeklyDataWithCompleted();
  await tester.pumpWidget(
    MaterialApp(
      theme: theme,
      home: Scaffold(
        body: WeeklyMiniCalendar(weeklyData: weeklyData),
      ),
    ),
  );
}

void main() {
  group('WeeklyMiniCalendar - completed cell background', () {
    testWidgets(
      'ダークモードで完了セルの背景が successTint(dark) になり、固定のemerald50は使われない',
      (tester) async {
        await _pumpCalendar(tester, AppTheme.darkTheme);

        final containers = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(WeeklyMiniCalendar),
                matching: find.byType(Container),
              ),
            )
            .toList();

        final hasSuccessTintDark = containers.any((c) {
          final decoration = c.decoration;
          if (decoration is! BoxDecoration) return false;
          return decoration.color == AppColorsExtension.dark.successTint;
        });
        final hasFixedEmerald50 = containers.any((c) {
          final decoration = c.decoration;
          if (decoration is! BoxDecoration) return false;
          return decoration.color == AppColors.emerald50;
        });

        expect(
          hasSuccessTintDark,
          isTrue,
          reason: 'ダークモードでは successTint(dark) の背景セルが存在するべき',
        );
        expect(
          hasFixedEmerald50,
          isFalse,
          reason: 'ダークモードで固定色 emerald50 の背景が使われてはいけない',
        );
      },
    );

    testWidgets(
      'ライトモードで完了セルの背景が successTint(light) になる',
      (tester) async {
        await _pumpCalendar(tester, AppTheme.lightTheme);

        final containers = tester
            .widgetList<Container>(
              find.descendant(
                of: find.byType(WeeklyMiniCalendar),
                matching: find.byType(Container),
              ),
            )
            .toList();

        final hasSuccessTintLight = containers.any((c) {
          final decoration = c.decoration;
          if (decoration is! BoxDecoration) return false;
          return decoration.color == AppColorsExtension.light.successTint;
        });

        expect(
          hasSuccessTintLight,
          isTrue,
          reason: 'ライトモードでは successTint(light) の背景セルが存在するべき',
        );
      },
    );
  });
}
