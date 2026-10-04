import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 同期エラー行は、再デザインで注意の色（warning）の `FcInlineNotice` になった
/// （旧: 淡赤の dangerTint の囲み）。文言「同期エラー: …」は現行のまま。
void main() {
  /// 通知帯の面の色（`FcInlineNotice` の外側の DecoratedBox）
  Color? noticeBackground(WidgetTester tester) {
    final box = tester.widget<DecoratedBox>(
      find
          .descendant(
            of: find.byType(HealthSyncErrorRow),
            matching: find.byType(DecoratedBox),
          )
          .first,
    );
    return (box.decoration as BoxDecoration).color;
  }

  group('HealthSyncErrorRow', () {
    testWidgets('ダークモードでは warningSurface（暗い配色）の背景でエラー文が表示される', (tester) async {
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

      expect(noticeBackground(tester), AppColorsExtension.dark.warningSurface);
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
    });

    testWidgets('ライトモードでは warningSurface（淡い配色）の背景でエラー文が表示される', (tester) async {
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

      expect(noticeBackground(tester), AppColorsExtension.light.warningSurface);
      expect(
        find.text('同期エラー: HealthKitへのアクセスが拒否されました'),
        findsOneWidget,
      );
      expect(find.byType(FcInlineNotice), findsOneWidget);
    });

    testWidgets('色だけでなくアイコンも併用し、onRetry があれば「再試行」が押せる', (tester) async {
      var retried = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: Scaffold(
            body: HealthSyncErrorRow(
              message: 'タイムアウトしました',
              onRetry: () => retried++,
            ),
          ),
        ),
      );

      expect(find.byIcon(LucideIcons.alertCircle), findsOneWidget);
      expect(find.text('再試行'), findsOneWidget);

      await tester.tap(find.text('再試行'));
      await tester.pump();
      expect(retried, 1);
    });

    testWidgets('onRetry が無ければ「再試行」は出ない', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          home: const Scaffold(
            body: HealthSyncErrorRow(message: 'タイムアウトしました'),
          ),
        ),
      );

      expect(find.text('再試行'), findsNothing);
    });

    testWidgets('文字拡大 1.35 でも overflow しない', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(1.35),
            ),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: HealthSyncErrorRow(
                message: 'HealthKitへのアクセスが拒否されました。設定アプリから許可してください',
                onRetry: () {},
              ),
            ),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
    });
  });
}
