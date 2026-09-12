import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';

void main() {
  group('HealthSyncErrorRow', () {
    testWidgets('ダークモードでは dangerTint（濃赤）背景でエラー文が表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.darkTheme,
          home: const Scaffold(
            body: HealthSyncErrorRow(
              message: 'HealthKitへのアクセスが拒否されました',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HealthSyncErrorRow),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, AppColorsExtension.dark.dangerTint);
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
    });

    testWidgets('ライトモードでは dangerTint（淡赤）背景でエラー文が表示される', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: HealthSyncErrorRow(
              message: 'HealthKitへのアクセスが拒否されました',
            ),
          ),
        ),
      );

      final container = tester.widget<Container>(
        find
            .descendant(
              of: find.byType(HealthSyncErrorRow),
              matching: find.byType(Container),
            )
            .first,
      );
      final decoration = container.decoration as BoxDecoration;

      expect(decoration.color, AppColorsExtension.light.dangerTint);
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
    });
  });
}
