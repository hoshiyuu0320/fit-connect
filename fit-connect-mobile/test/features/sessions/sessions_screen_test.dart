import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/screens/sessions_screen.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';

/// セッション一覧画面の表示テスト。
///
/// リモートDBに未来のセッションが無くシミュレータでは空状態しか確認できないため、
/// Providerを差し替えて「今後 / 過去」の切替とリスト表示を検証する。
///
/// ※ 日時のフィクスチャは必ず DateTime.now() 基準の相対値で作ること。
SessionModel _makeSession({
  required String id,
  required Duration fromNow,
  required String status,
  String? sessionType,
  int durationMinutes = 60,
  List<ClientNote> notes = const [],
}) {
  final now = DateTime.now();
  return SessionModel(
    id: id,
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now.add(fromNow),
    durationMinutes: durationMinutes,
    status: status,
    sessionType: sessionType,
    notes: notes,
    createdAt: now,
    updatedAt: now,
  );
}

/// embed（`client_notes(...)`）で一緒に返ってくるノート1件。
/// 顧客のクエリにはRLSで共有ノートしか入ってこないが、未共有が混ざっても
/// 導線が出ないことを確かめたいので isShared を渡せるようにしてある。
ClientNote _makeNote({
  required String id,
  required String sessionId,
  String title = 'セッションの記録',
  bool isShared = true,
}) {
  final now = DateTime.now();
  return ClientNote(
    id: id,
    clientId: 'client-1',
    trainerId: 'trainer-1',
    title: title,
    content: '本日の内容と次回に向けたポイント。',
    isShared: isShared,
    sharedAt: isShared ? now : null,
    sessionId: sessionId,
    createdAt: now,
    updatedAt: now,
  );
}

/// push されたルート数を数える Observer（ノートが無い行の空振りタップ検知用）
class _PushCountObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

