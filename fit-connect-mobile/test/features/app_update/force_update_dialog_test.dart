import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/app_update/data/app_config_repository.dart';
import 'package:fit_connect_mobile/features/app_update/presentation/force_update_dialog.dart';

/// 強制アップデートのダイアログ。ダークで見出しのアイコンが読めること・文字拡大で崩れないことを確かめる。
void main() {
  const withUrl = AppConfig(
    minSupportedVersion: '1.1.0',
    latestVersion: '1.2.0',
    iosStoreUrl: 'https://apps.apple.com/jp/app/id0000000000',
    androidStoreUrl: 'https://play.google.com/store/apps/details?id=x',
  );
  const withoutUrl = AppConfig(
    minSupportedVersion: '1.1.0',
    updateMessage: '重要な不具合修正を含むため、最新バージョンへの更新が必要です。',
  );

  Future<void> pumpDialog(
    WidgetTester tester,
    AppConfig config, {
    ThemeData? theme,
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

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
          body: Center(child: ForceUpdateDialog(config: config)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('ForceUpdateDialog', () {
    testWidgets('ストア URL があれば「アップデート」ボタン、無ければ案内文言だけ', (tester) async {
      await pumpDialog(tester, withUrl);
      expect(find.text('アップデートのお願い'), findsOneWidget);
      expect(find.text('最新バージョン: 1.2.0'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, 'アップデート'), findsOneWidget);

      await pumpDialog(tester, withoutUrl);
      expect(find.text('重要な不具合修正を含むため、最新バージョンへの更新が必要です。'), findsOneWidget);
      expect(find.byType(FilledButton), findsNothing);
    });

    testWidgets('ダーク: 見出しのアイコンはテーマ追従の accent（静的な primary600 ではない）',
        (tester) async {
      await pumpDialog(tester, withUrl, theme: AppTheme.darkTheme);

      final icon = tester.widget<Icon>(find.byIcon(LucideIcons.arrowUpCircle));
      expect(icon.color, AppColorsExtension.dark.accent);
      expect(icon.color, isNot(AppColors.primary600));
    });

    testWidgets('ボタンはテーマの形（actionFill・最小高さ 48）で、44 以上のタップ領域', (tester) async {
      await pumpDialog(tester, withUrl, theme: AppTheme.darkTheme);

      final button = find.widgetWithText(FilledButton, 'アップデート');
      expect(tester.getSize(button).height, greaterThanOrEqualTo(48));
      // 色は個別指定せずテーマ（actionFill / onAction）に任せる
      expect(tester.widget<FilledButton>(button).style, isNull);
    });

    testWidgets('文字拡大 1.35: 見出しが折り返しても overflow しない', (tester) async {
      await pumpDialog(tester, withUrl, textScale: 1.35);

      expect(tester.takeException(), isNull);
      expect(find.text('アップデートのお願い'), findsOneWidget);
    });
  });
}
