import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// `#` を入力したときに出す「タグの候補」（正本 `message-screens.js` の `ComposerTags`）。
///
/// surface のカード（角丸 20・余白 上 8 / 下 4）に、見出し「タグの候補」（caption・左右 16）と
/// 候補の行（高さ 44 以上・アイコン 16 accent・`#食事:朝食` 16）を縦に並べる。
/// カテゴリごとに色を割り振らず、アイコンと言葉で区別する（食事 = utensils、運動 = dumbbell /
/// footprints、体重 = scale）。行を押すと [onSelect]（入力欄へ反映）してフォーカスを戻す。
class TagSuggestionList extends StatelessWidget {
  final String query;
  final Function(String tag, bool addSpace, String? example) onSelect;
  final FocusNode? textFieldFocusNode;

  const TagSuggestionList({
    super.key,
    required this.query,
    required this.onSelect,
    this.textFieldFocusNode,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final suggestions = _getSuggestions(query);

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.chatRecordCard),
      ),
      child: Padding(
        padding: const EdgeInsets.only(top: 8, bottom: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 2),
              child: Text('タグの候補', style: AppTextStyles.caption(context)),
            ),
            for (final tag in suggestions)
              _SuggestionRow(
                tag: tag,
                onTap: () {
                  onSelect(tag.tag, tag.addSpace, tag.example);
                  // タグ選択後にTextFieldのフォーカスを維持
                  textFieldFocusNode?.requestFocus();
                },
              ),
          ],
        ),
      ),
    );
  }

  List<TagSuggestion> _getSuggestions(String query) {
    if (query.isEmpty) return [];

    final normalizedQuery = query.replaceAll('#', '').toLowerCase().trim();

    final allTags = [
      // 食事
      const TagSuggestion(
          label: '#食事:朝食',
          icon: LucideIcons.utensils,
          tag: '#食事:朝食',
          keywords: ['食事', '朝食', 'meal', 'breakfast'],
          example: '例: #食事:朝食 トースト、目玉焼き、サラダ'),
      const TagSuggestion(
          label: '#食事:昼食',
          icon: LucideIcons.utensils,
          tag: '#食事:昼食',
          keywords: ['食事', '昼食', 'meal', 'lunch'],
          example: '例: #食事:昼食 サラダチキン、玄米おにぎり'),
      const TagSuggestion(
          label: '#食事:夕食',
          icon: LucideIcons.utensils,
          tag: '#食事:夕食',
          keywords: ['食事', '夕食', 'meal', 'dinner'],
          example: '例: #食事:夕食 鶏むね肉のグリル、味噌汁'),
      const TagSuggestion(
          label: '#食事:間食',
          icon: LucideIcons.utensils,
          tag: '#食事:間食',
          keywords: ['食事', '間食', 'meal', 'snack'],
          example: '例: #食事:間食 プロテインバー、ナッツ'),
      // 運動
      const TagSuggestion(
          label: '#運動:筋トレ',
          icon: LucideIcons.dumbbell,
          tag: '#運動:筋トレ',
          keywords: ['運動', '筋トレ', 'exercise', 'workout', 'strength'],
          example: '例: #運動:筋トレ ベンチプレス 60分 350kcal'),
      const TagSuggestion(
          label: '#運動:有酸素',
          icon: LucideIcons.footprints,
          tag: '#運動:有酸素',
          keywords: ['運動', '有酸素', 'exercise', 'cardio', 'run'],
          example: '例: #運動:有酸素 ウォーキング 30分 3km 150kcal'),
      // 体重
      const TagSuggestion(
          label: '#体重',
          icon: LucideIcons.scale,
          tag: '#体重',
          keywords: ['体重', 'weight'],
          example: '例: #体重 65.5kg 順調に減ってきた！'),
    ];

    if (normalizedQuery.isEmpty) {
      // Show default categories if query is empty or just '#'
      return [
        const TagSuggestion(
            label: '#食事',
            icon: LucideIcons.utensils,
            tag: '#食事',
            keywords: [],
            addSpace: false,
            example: '#食事:朝食 / 昼食 / 夕食 / 間食 から選択'),
        const TagSuggestion(
            label: '#運動',
            icon: LucideIcons.dumbbell,
            tag: '#運動',
            keywords: [],
            addSpace: false,
            example: '#運動:筋トレ / 有酸素 から選択'),
        const TagSuggestion(
            label: '#体重',
            icon: LucideIcons.scale,
            tag: '#体重',
            keywords: [],
            example: '例: #体重 65.5kg'),
      ];
    }

    return allTags.where((tag) {
      if (tag.tag.toLowerCase().contains(normalizedQuery)) return true;
      for (final keyword in tag.keywords) {
        if (keyword.contains(normalizedQuery)) return true;
      }
      return false;
    }).toList();
  }
}

class _SuggestionRow extends StatelessWidget {
  final TagSuggestion tag;
  final VoidCallback onTap;

  const _SuggestionRow({required this.tag, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return FcPressable(
      onTap: onTap,
      semanticLabel: tag.label,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: AppSizes.minTouch),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Row(
            children: [
              ExcludeSemantics(
                child: Icon(tag.icon, size: 16, color: colors.accent),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(tag.label, style: AppTextStyles.body(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class TagSuggestion {
  final String label;
  final IconData icon;
  final String tag;
  final List<String> keywords;
  final bool addSpace;
  final String? example;

  const TagSuggestion({
    required this.label,
    required this.icon,
    required this.tag,
    required this.keywords,
    this.addSpace = true,
    this.example,
  });
}

// ============================================
// Previews
// ============================================

Widget _previewApp({
  required Brightness brightness,
  required String query,
  double textScale = 1.0,
}) {
  return MaterialApp(
    theme: brightness == Brightness.dark
        ? AppTheme.darkTheme
        : AppTheme.lightTheme,
    builder: (context, c) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(textScale)),
      child: c!,
    ),
    home: Scaffold(
      body: SafeArea(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: TagSuggestionList(query: query, onSelect: (_, __, ___) {}),
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'TagSuggestionList - #食')
Widget previewTagSuggestionListMeal() =>
    _previewApp(brightness: Brightness.light, query: '#食');

@Preview(name: 'TagSuggestionList - # のみ')
Widget previewTagSuggestionListRoot() =>
    _previewApp(brightness: Brightness.light, query: '#');

@Preview(name: 'TagSuggestionList - ダーク')
Widget previewTagSuggestionListDark() =>
    _previewApp(brightness: Brightness.dark, query: '#運');

@Preview(name: 'TagSuggestionList - 文字1.35')
Widget previewTagSuggestionListLarge() =>
    _previewApp(brightness: Brightness.light, query: '#食', textScale: 1.35);
