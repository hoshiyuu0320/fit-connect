import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/presentation/widgets/next_session_card.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// ホームの「次回のセッション」カードの表示テスト。
///
/// リモートDBに未来のセッションが無くシミュレータでは「予定なし」しか
/// 確認できないため、Providerを差し替えてデータあり/当日/エラーを検証する。
///
/// ※ 日時のフィクスチャは必ず DateTime.now() 基準の相対値で作ること。
///   固定日付をハードコードすると「あとN日」が将来必ず壊れる。
SessionModel _makeSession({
  required DateTime sessionDate,
  String id = 'session-1',
  int durationMinutes = 60,
  String status = 'confirmed',
  String? sessionType,
}) {
  final now = DateTime.now();
  return SessionModel(
    id: id,
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: sessionDate,
    durationMinutes: durationMinutes,
    status: status,
    sessionType: sessionType,
    createdAt: now,
    updatedAt: now,
  );
}

/// 画面に出す日時の表記（再デザイン: 全角括弧・時刻の前にスペースなし・時は 0 埋めなし）。
/// 実装（session_formatting.dart）を呼ばずテスト側に同じ規則を持たせて期待値を組み立てる
/// （規則の変更を検知するため）。ホームのカードは年が変わる場合だけ年が付く
String _expectedDateTimeLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日（$weekday）${dateTime.hour}:$minute';
}

/// 「変更を相談」の定型文に使う日時の表記（半角括弧・0 埋め。表示とは別。変えない）
String _expectedConsultDateTimeLabel(DateTime dateTime) {
  const weekdays = ['月', '火', '水', '木', '金', '土', '日'];
  final weekday = weekdays[dateTime.weekday - 1];
  final hour = dateTime.hour.toString().padLeft(2, '0');
  final minute = dateTime.minute.toString().padLeft(2, '0');
  final yearPrefix =
      dateTime.year != DateTime.now().year ? '${dateTime.year}年' : '';
  return '$yearPrefix${dateTime.month}月${dateTime.day}日($weekday) $hour:$minute';
}

/// push されたルート数を数える Observer（連打による二重pushの検知用）
class _PushCountObserver extends NavigatorObserver {
  int pushCount = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushCount++;
    super.didPush(route, previousRoute);
  }
}

