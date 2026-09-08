import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/session_status_badge.dart';

/// セッションのステータスバッジの表示テスト。
/// 4値の日本語ラベルと、CHECK制約外の未知値でも落ちないことを担保する
SessionModel _makeSession(String status) {
  final now = DateTime.now();
  return SessionModel(
    id: 'session-$status',
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now,
    durationMinutes: 60,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  Future<void> pumpBadge(WidgetTester tester, String status) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: SessionStatusBadge(session: _makeSession(status)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('SessionStatusBadge', () {
    testWidgets('既知の4ステータスは日本語ラベルで表示される', (tester) async {
      const expected = {
        'scheduled': '予定',
        'confirmed': '確定',
        'completed': '完了',
        'cancelled': 'キャンセル',
      };

      for (final entry in expected.entries) {
        await pumpBadge(tester, entry.key);
        expect(
          find.text(entry.value),
          findsOneWidget,
          reason: '${entry.key} は「${entry.value}」と表示されるべき',
        );
      }
    });

    testWidgets('未知のステータスでも例外を出さず生値にフォールバックする', (tester) async {
      await pumpBadge(tester, 'no_show');

      expect(tester.takeException(), isNull);
      expect(find.text('no_show'), findsOneWidget);
    });

    testWidgets('空文字のステータスでも描画が壊れない', (tester) async {
      await pumpBadge(tester, '');

      expect(tester.takeException(), isNull);
      expect(find.byType(SessionStatusBadge), findsOneWidget);
    });
  });
}