/// 実装（session_formatting.dart）と同じ表示整形。
/// 実装を呼ばずテスト側に同じ規則を持たせて期待値を組み立てる（規則の変更を検知するため）。
///
/// 「過去」タブは年をまたぐため常に年付き（includeYear: true）、
/// 「今後」タブは年が変わる場合だけ年が付く
String _expectedDateTimeLabel(DateTime dateTime, {bool includeYear = false}) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix = (includeYear || dateTime.year != DateTime.now().year)
      ? '${dateTime.year}年'
      : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> overrides,
    void Function(String draft)? onConsult,
    List<NavigatorObserver> navigatorObservers = const [],
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          navigatorObservers: navigatorObservers,
          home: SessionsScreen(onConsult: onConsult),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// 画面はノート詳細のヘッダー用にトレーナー名を引く（カルテ一覧と同じ出典）。
  /// テストでSupabaseに触れないよう必ず差し替える
  final trainerOverride = trainerProfileProvider.overrideWith(
    (ref) async => const Trainer(id: 'trainer-1', name: '山田太郎'),
  );

  List<Override> listOverrides({
    List<SessionModel> upcoming = const [],
    List<SessionModel> past = const [],
  }) =>
      [
        upcomingSessionsProvider.overrideWith((ref) async => upcoming),
        pastSessionsProvider.overrideWith((ref) async => past),
        trainerOverride,
      ];

  final upcoming = [
    _makeSession(
      id: 'upcoming-1',
      fromNow: const Duration(days: 1),
      status: 'confirmed',
      sessionType: 'パーソナルトレーニング',
    ),
    _makeSession(
      id: 'upcoming-2',
      fromNow: const Duration(days: 5),
      status: 'scheduled',
      sessionType: 'ストレッチ',
      durationMinutes: 45,
    ),
  ];

  final past = [
    _makeSession(
      id: 'past-1',
      fromNow: const Duration(days: -2),
      status: 'completed',
      sessionType: 'パーソナルトレーニング',
    ),
    _makeSession(
      id: 'past-2',
      fromNow: const Duration(days: -9),
      status: 'cancelled',
      sessionType: 'カウンセリング',
      durationMinutes: 30,
    ),
  ];

  group('SessionsScreen 今後タブ', () {
    testWidgets('初期表示で今後のセッションが並ぶ', (tester) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
      );

      expect(find.text('セッション'), findsOneWidget);
      for (final session in upcoming) {
        expect(
          find.text(_expectedDateTimeLabel(session.sessionDate)),
          findsOneWidget,
        );
      }

      // ステータス・所要時間・種別も出る
      expect(find.text('確定'), findsOneWidget);
      expect(find.text('予定'), findsOneWidget);
      expect(find.text('45分'), findsOneWidget);
      expect(find.text('ストレッチ'), findsOneWidget);

      // 過去タブの内容は出ていない
      expect(
        find.text(
          _expectedDateTimeLabel(past.first.sessionDate, includeYear: true),
        ),
        findsNothing,
      );
    });
  });

  group('SessionsScreen セグメント切替', () {
    testWidgets('「過去」をタップすると過去のセッションに切り替わる', (tester) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
      );

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      for (final session in past) {
        expect(
          find.text(
            _expectedDateTimeLabel(session.sessionDate, includeYear: true),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('完了'), findsOneWidget);
      expect(find.text('キャンセル'), findsOneWidget);

      // 今後のセッションは消えている
      for (final session in upcoming) {
        expect(
          find.text(_expectedDateTimeLabel(session.sessionDate)),
          findsNothing,
        );
      }

      // 「今後」へ戻せる
      await tester.tap(find.text('今後'));
      await tester.pumpAndSettle();
      expect(
        find.text(_expectedDateTimeLabel(upcoming.first.sessionDate)),
        findsOneWidget,
      );
    });
  });

  group('SessionsScreen 空状態', () {
    testWidgets('今後が0件なら予約を促す文言が出る', (tester) async {
      await pumpScreen(tester, overrides: listOverrides());

      expect(find.text('予定されているセッションはありません'), findsOneWidget);
      expect(find.text('次回の予約についてトレーナーに相談してみましょう。'), findsOneWidget);
    });

    testWidgets('過去が0件なら過去用の文言に切り替わる', (tester) async {
      await pumpScreen(tester, overrides: listOverrides());

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      expect(find.text('過去のセッションはありません'), findsOneWidget);
      expect(find.text('完了・キャンセルしたセッションがここに表示されます。'), findsOneWidget);
      expect(find.text('予定されているセッションはありません'), findsNothing);
    });
  });

  group('SessionsScreen エラー状態', () {
    testWidgets('取得失敗時はリトライ導線が出る', (tester) async {
      await pumpScreen(
        tester,
        overrides: [
          upcomingSessionsProvider.overrideWith(
            (ref) async => throw StateError('failed to load'),
          ),
          pastSessionsProvider.overrideWith((ref) async => past),
          trainerOverride,
        ],
      );

      expect(find.text('エラーが発生しました'), findsOneWidget);
      expect(find.text('リトライ'), findsOneWidget);
    });
  });

  group('SessionsScreen 変更を相談', () {
    testWidgets('タップで定型文付きの onConsult が呼ばれる', (tester) async {
      final drafts = <String>[];

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
        onConsult: drafts.add,
      );

      await tester.tap(find.text('変更を相談').first);
      await tester.pumpAndSettle();

      expect(drafts, [
        '${_expectedDateTimeLabel(upcoming.first.sessionDate)} のセッションについて相談です。',
      ]);
    });

    testWidgets('過去タブには相談導線を出さない（終わったセッションのため）', (tester) async {
      final drafts = <String>[];

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
        onConsult: drafts.add,
      );

      // 「今後」では出ている
      expect(find.text('変更を相談'), findsWidgets);

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      // 過去の行は描画されているがボタンは1つも無い
      expect(
        find.text(
          _expectedDateTimeLabel(past.first.sessionDate, includeYear: true),
        ),
        findsOneWidget,
      );
      expect(find.text('変更を相談'), findsNothing);
      expect(drafts, isEmpty);
    });
  });

  group('SessionsScreen 過去タブの年表示', () {
    testWidgets('年をまたいだ過去のセッションは年付きで表示される', (tester) async {
      final lastYear = _makeSession(
        id: 'past-last-year',
        fromNow: const Duration(days: -400),
        status: 'completed',
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(past: [lastYear]),
      );

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      final label = _expectedDateTimeLabel(
        lastYear.sessionDate,
        includeYear: true,
      );
      expect(label, startsWith('${lastYear.sessionDate.year}年'));
      expect(find.text(label), findsOneWidget);
    });
  });

  group('SessionsScreen ノート導線', () {
    // ノートあり / なしを1画面に並べて差が出ることを見る
    final withNote = _makeSession(
      id: 'past-with-note',
      fromNow: const Duration(days: -2),
      status: 'completed',
      sessionType: 'パーソナルトレーニング',
      notes: [
        _makeNote(
          id: 'note-1',
          sessionId: 'past-with-note',
          title: '第3回セッションの記録',
        ),
      ],
    );
    final withoutNote = _makeSession(
      id: 'past-without-note',
      fromNow: const Duration(days: -9),
      status: 'completed',
      sessionType: 'カウンセリング',
    );

    Future<void> pumpPastTab(
      WidgetTester tester, {
      required List<SessionModel> past,
      List<NavigatorObserver> navigatorObservers = const [],
    }) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(past: past),
        navigatorObservers: navigatorObservers,
      );
      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();
    }

    testWidgets('ノートがある行にだけチップと chevron が出る', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      final noteTile = find.byKey(const ValueKey('past-with-note'));
      expect(
        find.descendant(of: noteTile, matching: find.text('ノート')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: noteTile,
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ノートが無い行にはチップも chevron も出ない', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      final plainTile = find.byKey(const ValueKey('past-without-note'));
      // 行自体は描画されている
      expect(
        find.descendant(of: plainTile, matching: find.text('カウンセリング')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plainTile, matching: find.text('ノート')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: plainTile,
          matching: find.byIcon(LucideIcons.chevronRight),
        ),
        findsNothing,
      );
    });

    testWidgets('未共有ノートしか無い行には導線を出さない', (tester) async {
      final privateOnly = _makeSession(
        id: 'past-private-note',
        fromNow: const Duration(days: -3),
        status: 'completed',
        notes: [
          _makeNote(
            id: 'note-private',
            sessionId: 'past-private-note',
            title: '共有していないメモ',
            isShared: false,
          ),
        ],
      );

      await pumpPastTab(tester, past: [privateOnly]);

      final tile = find.byKey(const ValueKey('past-private-note'));
      expect(
        find.descendant(of: tile, matching: find.text('ノート')),
        findsNothing,
      );
      // タイトルが漏れていないこと（未共有ノートの存在を匂わせない）
      expect(find.text('共有していないメモ'), findsNothing);
    });

    testWidgets('タップでカルテ詳細へ遷移する', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      await tester.tap(find.byKey(const ValueKey('past-with-note')));
      await tester.pumpAndSettle();

      expect(find.byType(ClientNoteDetailScreen), findsOneWidget);
      expect(find.text('第3回セッションの記録'), findsOneWidget);
      // トレーナー名も一覧から引き継がれる
      expect(find.text('山田太郎'), findsOneWidget);
      // 逆向きの embed が無くても、行のセッション自身の日時・種別が
      // 詳細ヘッダーに補われて出る（詳細は常に年付き）
      expect(
        find.text(
          _expectedDateTimeLabel(withNote.sessionDate, includeYear: true),
        ),
        findsOneWidget,
      );
      expect(find.text('パーソナルトレーニング'), findsOneWidget);
    });

    testWidgets('ノートが無い行はタップしても何も起きない', (tester) async {
      final observer = _PushCountObserver();

      await pumpPastTab(
        tester,
        past: [withNote, withoutNote],
        navigatorObservers: [observer],
      );

      // home の初回 push 分をここまでの件数として控える
      final baseline = observer.pushCount;

      await tester.tap(find.byKey(const ValueKey('past-without-note')));
      await tester.pumpAndSettle();

      expect(observer.pushCount, baseline);
      expect(find.byType(ClientNoteDetailScreen), findsNothing);
      // 一覧に留まっている
      expect(find.text('セッション'), findsOneWidget);
    });

    testWidgets('「今後」タブでもノート導線は効く（相談ボタンとは併存する）', (tester) async {
      final upcomingWithNote = _makeSession(
        id: 'upcoming-with-note',
        fromNow: const Duration(days: 2),
        status: 'confirmed',
        notes: [
          _makeNote(
            id: 'note-upcoming',
            sessionId: 'upcoming-with-note',
            title: '次回セッションの事前確認',
          ),
        ],
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [upcomingWithNote]),
        onConsult: (_) {},
      );

      expect(find.text('ノート'), findsOneWidget);
      // 「今後」の既存仕様（相談導線）を壊していないこと
      expect(find.text('変更を相談'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('upcoming-with-note')));
      await tester.pumpAndSettle();

      expect(find.byType(ClientNoteDetailScreen), findsOneWidget);
    });
  });

  group('SessionsScreen キャンセル済みの表示', () {
    testWidgets('「今後」に残る未来のキャンセルは淡色（surfaceDim）で区別される', (tester) async {
      final cancelled = _makeSession(
        id: 'upcoming-cancelled',
        fromNow: const Duration(days: 2),
        status: 'cancelled',
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [upcoming.first, cancelled]),
      );

      // キャンセルでも「今後」から消えない（仕分けは終了時刻の一本）
      expect(find.text('キャンセル'), findsOneWidget);

      expect(
        _tileBackgroundColor(tester, const ValueKey('upcoming-cancelled')),
        AppColorsExtension.light.surfaceDim,
      );
      // 生きている予定は通常色のまま
      expect(
        _tileBackgroundColor(tester, const ValueKey('upcoming-1')),
        AppColorsExtension.light.surface,
      );
    });
  });
}

/// 一覧の行（外側のContainer）の背景色を取り出す
Color? _tileBackgroundColor(WidgetTester tester, Key tileKey) {
  final container = tester.widget<Container>(
    find
        .descendant(of: find.byKey(tileKey), matching: find.byType(Container))
        .first,
  );
  return (container.decoration as BoxDecoration?)?.color;
}
