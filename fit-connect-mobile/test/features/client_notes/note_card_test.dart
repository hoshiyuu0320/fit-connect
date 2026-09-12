import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/note_card.dart';

/// カルテ一覧の1件（NoteCard）の表示テスト。
///
/// 廃止した `#N`（session_number）の代わりに、紐づくセッションがあるノートだけ
/// セッション日時 + 種別を先頭行に出すことを検証する。
ClientNote _makeNote({
  LinkedSession? session,
  List<String> fileUrls = const [],
}) {
  return ClientNote(
    id: 'note-1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: 'トレーニングセッション記録',
    content: 'スクワットとデッドリフトを中心に実施。',
    fileUrls: fileUrls,
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
/// 一覧は includeYear なしで呼ばれるので、[now] と年が違う場合だけ年が付く
String _expectedDateTimeLabel(DateTime dateTime, {required DateTime now}) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix = dateTime.year != now.year ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required ClientNote note,
    required DateTime now,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.lightTheme,
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: NoteCard(note: note, now: now, onTap: () {}),
          ),
        ),
      ),
    );
  }

  final now = DateTime(2026, 2, 15, 12, 0);

  group('NoteCard 紐づくセッションあり', () {
    final sessionDate = DateTime(2026, 2, 10, 18, 0);

    testWidgets('セッション日時と種別が出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(
            sessionDate: sessionDate,
            sessionType: 'パーソナルトレーニング',
          ),
        ),
        now: now,
      );

      expect(
        find.text(_expectedDateTimeLabel(sessionDate, now: now)),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.calendarCheck), findsOneWidget);
      expect(find.text('パーソナルトレーニング'), findsOneWidget);
      // タイトルと作成日は従来どおり
      expect(find.text('トレーニングセッション記録'), findsOneWidget);
      expect(find.text('2026年2月10日'), findsOneWidget);
    });

    testWidgets('種別が無ければ日時だけ出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(session: LinkedSession(sessionDate: sessionDate)),
        now: now,
      );

      expect(
        find.text(_expectedDateTimeLabel(sessionDate, now: now)),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.dumbbell), findsNothing);
    });

    testWidgets("種別 'other' は「その他」に変換される", (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          session:
              LinkedSession(sessionDate: sessionDate, sessionType: 'other'),
        ),
        now: now,
      );

      expect(find.text('その他'), findsOneWidget);
      expect(find.text('other'), findsNothing);
    });

    testWidgets('年をまたいだセッションは年付きで表示される', (tester) async {
      final lastYear = DateTime(2025, 12, 20, 11, 0);

      await pumpCard(
        tester,
        note: _makeNote(session: LinkedSession(sessionDate: lastYear)),
        now: now,
      );

      final label = _expectedDateTimeLabel(lastYear, now: now);
      expect(label, startsWith('2025年'));
      expect(find.text(label), findsOneWidget);
    });
  });

  group('NoteCard 紐づくセッションなし', () {
    testWidgets('セッション行は出ず、タイトルと作成日のみ（従来どおり）', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now);

      expect(find.byIcon(LucideIcons.calendarCheck), findsNothing);
      expect(find.byIcon(LucideIcons.dumbbell), findsNothing);
      expect(find.text('トレーニングセッション記録'), findsOneWidget);
      expect(find.text('2026年2月10日'), findsOneWidget);
      // 廃止した通し番号表示（#N）が残っていないこと
      expect(find.textContaining('#'), findsNothing);
    });
  });

  group('NoteCard 添付ファイル', () {
    testWidgets('添付があれば件数バッジが出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(fileUrls: ['notes/a.jpg#写真.jpg', 'notes/b.pdf#資料.pdf']),
        now: now,
      );

      expect(find.text('添付ファイル2件'), findsOneWidget);
      expect(find.byIcon(LucideIcons.paperclip), findsOneWidget);
    });

    testWidgets('添付が無ければバッジは出ない', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now);

      expect(find.textContaining('添付ファイル'), findsNothing);
    });
  });
}