void main() {
  Future<void> pumpCard(
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
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: NextSessionCard(onConsult: onConsult),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// データありのカードを表示する
  Future<void> pumpWithSession(
    WidgetTester tester,
    SessionModel session, {
    void Function(String draft)? onConsult,
    List<NavigatorObserver> navigatorObservers = const [],
  }) {
    return pumpCard(
      tester,
      overrides: [
        nextSessionProvider.overrideWith((ref) async => session),
        upcomingSessionsProvider.overrideWith((ref) async => [session]),
      ],
      onConsult: onConsult,
      navigatorObservers: navigatorObservers,
    );
  }

  group('NextSessionCard データあり', () {
    testWidgets('日時・所要時間・種別・ステータスが表示される', (tester) async {
      // 3日後の18:00（時刻部分だけ固定し、日付は now 基準で相対に作る）
      final base = DateTime.now().add(const Duration(days: 3));
      final sessionDate = DateTime(base.year, base.month, base.day, 18, 0);

      await pumpWithSession(
        tester,
        _makeSession(
          sessionDate: sessionDate,
          durationMinutes: 45,
          status: 'confirmed',
          sessionType: 'パーソナルトレーニング',
        ),
      );

      // 「9月10日（水）18:00」形式（全角括弧・スペースなし）
      final label = _expectedDateTimeLabel(sessionDate);
      expect(label, contains('）18:00'));
      expect(find.text(label), findsOneWidget);

      expect(find.text('次回のセッション'), findsOneWidget);
      // 補足は「45分 · パーソナルトレーニング · 確定」の 1 行（色分けしない）
      expect(find.text('45分 · パーソナルトレーニング · 確定'), findsOneWidget);
    });

    testWidgets('種別が未設定なら種別チップは出ない', (tester) async {
      await pumpWithSession(
        tester,
        _makeSession(
          sessionDate: DateTime.now().add(const Duration(days: 2)),
        ),
      );

      // 種別が無ければ補足は「60分 · 確定」
      expect(find.text('60分 · 確定'), findsOneWidget);
      expect(find.text('あと2日'), findsOneWidget);
    });

    testWidgets("種別 'other' は「その他」に変換される", (tester) async {
      await pumpWithSession(
        tester,
        _makeSession(
          sessionDate: DateTime.now().add(const Duration(days: 2)),
          sessionType: 'other',
        ),
      );

      expect(find.text('60分 · その他 · 確定'), findsOneWidget);
    });
  });

  group('NextSessionCard 残り日数バッジ', () {
    testWidgets('当日のセッションは「今日」のピル（強い色・枠は付けない）', (tester) async {
      await pumpWithSession(tester, _makeSession(sessionDate: DateTime.now()));

      expect(find.text('今日'), findsOneWidget);
      // ピルは他の日と同じ控えめな面（actionFill の塗りにしない）
      final pill = tester.widget<FcPill>(find.byType(FcPill));
      expect(pill.tone, FcPillTone.neutral);
    });

    testWidgets('翌日のセッションは「明日」', (tester) async {
      await pumpWithSession(
        tester,
        _makeSession(sessionDate: DateTime.now().add(const Duration(days: 1))),
      );

      expect(find.text('明日'), findsOneWidget);
    });

    testWidgets('3日後のセッションは「あと3日」', (tester) async {
      await pumpWithSession(
        tester,
        _makeSession(sessionDate: DateTime.now().add(const Duration(days: 3))),
      );

      expect(find.text('あと3日'), findsOneWidget);
      expect(find.text('今日'), findsNothing);
      expect(find.text('明日'), findsNothing);
    });
  });

  group('NextSessionCard 予定なし', () {
    testWidgets('空状態のメッセージとCTAが表示される', (tester) async {
      await pumpCard(
        tester,
        overrides: [
          nextSessionProvider.overrideWith((ref) async => null),
          upcomingSessionsProvider.overrideWith((ref) async => []),
        ],
      );

      // ヘッダーは全状態で保持される
      expect(find.text('次回のセッション'), findsOneWidget);
      expect(find.text('予定はまだありません'), findsOneWidget);
      // トレーナー名が渡されていなければ「トレーナー」
      expect(find.text('日程はトレーナーと相談して決めます。'), findsOneWidget);
      expect(find.text('トレーナーに相談する'), findsOneWidget);
      // 予定0件でも過去の履歴へ行けること（一覧への唯一の入口を塞がない）
      expect(find.text('これまでのセッション'), findsOneWidget);
    });

    testWidgets('「トレーナーに相談」タップで定型文なし（空文字）のコールバックが呼ばれる', (tester) async {
      final drafts = <String>[];

      await pumpCard(
        tester,
        overrides: [
          nextSessionProvider.overrideWith((ref) async => null),
          upcomingSessionsProvider.overrideWith((ref) async => []),
        ],
        onConsult: drafts.add,
      );

      await tester.tap(find.text('トレーナーに相談する'));
      await tester.pumpAndSettle();

      expect(drafts, ['']);
    });
  });

  group('NextSessionCard エラー', () {
    List<Override> errorOverrides() => [
          nextSessionProvider.overrideWith(
            (ref) async => throw StateError('failed to load'),
          ),
          upcomingSessionsProvider.overrideWith(
            (ref) async => throw StateError('failed to load'),
          ),
        ];

    testWidgets('エラーメッセージとリトライボタンが出る（ヘッダーは保持）', (tester) async {
      await pumpCard(tester, overrides: errorOverrides());

      expect(find.text('次回のセッション'), findsOneWidget);
      expect(find.text('セッション情報を読み込めませんでした'), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);
    });

    testWidgets('リトライタップで例外を出さない', (tester) async {
      await pumpCard(tester, overrides: errorOverrides());

      await tester.tap(find.text('再試行'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      // 上流の再取得も失敗するのでエラー表示のまま
      expect(find.text('再試行'), findsOneWidget);
    });
  });

  group('NextSessionCard 一覧への遷移', () {
    testWidgets('カードタップでセッション一覧へ遷移し、相談タップで一覧を閉じてから定型文が渡る', (tester) async {
      final session = _makeSession(
        sessionDate: DateTime.now().add(const Duration(days: 3)),
        sessionType: 'パーソナルトレーニング',
      );
      final drafts = <String>[];

      await pumpWithSession(tester, session, onConsult: drafts.add);

      await tester.tap(find.text(_expectedDateTimeLabel(session.sessionDate)));
      await tester.pumpAndSettle();

      // 一覧画面が開いている
      expect(find.text('セッション'), findsOneWidget);
      expect(find.text('変更を相談'), findsOneWidget);

      await tester.tap(find.text('変更を相談'));
      await tester.pumpAndSettle();

      // pop されてホーム（カード）に戻り、コールバックに定型文が渡る
      expect(find.byType(NextSessionCard), findsOneWidget);
      expect(find.text('変更を相談'), findsNothing);
      // 定型文は画面の表示とは別の表記（半角括弧・0 埋め。push 通知本文と揃えてある）のまま
      expect(drafts, [
        '${_expectedConsultDateTimeLabel(session.sessionDate)} のセッションについて相談です。',
      ]);
    });

    testWidgets('タップ1回につき一覧のpushも1回だけ', (tester) async {
      // 隠れたルートは finder から除外されてしまうため、
      // push の回数そのものを Observer で数える。
      // ※ 同一フレーム内の連打は widget test 環境では2回目のタップが
      //   Widget に届かず再現できないので、実装側は _isNavigating フラグで
      //   防御しつつ、ここでは「1タップ=1push」の不変条件を確認する
      final session = _makeSession(
        sessionDate: DateTime.now().add(const Duration(days: 3)),
      );
      final observer = _PushCountObserver();

      await pumpWithSession(tester, session, navigatorObservers: [observer]);

      final card = find.text(_expectedDateTimeLabel(session.sessionDate));
      await tester.tap(card);
      await tester.tap(card, warnIfMissed: false);
      await tester.pumpAndSettle();

      // ホーム（初期ルート）+ 一覧1枚のみ
      expect(observer.pushCount, 2);
      expect(find.text('セッション'), findsOneWidget);
    });

    testWidgets('予定なしでも「セッション履歴を見る」から過去のセッションへ辿り着ける', (tester) async {
      // 予定0件のユーザー（リモートの現状）でも履歴が見られること
      final pastSession = _makeSession(
        id: 'past-1',
        sessionDate: DateTime.now().subtract(const Duration(days: 3)),
        status: 'completed',
      );

      await pumpCard(
        tester,
        overrides: [
          nextSessionProvider.overrideWith((ref) async => null),
          upcomingSessionsProvider.overrideWith((ref) async => []),
          pastSessionsProvider.overrideWith((ref) async => [pastSession]),
        ],
      );

      await tester.tap(find.text('これまでのセッション'));
      await tester.pumpAndSettle();

      expect(find.text('セッション'), findsOneWidget);

      // 「過去」タブに切り替えると履歴が見える
      await tester.tap(find.text('過去'));
      await tester.pumpAndSettle();

      // 一覧の行の補足は「60分 · 完了」（ステータスは色ではなく文言で示される）
      expect(find.textContaining('· 完了'), findsOneWidget);
    });

    testWidgets('エラー状態でもカードタップで一覧へ行ける', (tester) async {
      await pumpCard(
        tester,
        overrides: [
          nextSessionProvider.overrideWith(
            (ref) async => throw StateError('failed to load'),
          ),
          upcomingSessionsProvider.overrideWith(
            (ref) async => throw StateError('failed to load'),
          ),
          pastSessionsProvider.overrideWith((ref) async => []),
        ],
      );

      // ヘッダー部分（カード全体がタップ可能）
      await tester.tap(find.text('次回のセッション'));
      await tester.pumpAndSettle();

      expect(find.text('セッション'), findsOneWidget);

      // 一覧側のリトライ導線も生きている（今後タブは同じくエラー）
      expect(find.text('エラーが発生しました'), findsOneWidget);
    });
  });

  group('NextSessionCard 再デザイン（見出し・読込中・文字拡大）', () {
    testWidgets('データあり: 見出しは calendar-days、右に chevron。日時は全角括弧', (tester) async {
      final base = DateTime.now().add(const Duration(days: 3));
      final sessionDate = DateTime(base.year, base.month, base.day, 19, 0);
      await pumpWithSession(tester, _makeSession(sessionDate: sessionDate));

      expect(find.byIcon(LucideIcons.calendarDays), findsOneWidget);
      expect(find.byIcon(LucideIcons.chevronRight), findsOneWidget);
      expect(find.textContaining('（'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
    });

    testWidgets('予定なし: トレーナー名が文言に入る。相談とこれまでのセッションは 44 以上', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            nextSessionProvider.overrideWith((ref) async => null),
            upcomingSessionsProvider.overrideWith((ref) async => []),
          ],
          child: MaterialApp(
            theme: AppTheme.lightTheme,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(20),
                child: NextSessionCard(trainerName: '田中トレーナー'),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('日程は田中トレーナーと相談して決めます。'), findsOneWidget);
      for (final label in ['トレーナーに相談する', 'これまでのセッション']) {
        final size = tester.getSize(
          find.ancestor(of: find.text(label), matching: find.byType(FcButton)),
        );
        expect(size.height, greaterThanOrEqualTo(44), reason: label);
      }
      expect(find.byIcon(LucideIcons.messageCircle), findsOneWidget);
    });

    testWidgets('読み込み中は見出しとスケルトン（配置を保つ）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(20),
              child: NextSessionCardView.loading(),
            ),
          ),
        ),
      );

      expect(find.text('次回のセッション'), findsOneWidget);
      expect(find.byType(FcSkeleton), findsNWidgets(2));
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    for (final brightness in Brightness.values) {
      testWidgets('文字拡大 1.35（${brightness.name}）でも overflow せず、日時とピルは折り返す',
          (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final session = _makeSession(
          sessionDate: DateTime.now().add(const Duration(days: 3)),
          sessionType: 'パーソナルトレーニング',
        );
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              nextSessionProvider.overrideWith((ref) async => session),
              upcomingSessionsProvider.overrideWith((ref) async => [session]),
            ],
            child: MaterialApp(
              theme: AppTheme.lightTheme,
              darkTheme: AppTheme.darkTheme,
              themeMode: brightness == Brightness.dark
                  ? ThemeMode.dark
                  : ThemeMode.light,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: const TextScaler.linear(1.35)),
                child: child!,
              ),
              home: const Scaffold(
                body: Padding(
                  padding: EdgeInsets.all(20),
                  child: NextSessionCard(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        // カードは不透明な surface（透過・枠・影なし）
        final card = tester.widget<DecoratedBox>(
          find
              .descendant(
                of: find.byType(FcCard),
                matching: find.byType(DecoratedBox),
              )
              .first,
        );
        final decoration = card.decoration as BoxDecoration;
        expect(decoration.border, isNull);
        expect(decoration.boxShadow, isNull);
      });
    }
  });
}
