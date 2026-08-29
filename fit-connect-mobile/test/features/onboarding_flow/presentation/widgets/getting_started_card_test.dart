import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/presentation/widgets/getting_started_card.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
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

  Widget buildCard({required Client client}) {
    return ProviderScope(
      overrides: [
        currentClientProvider.overrideWith((ref) async => client),
        latestWeightRecordProvider.overrideWith((ref) async => null),
        hasSentFirstMessageProvider.overrideWith((ref) async => false),
      ],
      child: MaterialApp(
        theme: AppTheme.lightTheme,
        home: const Scaffold(
          body: SingleChildScrollView(
            child: GettingStartedCard(),
          ),
        ),
      ),
    );
  }

  group('GettingStartedCard', () {
    testWidgets('登録直後は3項目と進捗（1/3: ヘルスケア連携済み）が表示される', (tester) async {
      // ヘルスケア連携のみ達成済みの状態
      SharedPreferences.setMockInitialValues({'health_enabled': true});

      await tester.pumpWidget(buildCard(client: buildClient()));
      await tester.pumpAndSettle();

      expect(find.text('はじめの3ステップ'), findsOneWidget);
      expect(find.text('最初の体重を記録する'), findsOneWidget);
      expect(find.text('トレーナーにメッセージを送る'), findsOneWidget);
      expect(find.text('ヘルスケアと連携する'), findsOneWidget);
      expect(find.text('1/3'), findsOneWidget);

      // 達成済み項目はチェックアイコン（1つだけ）
      expect(find.byIcon(LucideIcons.checkCircle2), findsOneWidget);
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
