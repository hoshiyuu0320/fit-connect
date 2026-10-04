import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/getting_started_card.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:lucide_icons/lucide_icons.dart';

void main() {
  Client buildClient({DateTime? createdAt}) {
    return Client(
      clientId: 'client-1',
      name: 'テスト太郎',
      trainerId: 'trainer-1',
      createdAt: createdAt ?? DateTime.now(),
    );
  }

  Widget buildCard({
    required Client client,
    VoidCallback? onWeightTap,
    VoidCallback? onMessageTap,
    double textScale = 1.0,
    ThemeMode themeMode = ThemeMode.light,
  }) {
    return ProviderScope(
      overrides: [
        currentClientProvider.overrideWith((ref) async => client),
        latestWeightRecordProvider.overrideWith((ref) async => null),
        hasSentFirstMessageProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: themeMode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: GettingStartedCard(
              onWeightTap: onWeightTap,
              onMessageTap: onMessageTap,
            ),
          ),
        ),
      ),
    );
  }

  group('GettingStartedCard', () {
    testWidgets('登録直後は3項目と進捗（1 / 3: ヘルスケア連携済み）が表示される', (tester) async {
      // ヘルスケア連携のみ達成済みの状態
      SharedPreferences.setMockInitialValues({'health_enabled': true});

      await tester.pumpWidget(
        buildCard(
          client: buildClient(),
          onWeightTap: () {},
          onMessageTap: () {},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('はじめの3ステップ'), findsOneWidget);
      expect(find.text('最初の体重を記録する'), findsOneWidget);
      expect(find.text('トレーナーにメッセージを送る'), findsOneWidget);
      expect(find.text('ヘルスケアと連携する'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);

      // 達成済みの項目は完了マーク（形でも区別）と「完了」の文字。ほかは空の丸
      final marks =
          tester.widgetList<FcDoneMark>(find.byType(FcDoneMark)).toList();
      expect(marks, hasLength(3));
      expect(marks.where((m) => m.done), hasLength(1));
      expect(marks.every((m) => m.size == 22), isTrue);
      expect(find.text('完了'), findsOneWidget);
      // 未完了の 2 行には chevron（完了の行は「完了」の文字）
      expect(find.byIcon(LucideIcons.chevronRight), findsNWidgets(2));
    });

    testWidgets('完了した項目の文言は textSecondary、未完了は textPrimary', (tester) async {
      SharedPreferences.setMockInitialValues({'health_enabled': true});

      await tester.pumpWidget(buildCard(client: buildClient()));
      await tester.pumpAndSettle();

      final colors = AppColorsExtension.light;
      Color colorOf(String text) =>
          tester.widget<Text>(find.text(text)).style!.color!;
      expect(colorOf('ヘルスケアと連携する'), colors.textSecondary);
      expect(colorOf('最初の体重を記録する'), colors.textPrimary);
    });

    testWidgets('×ボタンで手動クローズすると非表示になる', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(buildCard(client: buildClient()));
      await tester.pumpAndSettle();
      expect(find.text('はじめの3ステップ'), findsOneWidget);

      await tester.tap(find.byIcon(LucideIcons.x));
      await tester.pumpAndSettle();

      expect(find.text('はじめの3ステップ'), findsNothing);
    });

    testWidgets('閉じるボタンは 44×44 以上で「閉じる」のラベルを持つ', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final handle = tester.ensureSemantics();

      await tester.pumpWidget(buildCard(client: buildClient()));
      await tester.pumpAndSettle();

      final size = tester.getSize(find.byType(FcCloseButton));
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
      expect(find.bySemanticsLabel('閉じる'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('行をタップすると体重・メッセージの遷移コールバックが呼ばれる', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var weight = 0;
      var message = 0;

      await tester.pumpWidget(
        buildCard(
          client: buildClient(),
          onWeightTap: () => weight++,
          onMessageTap: () => message++,
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('最初の体重を記録する'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('トレーナーにメッセージを送る'));
      await tester.pumpAndSettle();

      expect(weight, 1);
      expect(message, 1);
    });

    testWidgets('文字拡大 1.35 とダークでも overflow しない', (tester) async {
      SharedPreferences.setMockInitialValues({'health_enabled': true});
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        buildCard(
          client: buildClient(),
          textScale: 1.35,
          themeMode: ThemeMode.dark,
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('はじめの3ステップ'), findsOneWidget);
    });

    testWidgets('登録から14日経過している場合は表示されない', (tester) async {
      SharedPreferences.setMockInitialValues({});

      await tester.pumpWidget(
        buildCard(
          client: buildClient(
            createdAt: DateTime.now().subtract(const Duration(days: 15)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('はじめの3ステップ'), findsNothing);
    });
  });
}
