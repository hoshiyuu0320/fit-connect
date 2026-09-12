import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';

/// カルテ詳細画面のヘッダー表示テスト。
///
/// 廃止した「第N回セッション」の代わりに、紐づくセッションがあるノートだけ
/// ヘッダー先頭にセッション日時（常に年付き）+ 種別を出すことを検証する。
/// 添付の表示（署名URL解決）はネットワークに触れるため、本文のみのノートで検証する。
ClientNote _makeNote({LinkedSession? session}) {
  return ClientNote(
    id: 'note-1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: '初回トレーニングセッション',
    content: '本日は初回セッションを実施しました。',
    fileUrls: const [],
    isShared: true,
    sharedAt: DateTime(2026, 2, 10, 20, 30),
    sessionId: session == null ? null : 'session-1',
    session: session,
    createdAt: DateTime(2026, 2, 10, 20, 30),
    updatedAt: DateTime(2026, 2, 10, 20, 30),
  );
}

/// 実装（session_formatting.dart）と同じ表示整形。
/// 実装を呼ばずテスト側に同じ規則を持たせて期待値を組み立てる（規則の変更を検知するため）。
/// 詳細は includeYear: true で呼ばれるので常に年が付く
String _expectedDateTimeLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  return '${dateTime.year}年${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

void main() {
  Future<void> pumpScreen(WidgetTester tester, ClientNote note) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: ClientNoteDetailScreen(note: note, trainerName: '山田太郎'),
      ),
    );
  }

  group('ClientNoteDetailScreen ヘッダー', () {
    testWidgets('紐づくセッションがあれば年付きの日時と種別が出る', (tester) async {
      final sessionDate = DateTime(2026, 2, 10, 18, 0);

      await pumpScreen(
        tester,
        _makeNote(
          session: LinkedSession(
            sessionDate: sessionDate,
            sessionType: 'パーソナルトレーニング',
          ),
        ),
      );

      expect(find.text(_expectedDateTimeLabel(sessionDate)), findsOneWidget);
      expect(find.byIcon(LucideIcons.calendarCheck), findsOneWidget);
      expect(find.text('パーソナルトレーニング'), findsOneWidget);
      // タイトル・トレーナー名・作成日時は従来どおり
      expect(find.text('初回トレーニングセッション'), findsOneWidget);
      expect(find.text('山田太郎'), findsOneWidget);
      expect(find.text('2026年2月10日 20:30'), findsOneWidget);
    });

    testWidgets('紐づくセッションが無ければセッション行は出ない（従来どおり）', (tester) async {
      await pumpScreen(tester, _makeNote());

      expect(find.byIcon(LucideIcons.calendarCheck), findsNothing);
      expect(find.byIcon(LucideIcons.dumbbell), findsNothing);
      expect(find.text('初回トレーニングセッション'), findsOneWidget);
      expect(find.text('2026年2月10日 20:30'), findsOneWidget);
      // 廃止した「第N回セッション」が残っていないこと
      // （本文の「初回セッション」に引っかからないよう番号付きの形で探す）
      expect(find.textContaining(RegExp(r'第\d+回セッション')), findsNothing);
    });
  });
}
