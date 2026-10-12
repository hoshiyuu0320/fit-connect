import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// カルテ詳細画面の表示テスト（正本: more-screens.js `NoteDetailScreen`）。
///
/// 紐づくセッションがあるノートだけ、タイトルの上にセッション日時 + 種別の行を出す。
/// 添付の表示（署名URL解決）はネットワークに触れるため、本文のみのノートで検証する。
ClientNote _makeNote({
  LinkedSession? session,
  String content = '本日は初回セッションを実施しました。',
  DateTime? createdAt,
}) {
  final created = createdAt ?? DateTime(2026, 2, 10, 20, 30);
  return ClientNote(
    id: 'note-1',
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: '初回トレーニングセッション',
    content: content,
    fileUrls: const [],
    isShared: true,
    sharedAt: created,
    sessionId: session == null ? null : 'session-1',
    session: session,
    createdAt: created,
    updatedAt: created,
  );
}

/// 画面に出る日時（正本の表記: 「9月15日（火）19:00」）。
/// 実装を呼ばずテスト側に同じ規則を持たせて期待値を組み立てる（規則の変更を検知するため）。
/// 年は今年と違うときだけ付く
String _expectedDateTimeLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final year = dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$year${dateTime.month}月${dateTime.day}日（$weekday）${dateTime.hour}:$minute';
}

/// 作成日（日付だけ）。年は今年と違うときだけ付く
String _expectedDateLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final year = dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$year${dateTime.month}月${dateTime.day}日（$weekday）';
}

String _weekday(DateTime dateTime) =>
    const ['月', '火', '水', '木', '金', '土', '日'][dateTime.weekday - 1];

