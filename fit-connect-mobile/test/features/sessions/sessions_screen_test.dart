import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/presentation/screens/client_note_detail_screen.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/screens/sessions_screen.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

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

/// セッションに紐づけて返ってくるノート1件（SessionRepository が client_notes から差し込む）。
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

/// 画面に出る日時（正本の表記: 「9月15日（火）19:00」）。
/// 実装（formatSessionDateTimeDisplay）を呼ばずテスト側に同じ規則を持たせて期待値を組み立てる
/// （規則の変更を検知するため）。
///
/// 年は「今年と違うときだけ」付く（今後・過去タブ共通。同じ年なら正本どおり年なし）
String _expectedDateTimeLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日（$weekday）${dateTime.hour}:$minute';
}

/// 「変更を相談」の定型文に入る日時（push 通知本文と同じ半角括弧の表記 = formatSessionDateTime）
String _expectedDraftLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

void main() {
  Future<void> pumpScreen(
    WidgetTester tester, {
    required List<Override> overrides,
    void Function(String draft)? onConsult,
    List<NavigatorObserver> navigatorObservers = const [],
    double textScale = 1.0,
    bool settle = true,
  }) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.lightTheme,
          navigatorObservers: navigatorObservers,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
            ),
            child: child!,
          ),
          home: SessionsScreen(onConsult: onConsult),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      await tester.pump();
    }
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

      // 所要時間・種別・ステータスは 1 行の文言（ステータスは色分けせず文言で示す）
      expect(find.text('60分 · パーソナルトレーニング · 確定'), findsOneWidget);
      expect(find.text('45分 · ストレッチ · 予定'), findsOneWidget);

      // 過去タブの内容は出ていない
      expect(
        find.text(
          _expectedDateTimeLabel(past.first.sessionDate),
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
            _expectedDateTimeLabel(session.sessionDate),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('60分 · パーソナルトレーニング · 完了'), findsOneWidget);
      expect(find.text('30分 · カウンセリング · キャンセル'), findsOneWidget);

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
        // 定型文は表示の表記ではなく、push 通知本文と同じ半角括弧の表記
        '${_expectedDraftLabel(upcoming.first.sessionDate)} のセッションについて相談です。',
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
          _expectedDateTimeLabel(past.first.sessionDate),
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

      final label = _expectedDateTimeLabel(lastYear.sessionDate);
      expect(label, startsWith('${lastYear.sessionDate.year}年'));
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('同じ年の過去のセッションは年を付けない（正本どおり）', (tester) async {
      // 年初に実行しても同じ年に収まるよう、今日の 0:00 を使う
      final now = DateTime.now();
      final thisYear = SessionModel(
        id: 'past-this-year',
        trainerId: 'trainer-1',
        clientId: 'client-1',
        sessionDate: DateTime(now.year, now.month, now.day, 0, 0),
        durationMinutes: 30,
        status: 'completed',
        createdAt: now,
        updatedAt: now,
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(past: [thisYear]),
      );
      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      final label = _expectedDateTimeLabel(thisYear.sessionDate);
      expect(label, isNot(contains('年')));
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

    testWidgets('ノートがある行にだけ「ノート」の操作が出る', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      final noteTile = find.byKey(const ValueKey('past-with-note'));
      expect(
        find.descendant(of: noteTile, matching: find.text('ノート')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: noteTile,
          matching: find.byIcon(LucideIcons.fileText),
        ),
        findsOneWidget,
      );
    });

    testWidgets('ノートが無い行には「ノート」の操作が出ない', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      final plainTile = find.byKey(const ValueKey('past-without-note'));
      // 行自体は描画されている
      expect(
        find.descendant(
          of: plainTile,
          matching: find.text('60分 · カウンセリング · 完了'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(of: plainTile, matching: find.text('ノート')),
        findsNothing,
      );
      expect(
        find.descendant(
          of: plainTile,
          matching: find.byIcon(LucideIcons.fileText),
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

    testWidgets('「ノート」をタップするとカルテ詳細へ遷移する', (tester) async {
      await pumpPastTab(tester, past: [withNote, withoutNote]);

      await tester.tap(
        find.descendant(
          of: find.byKey(const ValueKey('past-with-note')),
          matching: find.text('ノート'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(ClientNoteDetailScreen), findsOneWidget);
      expect(find.text('第3回セッションの記録'), findsOneWidget);
      // トレーナー名も一覧から引き継がれる
      expect(find.textContaining('山田太郎'), findsOneWidget);
      // 逆向きの embed が無くても、行のセッション自身の日時・種別が
      // 詳細ヘッダーに補われて出る（正本の表記。年は今年と違うときだけ付く）
      expect(
        find.text(
          '${_expectedDateTimeLabel(withNote.sessionDate)} · パーソナルトレーニング',
        ),
        findsOneWidget,
      );
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

      await tester.tap(
        find.text(
          _expectedDateTimeLabel(withoutNote.sessionDate),
        ),
      );
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

      await tester.tap(find.text('ノート'));
      await tester.pumpAndSettle();

      expect(find.byType(ClientNoteDetailScreen), findsOneWidget);
    });
  });

  group('SessionsScreen キャンセル済みの表示', () {
    testWidgets('「今後」に残る未来のキャンセルは淡色（0.55）で区別され、文言で示される', (tester) async {
      final cancelled = _makeSession(
        id: 'upcoming-cancelled',
        fromNow: const Duration(days: 2),
        status: 'cancelled',
        sessionType: 'カウンセリング',
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [upcoming.first, cancelled]),
        onConsult: (_) {},
      );

      // キャンセルでも「今後」から消えない（仕分けは終了時刻の一本）。色分けはせず文言で示す
      expect(find.text('60分 · カウンセリング · キャンセル'), findsOneWidget);

      expect(
        _tileOpacity(tester, const ValueKey('upcoming-cancelled')),
        0.55,
      );
      // 生きている予定は通常の濃さのまま
      expect(_tileOpacity(tester, const ValueKey('upcoming-1')), 1.0);
    });

    testWidgets('キャンセル済みの予定には「変更を相談」を出さない（動かせないため）', (tester) async {
      final cancelled = _makeSession(
        id: 'upcoming-cancelled',
        fromNow: const Duration(days: 2),
        status: 'cancelled',
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [cancelled]),
        onConsult: (_) {},
      );

      expect(find.text('変更を相談'), findsNothing);
    });
  });

  group('SessionsScreen あと◯日のピル', () {
    testWidgets('次回（最初の生きている予定）にだけ付く', (tester) async {
      final next = _makeSession(
        id: 'next',
        fromNow: const Duration(days: 3),
        status: 'confirmed',
      );
      final later = _makeSession(
        id: 'later',
        fromNow: const Duration(days: 10),
        status: 'scheduled',
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [next, later]),
      );

      expect(find.text('あと3日'), findsOneWidget);
      expect(find.text('あと10日'), findsNothing);
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('next')),
          matching: find.byType(FcPill),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('later')),
          matching: find.byType(FcPill),
        ),
        findsNothing,
      );
    });

    testWidgets('翌日は「明日」と表示し、過去タブには付けない', (tester) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
      );
      expect(find.text('明日'), findsOneWidget);

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();
      expect(find.byType(FcPill), findsNothing);
    });
  });

  group('SessionsScreen 画面の枠', () {
    testWidgets('AppBar ではなく本文内の「戻る」と見出し「セッション」が出る', (tester) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
      );

      expect(find.byType(AppBar), findsNothing);
      expect(find.text('戻る'), findsOneWidget);
      expect(find.byIcon(LucideIcons.arrowLeft), findsOneWidget);
      expect(find.text('セッション'), findsOneWidget);
    });

    testWidgets('「戻る」で前の画面へ戻る。タッチ領域は 44 以上', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: listOverrides(upcoming: upcoming, past: past),
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SessionsScreen()),
                    ),
                    child: const Text('開く'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('開く'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionsScreen), findsOneWidget);

      final back = find.ancestor(
        of: find.text('戻る'),
        matching: find.byType(FcPressable),
      );
      final size = tester.getSize(back);
      expect(size.height, greaterThanOrEqualTo(AppSizes.minTouch));
      expect(size.width, greaterThanOrEqualTo(AppSizes.minTouch));

      await tester.tap(find.text('戻る'));
      await tester.pumpAndSettle();
      expect(find.byType(SessionsScreen), findsNothing);
    });

    testWidgets('今後 / 過去の切替は選択中が actionFill で示される', (tester) async {
      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: upcoming, past: past),
      );

      Color? segmentColor(String label) {
        final box = tester.widget<AnimatedContainer>(
          find.ancestor(
            of: find.text(label),
            matching: find.byType(AnimatedContainer),
          ),
        );
        return (box.decoration as BoxDecoration?)?.color;
      }

      expect(segmentColor('今後'), AppColorsExtension.light.actionFill);
      expect(segmentColor('過去'), AppColorsExtension.light.surface);

      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();
      expect(segmentColor('過去'), AppColorsExtension.light.actionFill);
      expect(segmentColor('今後'), AppColorsExtension.light.surface);
    });
  });

  group('SessionsScreen 読み込み中', () {
    testWidgets('読み込み中は配置を保つスケルトンを出す（文言は出さない）', (tester) async {
      final completer = Completer<List<SessionModel>>();
      await pumpScreen(
        tester,
        overrides: [
          upcomingSessionsProvider.overrideWith((ref) => completer.future),
          pastSessionsProvider.overrideWith((ref) async => past),
          trainerOverride,
        ],
        settle: false,
      );

      expect(find.byType(FcSkeleton), findsWidgets);
      expect(find.bySemanticsLabel('読み込み中'), findsOneWidget);
      expect(find.text('予定されているセッションはありません'), findsNothing);

      completer.complete(upcoming);
      await tester.pumpAndSettle();
      expect(find.byType(FcSkeleton), findsNothing);
    });
  });

  group('SessionsScreen 文字拡大 1.35 とダーク', () {
    testWidgets('文字拡大 1.35 でも overflow せず、操作の領域は 44 以上', (tester) async {
      final longType = _makeSession(
        id: 'long',
        fromNow: const Duration(days: 4),
        status: 'confirmed',
        sessionType: 'パーソナルトレーニング（ストレッチ込みの長いコース名）',
        notes: [_makeNote(id: 'n', sessionId: 'long')],
      );

      await pumpScreen(
        tester,
        overrides: listOverrides(upcoming: [longType, ...upcoming]),
        onConsult: (_) {},
        textScale: 1.35,
      );

      expect(tester.takeException(), isNull);
      for (final label in ['変更を相談', 'ノート']) {
        final button = find
            .ancestor(of: find.text(label), matching: find.byType(FcPressable))
            .first;
        expect(
          tester.getSize(button).height,
          greaterThanOrEqualTo(AppSizes.minTouch),
        );
      }
    });

    testWidgets('ダークでもカードは surface（不透明）で出る', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: listOverrides(upcoming: upcoming, past: past),
          child: MaterialApp(
            theme: AppTheme.darkTheme,
            home: const SessionsScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final card = tester.widget<DecoratedBox>(
        find
            .descendant(
              of: find.byKey(const ValueKey('upcoming-1')),
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
}

/// 一覧の 1 枚（外側の Opacity）の不透明度を取り出す
double _tileOpacity(WidgetTester tester, Key tileKey) {
  final opacity = tester.widget<Opacity>(
    find
        .descendant(of: find.byKey(tileKey), matching: find.byType(Opacity))
        .first,
  );
  return opacity.opacity;
}
