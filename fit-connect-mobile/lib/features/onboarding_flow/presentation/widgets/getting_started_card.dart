import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/health/presentation/screens/health_settings_screen.dart';
import 'package:fit_connect_mobile/features/health/providers/health_provider.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// はじめの3ステップカード（ホーム画面最上部）
///
/// 初週の行動（初記録・トレーナーに挨拶・ヘルスケア連携）へ
/// 誘導するチェックリスト。達成判定は既存データから導出する。
///
/// 非表示条件:
/// - 全項目達成
/// - 登録（clients.created_at）から14日経過
/// - 手動で閉じた（SharedPreferences）
class GettingStartedCard extends ConsumerWidget {
  /// 体重記録画面（記録タブ・体重）への遷移
  final VoidCallback? onWeightTap;

  /// メッセージタブへの遷移
  final VoidCallback? onMessageTap;

  const GettingStartedCard({
    super.key,
    this.onWeightTap,
    this.onMessageTap,
  });

  /// カードの自動非表示までの日数（clients.created_at 基準）
  static const int visibleDays = 14;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final client = ref.watch(currentClientProvider).valueOrNull;
    if (client == null) return const SizedBox.shrink();

    // 登録から14日経過で自動非表示
    if (DateTime.now().difference(client.createdAt).inDays >= visibleDays) {
      return const SizedBox.shrink();
    }

    // 手動で閉じた場合は非表示（読み込み完了までも非表示にしてチラつきを防ぐ）
    final dismissedAsync = ref.watch(gettingStartedCardDismissedProvider);
    if (dismissedAsync.valueOrNull != false) return const SizedBox.shrink();

    // 達成判定（既存データから導出）
    final weightDone =
        ref.watch(latestWeightRecordProvider).valueOrNull != null;
    final messageDone =
        ref.watch(hasSentFirstMessageProvider).valueOrNull ?? false;
    final healthDone =
        ref.watch(healthSettingsProvider).valueOrNull?.isEnabled ?? false;

    // 全達成で自動非表示
    if (weightDone && messageDone && healthDone) {
      return const SizedBox.shrink();
    }

    final doneCount =
        [weightDone, messageDone, healthDone].where((done) => done).length;

    return Padding(
      // 次のカードとの間（カード間 16）。カードが出ないときは余白も出ない
      padding: const EdgeInsets.only(bottom: AppSpacing.cardGap),
      child: GettingStartedCardBody(
        doneCount: doneCount,
        totalCount: 3,
        onClose: () =>
            ref.read(gettingStartedCardDismissedProvider.notifier).dismiss(),
        items: [
          GettingStartedItem(
            label: '最初の体重を記録する',
            isDone: weightDone,
            onTap: onWeightTap,
          ),
          GettingStartedItem(
            label: 'トレーナーにメッセージを送る',
            isDone: messageDone,
            onTap: onMessageTap,
          ),
          GettingStartedItem(
            label: 'ヘルスケアと連携する',
            isDone: healthDone,
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HealthSettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

/// はじめの3ステップカードの1項目分のデータ
///
/// 完了は [FcDoneMark]、未完了は空の丸で示す（項目ごとに色・アイコンを割り振らない）。
class GettingStartedItem {
  final String label;
  final bool isDone;
  final VoidCallback? onTap;

  const GettingStartedItem({
    required this.label,
    required this.isDone,
    this.onTap,
  });
}

/// カード本体（プレビュー・テストでも使えるよう Riverpod 非依存）
///
/// 正本: home-screens.js の `GettingStarted`。見出し「はじめの3ステップ」＋「1 / 3」＋ 閉じる（44×44）、
/// 行は完了マーク（22）＋ 文言 ＋「完了」/ chevron。完了した行の文言は textSecondary。
class GettingStartedCardBody extends StatelessWidget {
  final int doneCount;
  final int totalCount;
  final VoidCallback? onClose;
  final List<GettingStartedItem> items;

  const GettingStartedCardBody({
    super.key,
    required this.doneCount,
    required this.totalCount,
    required this.onClose,
    required this.items,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcRowsCard(
      // 上 12・下 4・左右 20。閉じるボタン（44×44）の右端は「×」の字が行の右端に揃うよう
      // カードの右余白へ食い込ませる
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.cardPadding,
        AppSpacing.md,
        AppSpacing.cardPadding,
        AppSpacing.xs,
      ),
      headerEndBleed: FcCloseButton.endBleed,
      header: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                'はじめの3ステップ',
                style: AppTextStyles.body(context)
                    .copyWith(fontWeight: FontWeight.w500),
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$doneCount / $totalCount',
            style: AppTextStyles.supplement(context)
                .copyWith(fontFeatures: AppTextStyles.tabularFigures),
          ),
          const SizedBox(width: AppSpacing.sm),
          FcCloseButton(onPressed: onClose),
        ],
      ),
      children: [
        for (final item in items)
          FcListRow(
            // 正本の行は縦余白 13・最小高さなし（48〜50）。いちばん近い 52 / 12 を使う
            density: FcRowDensity.record,
            leading: FcDoneMark(done: item.isDone, size: 22),
            title: item.label,
            color: item.isDone ? colors.textSecondary : null,
            trailing: item.isDone
                ? Text('完了', style: AppTextStyles.supplement(context))
                : null,
            // 未完了は chevron、完了は「完了」の文字（押せるのは変わらない）
            chevron: item.isDone ? false : null,
            onTap: item.onTap,
          ),
      ],
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: child,
        ),
      ),
    ),
  );
}

GettingStartedCardBody _previewBody({int done = 1}) {
  return GettingStartedCardBody(
    doneCount: done,
    totalCount: 3,
    onClose: () {},
    items: [
      GettingStartedItem(
        label: '最初の体重を記録する',
        isDone: done >= 1,
        onTap: () {},
      ),
      GettingStartedItem(
        label: 'トレーナーにメッセージを送る',
        isDone: done >= 2,
        onTap: () {},
      ),
      GettingStartedItem(
        label: 'ヘルスケアと連携する',
        isDone: done >= 3,
        onTap: () {},
      ),
    ],
  );
}

@Preview(name: 'GettingStartedCard - 進行中 (1 / 3)')
Widget previewGettingStartedCardInProgress() => _previewApp(_previewBody());

@Preview(name: 'GettingStartedCard - これから (0 / 3)')
Widget previewGettingStartedCardNotStarted() =>
    _previewApp(_previewBody(done: 0));

@Preview(name: 'GettingStartedCard - ダーク / 文字 1.35')
Widget previewGettingStartedCardDarkLarge() {
  return _previewApp(
    _previewBody(),
    brightness: Brightness.dark,
    textScale: 1.35,
  );
}