void main() {
  Future<void> pumpScreen(
    WidgetTester tester,
    ClientNote note, {
    String? trainerName = '山田太郎',
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: ClientNoteDetailScreen(note: note, trainerName: trainerName),
      ),
    );
  }

  group('ClientNoteDetailScreen ヘッダー', () {
    testWidgets('紐づくセッションがあれば日時と種別が 1 行で出る（calendar-days）', (tester) async {
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

      expect(
        find.text('${_expectedDateTimeLabel(sessionDate)} · パーソナルトレーニング'),
        findsOneWidget,
      );
      expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
      // タイトル・トレーナー名と作成日は「名前 · 日付作成」の 1 行
      expect(find.text('初回トレーニングセッション'), findsOneWidget);
      expect(
        find.text('山田太郎トレーナー · ${_expectedDateLabel(DateTime(2026, 2, 10))}作成'),
        findsOneWidget,
      );
    });

    testWidgets('年は今年と違うときだけ付く（去年のカルテでも年が分かる）', (tester) async {
      final now = DateTime.now();
      final lastYear = DateTime(now.year - 1, 11, 3, 9, 5);
      final thisYear = DateTime(now.year, now.month, now.day, 19, 0);

      // 去年のセッション・去年に作成 → 日時も作成日も年付き
      await pumpScreen(
        tester,
        _makeNote(
          session: LinkedSession(sessionDate: lastYear),
          createdAt: lastYear,
        ),
      );
      expect(
        find.text('${now.year - 1}年11月3日（${_weekday(lastYear)}）9:05'),
        findsOneWidget,
      );
      expect(
        find.text('山田太郎トレーナー · ${now.year - 1}年11月3日（${_weekday(lastYear)}）作成'),
        findsOneWidget,
      );

      // 今年のセッション・今年に作成 → 年なし（正本どおり）
      await pumpScreen(
        tester,
        _makeNote(
          session: LinkedSession(sessionDate: thisYear),
          createdAt: thisYear,
        ),
      );
      await tester.pump();
      expect(
        find.text(
            '${thisYear.month}月${thisYear.day}日（${_weekday(thisYear)}）19:00'),
        findsOneWidget,
      );
      expect(
        find.text(
          '山田太郎トレーナー · ${thisYear.month}月${thisYear.day}日（${_weekday(thisYear)}）作成',
        ),
        findsOneWidget,
      );
    });

    testWidgets('種別が無ければ日時だけ出る', (tester) async {
      final sessionDate = DateTime(2026, 2, 10, 18, 0);

      await pumpScreen(
        tester,
        _makeNote(session: LinkedSession(sessionDate: sessionDate)),
      );

      expect(find.text(_expectedDateTimeLabel(sessionDate)), findsOneWidget);
    });

    testWidgets('紐づくセッションが無ければセッション行は出ない（従来どおり）', (tester) async {
      await pumpScreen(tester, _makeNote());

      expect(find.byIcon(LucideIcons.calendarDays), findsNothing);
      expect(find.byIcon(LucideIcons.dumbbell), findsNothing);
      expect(find.text('初回トレーニングセッション'), findsOneWidget);
      // 廃止した「第N回セッション」が残っていないこと
      // （本文の「初回セッション」に引っかからないよう番号付きの形で探す）
      expect(find.textContaining(RegExp(r'第\d+回セッション')), findsNothing);
    });

    testWidgets('トレーナー名が取れていなければ作成日だけ出る', (tester) async {
      await pumpScreen(tester, _makeNote(), trainerName: null);

      expect(
        find.text('${_expectedDateLabel(DateTime(2026, 2, 10))}作成'),
        findsOneWidget,
      );
    });
  });

  group('ClientNoteDetailScreen 枠と本文', () {
    testWidgets('AppBar ではなく本文内の「戻る」が出て、44 以上の領域で戻れる', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ClientNoteDetailScreen(note: _makeNote()),
                    ),
                  ),
                  child: const Text('開く'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsNothing);
      expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
      final back = find.ancestor(
        of: find.text('戻る'),
        matching: find.byType(FcPressable),
      );
      expect(tester.getSize(back).height, greaterThanOrEqualTo(44));

      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(ClientNoteDetailScreen), findsNothing);
    });

    testWidgets('本文は空行で段落に分かれ、段落内の改行は残る', (tester) async {
      await pumpScreen(
        tester,
        _makeNote(content: '一つ目の段落です。\n\n二つ目の段落。\n・箇条書き1\n・箇条書き2'),
      );

      expect(find.text('一つ目の段落です。'), findsOneWidget);
      expect(find.text('二つ目の段落。\n・箇条書き1\n・箇条書き2'), findsOneWidget);
      // 行高 1.75
      final style = tester.widget<Text>(find.text('一つ目の段落です。')).style!;
      expect(style.height, 1.75);
      expect(style.fontSize, 16);
    });

    testWidgets('添付が無ければ添付ファイルのセクションは出ない', (tester) async {
      await pumpScreen(tester, _makeNote());

      expect(find.textContaining('添付ファイル'), findsNothing);
    });

    testWidgets('添付があれば「添付ファイル（N件）」の下に PDF・その他のカードが並ぶ', (tester) async {
      final created = DateTime(2026, 2, 10, 20, 30);
      await pumpScreen(
        tester,
        ClientNote(
          id: 'n',
          clientId: 'c',
          trainerId: 't',
          title: '添付つき',
          content: '本文',
          fileUrls: const [
            'https://example.com/plan.pdf',
            'https://example.com/memo.zip',
          ],
          isShared: true,
          createdAt: created,
          updatedAt: created,
        ),
      );

      expect(find.text('添付ファイル（2件）'), findsOneWidget);
      // PDF: ファイル名・「PDF · 外部のアプリで開きます」・外部リンクのアイコン
      expect(find.text('plan.pdf'), findsOneWidget);
      expect(find.text('PDF · 外部のアプリで開きます'), findsOneWidget);
      expect(find.byIcon(LucideIcons.externalLink), findsOneWidget);
      expect(find.byIcon(LucideIcons.fileText), findsOneWidget);
      // その他のファイル: ファイル名だけ（開けない）
      expect(find.text('memo.zip'), findsOneWidget);
      expect(find.byIcon(LucideIcons.file), findsOneWidget);
    });

    testWidgets('タイトルは 26 / 500 のプラン名の見た目', (tester) async {
      await pumpScreen(tester, _makeNote());

      final style = tester.widget<Text>(find.text('初回トレーニングセッション')).style!;
      expect(style.fontSize, 26);
      expect(style.fontWeight, FontWeight.w500);
    });
  });

  group('ClientNoteDetailScreen 文字拡大 1.35 とダーク', () {
    testWidgets('長いタイトル・名前でも文字拡大 1.35 で overflow しない', (tester) async {
      final note = ClientNote(
        id: 'n',
        clientId: 'c',
        trainerId: 't',
        title: 'ダンベルプレスとラットプルダウンのフォーム確認と次回に向けた目標設定',
        content: 'とても長い本文です。' * 30,
        isShared: true,
        session: LinkedSession(
          sessionDate: DateTime(2026, 2, 10, 18, 0),
          sessionType: 'パーソナルトレーニング（ストレッチ込みの長いコース名）',
        ),
        createdAt: DateTime(2026, 2, 10, 20, 30),
        updatedAt: DateTime(2026, 2, 10, 20, 30),
      );

      await pumpScreen(
        tester,
        note,
        trainerName: '田中トレーナー（チーフ）',
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
    });

    testWidgets('ダークでも読める（セッション行は accent、カードは surface）', (tester) async {
      await pumpScreen(
        tester,
        _makeNote(
          session: LinkedSession(
            sessionDate: DateTime(2026, 2, 10, 18, 0),
            sessionType: 'パーソナルトレーニング',
          ),
        ),
        theme: AppTheme.darkTheme,
      );

      expect(tester.takeException(), isNull);
      final line = tester.widget<Text>(
        find.textContaining('パーソナルトレーニング'),
      );
      expect(line.style!.color, AppColorsExtension.dark.accent);
      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byType(FcCard),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      expect(
        (card.decoration as BoxDecoration).color,
        AppColorsExtension.dark.surface,
      );
    });
  });

  group('NoteDetailPhotoCard 読み上げ', () {
    Future<void> pumpPhotos(
      WidgetTester tester, {
      required Widget Function(Widget failedPlaceholder) imageBuilder,
      int number = 1,
      int total = 2,
      VoidCallback? onTap,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: ListView(
              children: [
                NoteDetailPhotoCard(
                  number: number,
                  total: total,
                  imageBuilder: imageBuilder,
                  onTap: onTap ?? () {},
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('通常は「写真 1/2 を拡大して表示」と読み上げ、タップできる', (tester) async {
      final handle = tester.ensureSemantics();
      var taps = 0;
      await pumpPhotos(
        tester,
        imageBuilder: (_) => const SizedBox(height: 190),
        onTap: () => taps++,
      );

      expect(find.bySemanticsLabel('写真 1/2 を拡大して表示'), findsOneWidget);
      expect(find.bySemanticsLabel('写真を拡大して表示'), findsNothing);

      await tester.tap(find.text('写真 · タップで拡大'));
      expect(taps, 1);
      handle.dispose();
    });

    testWidgets('番号は写真ごとに変わる（2/2）', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPhotos(
        tester,
        number: 2,
        imageBuilder: (_) => const SizedBox(height: 190),
      );

      expect(find.bySemanticsLabel('写真 2/2 を拡大して表示'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('読み込みに失敗したら「写真 1/2 を読み込めませんでした」になり、代替の面にも出る', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpPhotos(
        tester,
        imageBuilder: (failedPlaceholder) => failedPlaceholder,
      );
      // 代替の面が出た次のフレームで、カードの読み上げが切り替わる
      await tester.pump();

      expect(find.bySemanticsLabel('写真 1/2 を読み込めませんでした'), findsWidgets);
      expect(find.bySemanticsLabel('写真 1/2 を拡大して表示'), findsNothing);
      // 見た目にも同じ文言（代替の面のラベル）
      expect(find.text('写真 1/2 を読み込めませんでした'), findsOneWidget);
      handle.dispose();
    });
  });
}
