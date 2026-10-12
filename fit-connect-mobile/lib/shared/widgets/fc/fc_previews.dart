import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'fc.dart';

// ============================================
// Fc 部品のプレビュー（部品ごとに散らさず、ここに集約する）
// ============================================

/// プレビュー用の MaterialApp。ライト/ダーク・文字拡大を切り替えられる。
class FcPreviewApp extends StatelessWidget {
  const FcPreviewApp({
    super.key,
    required this.brightness,
    required this.home,
    this.textScale = 1.0,
  });

  final Brightness brightness;
  final Widget home;
  final double textScale;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      darkTheme: AppTheme.darkTheme,
      themeMode:
          brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: home,
    );
  }
}

/// 全部品を縦に並べたギャラリー。選択系は押して切り替えられる。
///
/// 並びは正本の画面での使われ方に合わせている（カードの見出し → 数値 → 区切り → ピル、
/// 単独の行のセグメント、ページ背景の上のチップ など）。
class FcPreviewGallery extends StatefulWidget {
  const FcPreviewGallery({super.key});

  @override
  State<FcPreviewGallery> createState() => _FcPreviewGalleryState();
}

class _FcPreviewGalleryState extends State<FcPreviewGallery> {
  String _period = 'month';
  String _subTab = 'weight';
  String _meal = 'lunch';
  String _kind = 'all';
  bool _toggle = true;
  bool _toggleOff = false;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);

    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
          children: [
            const FcPageHeading(
              eyebrow: '10月4日（日）',
              title: 'ホーム',
              subtitle: '今日の記録と、トレーナーからのコメントです。',
            ),

            // --- ボタン ---
            FcButton.block(label: '送信する', onPressed: () {}),
            const SizedBox(height: AppSpacing.sm),
            const FcButton.block(label: '送信する（無効）', onPressed: null),
            const SizedBox(height: AppSpacing.sm),
            FcButton.block(
              label: '送信する',
              onPressed: () {},
              loading: true,
            ),
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FcButton.pill(
                  label: 'トレーナーに相談する',
                  icon: LucideIcons.messageCircle,
                  iconPosition: FcIconPosition.start,
                  onPressed: () {},
                ),
                FcButton.pill(label: '日付を変更', quiet: true, onPressed: () {}),
                const FcButton.pill(label: '今日やる', onPressed: null),
                FcButton.back(label: '戻る', onPressed: () {}),
                FcButton.back(
                  label: '編集',
                  icon: LucideIcons.pencil,
                  onPressed: () {},
                ),
                FcButton.back(
                  label: 'これまでのセッション',
                  icon: LucideIcons.chevronRight,
                  iconPosition: FcIconPosition.end,
                  onPressed: () {},
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            FcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('カードの下に置く文字ボタン'),
                  FcButton.text(
                    label: 'メッセージを送る',
                    icon: LucideIcons.chevronRight,
                    onPressed: () {},
                  ),
                ],
              ),
            ),

            // --- カード ---
            const FcSectionTitle('カード'),
            const SizedBox(height: AppSpacing.cardGap),
            FcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const FcCardHead(
                    icon: LucideIcons.scale,
                    label: '目標',
                    note: '12月31日まで',
                  ),
                  Wrap(
                    spacing: AppSpacing.md,
                    runSpacing: AppSpacing.md,
                    children: const [
                      FcStat(label: '現在', value: '62.4', unit: 'kg'),
                      FcStat(label: '目標', value: '65.0', unit: 'kg'),
                      FcStat(label: '目標まで', value: '2.6', unit: 'kg'),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const FcSeparator(),
                  const SizedBox(height: AppSpacing.md),
                  const Wrap(
                    spacing: AppSpacing.sm,
                    runSpacing: AppSpacing.sm,
                    children: [
                      FcPill('今日'),
                      FcPill('推定', tone: FcPillTone.muted),
                      FcPill('完了',
                          tone: FcPillTone.strong, icon: LucideIcons.check),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  FcCardHead(
                    icon: LucideIcons.moon,
                    label: '昨夜の睡眠',
                    trailing: const FcPill(
                      'HealthKit',
                      tone: FcPillTone.muted,
                      icon: LucideIcons.heartPulse,
                    ),
                  ),
                  const FcNum.parts(
                    size: FcNumSize.review,
                    parts: [FcNumPart('7', '時間'), FcNumPart('30', '分')],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  const FcNum(value: '1,987', unit: 'kcal'),
                  const SizedBox(height: AppSpacing.sm),
                  const FcStat(
                    label: '開始時から',
                    value: '+1.4',
                    unit: 'kg',
                    size: FcNumSize.compact,
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcCard(
              padding: FcCardPadding.coach,
              onTap: () {},
              semanticLabel: 'トレーナーからのコメントを開く',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  const FcAvatar(name: '田中 コーチ'),
                  const SizedBox(width: AppSpacing.sm + 2),
                  const Expanded(
                    child: Text('田中 コーチ'),
                  ),
                  FcDoneMark(done: _toggle),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            const Wrap(
              spacing: AppSpacing.md,
              runSpacing: AppSpacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                FcAvatar(name: '山田 太郎', size: FcAvatar.sm),
                FcAvatar(name: '山田 太郎'),
                FcAvatar(name: '山田 太郎', size: AppSizes.avatarProfile),
                FcAvatar(name: '山田 太郎', size: FcAvatar.lg),
                FcDoneMark(done: true),
                FcDoneMark(done: false),
                FcDot(),
                FcDot(filled: false),
              ],
            ),

            // --- 選択 ---
            const FcSectionTitle('選択', note: '押して切り替え'),
            const SizedBox(height: AppSpacing.cardGap),
            FcSegmentedControl<String>(
              items: const [
                FcSegmentedItem(value: 'week', label: '今週'),
                FcSegmentedItem(value: 'month', label: '今月'),
                FcSegmentedItem(value: '3m', label: '3ヶ月'),
              ],
              selected: _period,
              onChanged: (v) => setState(() => _period = v),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcSubTabs<String>(
              items: const [
                FcSubTabItem(value: 'summary', label: 'サマリ'),
                FcSubTabItem(value: 'weight', label: '体重'),
                FcSubTabItem(value: 'meal', label: '食事'),
                FcSubTabItem(value: 'exercise', label: '運動'),
                FcSubTabItem(value: 'sleep', label: '睡眠'),
                FcSubTabItem(value: 'note', label: 'ノート'),
              ],
              selected: _subTab,
              onChanged: (v) => setState(() => _subTab = v),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcChips<String>.single(
              items: const [
                FcChipItem(value: 'all', label: 'すべて'),
                FcChipItem(value: 'strength', label: '筋トレ'),
                FcChipItem(value: 'cardio', label: '有酸素'),
              ],
              selected: _kind,
              onSelected: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: AppSpacing.sm),
            FcChips<String>.single(
              items: const [
                FcChipItem(value: 'breakfast', label: '朝食'),
                FcChipItem(
                    value: 'lunch', label: '昼食', icon: LucideIcons.utensils),
                FcChipItem(value: 'dinner', label: '夕食'),
                FcChipItem(value: 'snack', label: '間食'),
              ],
              selected: _meal,
              onSelected: (v) => setState(() => _meal = v),
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcCard(
              padding: FcCardPadding.none,
              paddingOverride: const EdgeInsets.fromLTRB(10, 16, 10, 8),
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(10, 0, 10, 0),
                    child: FcCardHead(
                      icon: LucideIcons.calendarDays,
                      label: '今週の記録',
                      note: '9/7〜9/13',
                    ),
                  ),
                  FcWeekStrip(
                    days: [
                      for (var i = 0; i < 7; i++)
                        FcWeekDay(
                          date: DateTime(2026, 9, 7).add(Duration(days: i)),
                          mark: switch (i) {
                            0 || 2 => FcDayMark.filled,
                            4 => FcDayMark.hollow,
                            _ => FcDayMark.none,
                          },
                          markWidget: switch (i) {
                            3 => const FcDoneMark(done: true, size: 16),
                            5 => const Text('2回'),
                            _ => null,
                          },
                          selected: i == 6,
                          today: i == 6,
                        ),
                    ],
                    onSelect: (_) {},
                  ),
                ],
              ),
            ),

            // --- 入力 ---
            const FcSectionTitle('入力'),
            const SizedBox(height: AppSpacing.cardGap),
            FcCard(
              child: Column(
                children: [
                  FcTextField.number(label: '体重', unit: 'kg', hintText: '68.4'),
                  const SizedBox(height: AppSpacing.lg),
                  const FcTextField(
                    label: 'メモ',
                    hintText: '気づいたことを書きましょう',
                    helperText: '空のままでも保存できます',
                    minLines: 3,
                    maxLines: 5,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  FcTextField.number(
                    label: 'カロリー',
                    unit: 'kcal',
                    hintText: '0',
                    errorText: '数字で入力してください',
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  const FcTextField(
                    label: '無効の入力欄',
                    hintText: '入力できません',
                    enabled: false,
                  ),
                  const SizedBox(height: AppSpacing.lg),
                  Row(
                    children: [
                      const Expanded(child: Text('通知を受け取る')),
                      FcToggle(
                        value: _toggle,
                        onChanged: (v) => setState(() => _toggle = v),
                        semanticLabel: '通知を受け取る',
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      const Expanded(child: Text('リマインド')),
                      FcToggle(
                        value: _toggleOff,
                        onChanged: (v) => setState(() => _toggleOff = v),
                        semanticLabel: 'リマインド',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // --- 状態 ---
            const FcSectionTitle('状態'),
            const SizedBox(height: AppSpacing.cardGap),
            FcInlineNotice.warning(
              message: 'HealthKitと同期できませんでした。取得済みの値を表示しています。',
              actionLabel: '再試行',
              onAction: () {},
            ),
            const SizedBox(height: AppSpacing.sm),
            const FcInlineNotice.error(message: '体重を保存できませんでした。'),
            const SizedBox(height: AppSpacing.sm),
            const FcInlineNotice.success(message: '体重の記録に追加しました。'),
            const SizedBox(height: AppSpacing.sm),
            const FcInlineNotice.neutral(message: '推定値は目安です。'),
            const SizedBox(height: AppSpacing.cardGap),
            const FcStateMessage.empty(
              title: '今日のプランはありません',
              message: '田中トレーナーがプランを設定すると、ここに表示されます。',
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcStateMessage.error(
              title: '読み込めませんでした',
              message: '時間をおいてもう一度お試しください。',
              actionLabel: '再試行',
              onAction: () {},
            ),
            const SizedBox(height: AppSpacing.cardGap),
            const FcStateMessage.offline(
              title: 'オフラインです',
              message: '接続を確認してください。',
            ),
            const SizedBox(height: AppSpacing.cardGap),
            FcStateMessage.success(
              title: '共有しました',
              message: '田中トレーナーに体重を送りました。',
              actionLabel: 'ホームに戻る',
              actionVariant: FcButtonVariant.text,
              onAction: () {},
            ),
            const SizedBox(height: AppSpacing.cardGap),
            const FcCard(
              child: Row(
                children: [
                  FcSkeleton.circle(),
                  SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      children: [
                        FcSkeleton.line(),
                        SizedBox(height: AppSpacing.sm),
                        FcSkeleton.line(width: 120),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 下部ナビのプレビュー用画面（本文カード + 浮遊ナビ + 未読の点）。
class FcNavPreview extends StatefulWidget {
  const FcNavPreview({super.key, this.showDot = true, this.initialIndex = 0});

  final bool showDot;
  final int initialIndex;

  @override
  State<FcNavPreview> createState() => _FcNavPreviewState();
}

class _FcNavPreviewState extends State<FcNavPreview> {
  late int _index = widget.initialIndex;

  static const _tabs = <({IconData icon, String label})>[
    (icon: LucideIcons.home, label: 'ホーム'),
    (icon: LucideIcons.messageSquare, label: 'メッセージ'),
    (icon: LucideIcons.dumbbell, label: 'プラン'),
    (icon: LucideIcons.barChart2, label: '記録'),
    (icon: LucideIcons.settings, label: '設定'),
  ];

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return FcBottomNavLayout(
      body: Scaffold(
        body: SafeArea(
          child: ListView(
            padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 0),
            children: [
              const FcPageHeading(title: 'ホーム', eyebrow: '今日'),
              for (var i = 0; i < 6; i++) ...[
                FcCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      FcCardHead(
                          icon: LucideIcons.activity, label: 'カード ${i + 1}'),
                      const Text('本文はナビの下に潜らず、いちばん下までスクロールするとナビの上に収まります。'),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.cardGap),
              ],
            ],
          ),
        ),
      ),
      bottomNav: FcBottomNav(
        currentIndex: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          for (var i = 0; i < _tabs.length; i++)
            FcBottomNavItem(
              icon: _tabs[i].icon,
              label: _tabs[i].label,
              showDot: i == 1 && widget.showDot,
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------
// Previews
// ---------------------------------------------

@Preview(name: 'Fc 部品一覧 - Light')
Widget previewFcComponentsLight() => const FcPreviewApp(
      brightness: Brightness.light,
      home: FcPreviewGallery(),
    );

@Preview(name: 'Fc 部品一覧 - Dark')
Widget previewFcComponentsDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: FcPreviewGallery(),
    );

@Preview(name: 'Fc 部品一覧 - 文字拡大 1.35')
Widget previewFcComponentsLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: FcPreviewGallery(),
    );

@Preview(name: 'FcBottomNav - Light（未読の点あり）')
Widget previewFcBottomNavLight() => const FcPreviewApp(
      brightness: Brightness.light,
      home: FcNavPreview(),
    );

@Preview(name: 'FcBottomNav - Dark（記録を選択）')
Widget previewFcBottomNavDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: FcNavPreview(initialIndex: 3),
    );

@Preview(name: 'FcBottomNav - 文字拡大 1.35')
Widget previewFcBottomNavLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: FcNavPreview(),
    );
