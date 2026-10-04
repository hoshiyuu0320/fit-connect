import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/home/presentation/utils/home_formatting.dart';
import 'package:fit_connect_mobile/features/sessions/utils/session_formatting.dart';
import 'package:fit_connect_mobile/features/weight_records/presentation/widgets/weight_format.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

// ============================================
// 目標カード
// 正本: home-screens.js の `HomeGoal`（通常 / はじめて / 読込中 / 目標に届いた日）
// 達成率（％）と進捗バーはやめ、「現在 / 目標 / 目標まで」と開始時の体重で示す。
// 達成も演出なしの静かなカード（紙吹雪・ゴールドのカードは出さない）。
// ============================================

/// ホームの目標カード。
///
/// - 通常: 「現在 / 目標 / 目標まで」の 3 つの指標（入り切らなければ折り返す）＋ 区切り線 ＋
///   「{目標の説明} · 開始時 61.0 kg」。右上に期限（あれば）
/// - [isAchieved]: check-circle ＋「目標の 65.0 kg に届きました」。右上に達成日（分かれば）。
///   区切り線の下は「…· 開始時 61.0 kg から +4.0 kg」
/// - [isLoading] / [GoalCard.loading]: 3 つの指標の形のスケルトン
///
/// 「目標まで」は減量・増量どちらでも差の絶対値。増減の符号だけで色分けしない。
class GoalCard extends StatelessWidget {
  const GoalCard({
    super.key,
    required this.currentWeight,
    required this.targetWeight,
    required this.initialWeight,
    this.targetDate,
    this.isLoading = false,
    this.isAchieved = false,
    this.goalDescription,
    this.achievedAt,
  });

  /// 読み込み中（指標の形のスケルトン）
  const GoalCard.loading({super.key})
      : currentWeight = null,
        targetWeight = 0,
        initialWeight = null,
        targetDate = null,
        isLoading = true,
        isAchieved = false,
        goalDescription = null,
        achievedAt = null;

  /// 現在の体重。まだ記録も開始時の体重も無ければ null（「—」を出す。0 とは表示しない）
  final double? currentWeight;
  final double targetWeight;

  /// 開始時の体重。分からなければ null（「開始時…」を出さない）
  final double? initialWeight;
  final DateTime? targetDate;
  final bool isLoading;
  final bool isAchieved;

  /// 目標の説明（例: 「筋肉をつけて体重を増やす」）
  final String? goalDescription;

  /// 達成した日（`goal_achieved_at`）。無ければ右上に出さない
  final DateTime? achievedAt;

  static const String _label = '目標';

  @override
  Widget build(BuildContext context) {
    if (isLoading) return const _GoalLoading();
    if (isAchieved) return _buildAchieved(context);
    return _buildProgress(context);
  }

  /// 「{目標の説明} · 開始時 61.0 kg」（どちらも無ければ null）
  String? _metaLine({bool withChange = false}) {
    final parts = <String>[
      if (goalDescription != null && goalDescription!.trim().isNotEmpty)
        goalDescription!.trim(),
    ];
    final initial = initialWeight;
    if (initial != null) {
      var start = '開始時 ${formatKg(initial)} kg';
      final current = currentWeight;
      if (withChange && current != null) {
        start += ' から ${formatSignedKg(current - initial)} kg';
      }
      parts.add(start);
    }
    return parts.isEmpty ? null : parts.join(' · ');
  }

  Widget _buildProgress(BuildContext context) {
    final now = DateTime.now();
    final current = currentWeight;
    final remaining =
        current == null ? null : (current - targetWeight).abs();
    final meta = _metaLine();

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FcCardHead(
            icon: LucideIcons.scale,
            label: _label,
            note: targetDate == null
                ? null
                : formatDeadline(targetDate!, now: now),
          ),
          _AutoFitStats(
            children: [
              FcStat(
                label: '現在',
                value: current == null ? '—' : formatKg(current),
                unit: current == null ? null : 'kg',
              ),
              FcStat(
                label: '目標',
                value: formatKg(targetWeight),
                unit: 'kg',
              ),
              FcStat(
                label: '目標まで',
                value: remaining == null ? '—' : formatKg(remaining),
                unit: remaining == null ? null : 'kg',
              ),
            ],
          ),
          if (meta != null) _MetaBlock(text: meta),
        ],
      ),
    );
  }

  Widget _buildAchieved(BuildContext context) {
    final colors = AppColors.of(context);
    final now = DateTime.now();
    final meta = _metaLine(withChange: true);

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FcCardHead(
            icon: LucideIcons.scale,
            label: _label,
            note: achievedAt == null
                ? null
                : formatSessionDateDisplay(achievedAt!, now: now),
          ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              ExcludeSemantics(
                child: Icon(
                  LucideIcons.checkCircle2,
                  size: 22,
                  color: colors.accent,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  '目標の ${formatKg(targetWeight)} kg に届きました',
                  style: AppTextStyles.sectionHeading(context),
                ),
              ),
            ],
          ),
          if (meta != null) _MetaBlock(text: meta),
        ],
      ),
    );
  }
}

