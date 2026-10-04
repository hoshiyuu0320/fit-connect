import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/widgets/note_card.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// カルテ一覧の1件（NoteCard）の表示テスト（正本: record-screens.js `NoteCard`）。
///
/// 紐づくセッションがあるノートだけ、先頭にセッション行
/// （calendar-days ＋「9月8日（火）19:00 · パーソナル」）を出す。
/// 補足は「9月8日（火） · {トレーナー名}」、添付は「添付 2件」のピル、右に chevron。
ClientNote _makeNote({
  LinkedSession? session,
  List<String> fileUrls = const [],
  String title = 'トレーニングセッション記録',
  String content = 'スクワットとデッドリフトを中心に実施。',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 2, 10, 20, 30);
  return ClientNote(
    id: 'note-1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: title,
    content: content,
    fileUrls: fileUrls,
    isShared: true,
    sharedAt: created,
    sessionId: session == null ? null : 'session-1',
    session: session,
    createdAt: created,
    updatedAt: created,
  );
}

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required ClientNote note,
    required DateTime now,
    String? trainerName,
    VoidCallback? onTap,
    ThemeData? theme,
    double textScale = 1.0,
    double width = 390,
  }) async {
    tester.view.physicalSize = Size(width, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: NoteCard(
              note: note,
              now: now,
              trainerName: trainerName,
              onTap: onTap ?? () {},
            ),
          ),
        ),
      ),
    );
  }

  final now = DateTime(2026, 2, 15, 12, 0);

  group('NoteCard 紐づくセッションあり', () {
    final sessionDate = DateTime(2026, 2, 10, 18, 0);

    testWidgets('セッション行は calendar-days ＋「日時 · 種別」の 1 行で出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(
            sessionDate: sessionDate,
            sessionType: 'パーソナルトレーニング',
          ),
        ),
        now: now,
        trainerName: '山田太郎',
      );

      // 全角の括弧・時は 0 埋めなし・種別は「 · 」でつなぐ（別チップにしない）
      expect(
        find.text('2月10日（火）18:00 · パーソナルトレーニング'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
      // タイトルと「日付 · トレーナー名」
      expect(find.text('トレーニングセッション記録'), findsOneWidget);
      expect(find.text('2月10日（火） · 山田太郎トレーナー'), findsOneWidget);
    });

    testWidgets('種別が無ければ日時だけ出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(session: LinkedSession(sessionDate: sessionDate)),
        now: now,
      );

      expect(find.text('2月10日（火）18:00'), findsOneWidget);
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

      expect(find.text('2月10日（火）18:00 · その他'), findsOneWidget);
      expect(find.textContaining('other'), findsNothing);
    });

    testWidgets('年をまたいだセッションは年付きで表示される', (tester) async {
      final lastYear = DateTime(2025, 12, 20, 11, 0);

      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(sessionDate: lastYear),
          createdAt: DateTime(2025, 12, 20, 16, 45),
        ),
        now: now,
        trainerName: '山田太郎',
      );

      expect(find.text('2025年12月20日（土）11:00'), findsOneWidget);
      // 補足の日付も年が違えば年付き
      expect(find.text('2025年12月20日（土） · 山田太郎トレーナー'), findsOneWidget);
    });
  });

  group('NoteCard 紐づくセッションなし', () {
    testWidgets('セッション行は出ず、タイトルと補足から始まる', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now, trainerName: '山田太郎');

      expect(find.byIcon(LucideIcons.calendarDays), findsNothing);
      expect(find.byIcon(LucideIcons.calendarCheck), findsNothing);
      expect(find.text('トレーニングセッション記録'), findsOneWidget);
      expect(find.text('2月10日（火） · 山田太郎トレーナー'), findsOneWidget);
      // 廃止した通し番号表示（#N）が残っていないこと
      expect(find.textContaining('#'), findsNothing);
    });

    testWidgets('名前が「田中」でも「田中トレーナー」でも同じ「田中トレーナー」（二重にならない）', (tester) async {
      for (final raw in ['田中', '田中トレーナー', ' 田中 ']) {
        await pumpCard(tester, note: _makeNote(), now: now, trainerName: raw);

        expect(find.text('2月10日（火） · 田中トレーナー'), findsOneWidget, reason: raw);
        expect(find.textContaining('トレーナートレーナー'), findsNothing, reason: raw);
      }
    });

    testWidgets('トレーナー名が取れていなければ補足は日付だけ', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now);

      expect(find.text('2月10日（火）'), findsOneWidget);
      expect(find.textContaining('·'), findsNothing);
    });
  });

  group('NoteCard 添付ファイル', () {
    testWidgets('添付があれば「添付 N件」のピルが出る', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(fileUrls: ['notes/a.jpg#写真.jpg', 'notes/b.pdf#資料.pdf']),
        now: now,
      );

      expect(find.text('添付 2件'), findsOneWidget);
      expect(find.byIcon(LucideIcons.paperclip), findsOneWidget);
      expect(find.byType(FcPill), findsOneWidget);
    });

    testWidgets('添付が無ければピルは出ない（chevron は出る）', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now);

      expect(find.textContaining('添付'), findsNothing);
      expect(find.byType(FcPill), findsNothing);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
    });
  });

  group('NoteCard 見た目と操作', () {
    testWidgets('カード全体を押すと onTap が呼ばれる', (tester) async {
      var taps = 0;
      await pumpCard(
        tester,
        note: _makeNote(),
        now: now,
        onTap: () => taps++,
      );

      // タイトルでも、本文の抜粋でも、カードのどこを押しても反応する
      await tester.tap(find.text('トレーニングセッション記録'));
      await tester.tap(find.text('スクワットとデッドリフトを中心に実施。'));
      expect(taps, 2);
    });

    testWidgets('本文の抜粋は 2 行で省略され、タイトルは行数を固定しない', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          title: 'とても長いタイトルのノートです。' * 4,
          content: '本文です。' * 80,
        ),
        now: now,
      );

      final preview = tester.widget<Text>(find.textContaining('本文です。'));
      expect(preview.maxLines, 2);
      expect(preview.overflow, TextOverflow.ellipsis);
      expect(preview.style!.fontSize, 15);
      expect(preview.style!.height, 1.6);

      final title = tester.widget<Text>(find.textContaining('とても長いタイトル'));
      expect(title.maxLines, isNull);
      expect(title.style!.fontSize, 17);
      expect(title.style!.fontWeight, FontWeight.w500);
    });

    testWidgets('カードは不透明な surface・角丸 23（影・枠なし）', (tester) async {
      await pumpCard(tester, note: _makeNote(), now: now);

      final deco = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(deco.color, AppColorsExtension.light.surface);
      expect(deco.color!.a, 1.0);
      expect(deco.borderRadius, BorderRadius.circular(23));
      expect(deco.boxShadow, isNull);
      expect(deco.border, isNull);
    });

    testWidgets('ダークでも surface の面で描かれる', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(sessionDate: DateTime(2026, 2, 10, 18)),
          fileUrls: ['a.jpg'],
        ),
        now: now,
        theme: AppTheme.darkTheme,
      );

      final deco = tester
          .widgetList<DecoratedBox>(
            find.descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            ),
          )
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .first;
      expect(deco.color, AppColorsExtension.dark.surface);
      expect(tester.takeException(), isNull);
    });

    testWidgets('読み上げは 1 つのボタンにまとまり、セッション・タイトル・添付を含む', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(
            sessionDate: DateTime(2026, 2, 10, 18),
            sessionType: 'パーソナル',
          ),
          fileUrls: ['a.jpg', 'b.pdf'],
        ),
        now: now,
        trainerName: '山田太郎',
      );

      final data = tester.getSemantics(find.byType(FcCard)).getSemanticsData();
      expect(data.label, contains('2月10日（火）18:00 · パーソナル'));
      expect(data.label, contains('トレーニングセッション記録'));
      expect(data.label, contains('山田太郎トレーナー'));
      expect(data.label, contains('添付 2件'));
      handle.dispose();
    });

    testWidgets('文字拡大 1.35・狭い幅でも横にはみ出さない', (tester) async {
      await pumpCard(
        tester,
        note: _makeNote(
          session: LinkedSession(
            sessionDate: DateTime(2026, 2, 10, 18),
            sessionType: 'パーソナルトレーニング（体験・初回カウンセリング付き）',
          ),
          title: '体組成測定結果と今後のトレーニング方針について',
          content: '今月の体組成測定を実施しました。' * 10,
          fileUrls: ['a.jpg', 'b.pdf', 'c.jpg'],
        ),
        now: now,
        trainerName: '山田太郎',
        textScale: 1.35,
        width: 320,
      );

      expect(tester.takeException(), isNull);
      expect(find.text('添付 3件'), findsOneWidget);
      final cardRect = tester.getRect(find.byType(FcCard));
      expect(cardRect.right, lessThanOrEqualTo(320));
    });
  });
}