/// 区切り線（上 16・下 12）＋ 補足の 1 行（13 / textSecondary）
class _MetaBlock extends StatelessWidget {
  const _MetaBlock({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: AppSpacing.lg),
        const FcSeparator(),
        const SizedBox(height: AppSpacing.md),
        Text(text, style: AppTextStyles.supplement(context)),
      ],
    );
  }
}

/// 指標を横に並べ、入り切らなければ折り返す（正本: `repeat(auto-fit, minmax(88px, 1fr))`）。
///
/// 1 列の最小幅は 88、文字拡大に合わせて広げる（数値が途中で折れないようにするため）。
/// 余った幅は各列で等分する。
class _AutoFitStats extends StatelessWidget {
  const _AutoFitStats({required this.children});

  final List<Widget> children;

  static const double _minColumnWidth = 88;
  static const double _gap = AppSpacing.md;

  @override
  Widget build(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context).scale(1.0).clamp(1.0, 4.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final minWidth = _minColumnWidth * scale;
        final columns =
            ((width + _gap) / (minWidth + _gap)).floor().clamp(1, children.length);
        final itemWidth = (width - _gap * (columns - 1)) / columns;
        return Wrap(
          spacing: _gap,
          runSpacing: _gap,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

/// 読み込み中（見出しは出し、3 つの指標の形のスケルトン）
class _GoalLoading extends StatelessWidget {
  const _GoalLoading();

  @override
  Widget build(BuildContext context) {
    return FcCard(
      semanticLabel: '目標を読み込んでいます',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FcCardHead(icon: LucideIcons.scale, label: '目標'),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.md),
                const Expanded(child: _GoalSkeletonColumn()),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _GoalSkeletonColumn extends StatelessWidget {
  const _GoalSkeletonColumn();

  @override
  Widget build(BuildContext context) {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.5,
          child: FcSkeleton(height: 12),
        ),
        SizedBox(height: AppSpacing.sm),
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: 0.8,
          child: FcSkeleton(height: 26),
        ),
      ],
    );
  }
}

/// 目標がまだ設定されていないとき（正本 `HomeGoal` の `variant="new"`）。
class GoalNotSetCard extends StatelessWidget {
  const GoalNotSetCard({super.key, required this.trainerName});

  /// 表示名（「田中トレーナー」）
  final String trainerName;

  @override
  Widget build(BuildContext context) {
    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const FcCardHead(icon: LucideIcons.scale, label: '目標'),
          Text(
            '目標はまだ設定されていません',
            style: AppTextStyles.sectionHeading(context),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            '$trainerNameが目標を設定すると、ここに表示されます。',
            style: AppTextStyles.supplement(context),
          ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(
  List<Widget> children, {
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    darkTheme: AppTheme.darkTheme,
    themeMode:
        brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSpacing.cardGap),
                children[i],
              ],
            ],
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'GoalCard - 進行中（増量）')
Widget previewGoalCardInProgress() {
  return _previewApp([
    GoalCard(
      currentWeight: 62.4,
      targetWeight: 65.0,
      initialWeight: 61.0,
      targetDate: DateTime(DateTime.now().year, 12, 31),
      goalDescription: '筋肉をつけて体重を増やす',
    ),
  ]);
}

@Preview(name: 'GoalCard - 進行中（減量）')
Widget previewGoalCardWeightLoss() {
  return _previewApp([
    GoalCard(
      currentWeight: 65.2,
      targetWeight: 60.0,
      initialWeight: 67.5,
      targetDate: DateTime(DateTime.now().year, 12, 31),
      goalDescription: '体脂肪を落とす',
    ),
  ]);
}

@Preview(name: 'GoalCard - 達成')
Widget previewGoalCardAchieved() {
  return _previewApp([
    GoalCard(
      currentWeight: 65.0,
      targetWeight: 65.0,
      initialWeight: 61.0,
      isAchieved: true,
      goalDescription: '筋肉をつけて体重を増やす',
      achievedAt: DateTime(DateTime.now().year, 12, 2),
    ),
  ]);
}

@Preview(name: 'GoalCard - 未設定 / 読み込み中')
Widget previewGoalCardNotSetAndLoading() {
  return _previewApp(const [
    GoalNotSetCard(trainerName: '田中トレーナー'),
    GoalCard.loading(),
  ]);
}

@Preview(name: 'GoalCard - ダーク / 文字 1.35')
Widget previewGoalCardDarkLarge() {
  return _previewApp(
    brightness: Brightness.dark,
    textScale: 1.35,
    [
      GoalCard(
        currentWeight: 62.4,
        targetWeight: 65.0,
        initialWeight: 61.0,
        targetDate: DateTime(DateTime.now().year, 12, 31),
        goalDescription: '筋肉をつけて体重を増やす',
      ),
    ],
  );
}
