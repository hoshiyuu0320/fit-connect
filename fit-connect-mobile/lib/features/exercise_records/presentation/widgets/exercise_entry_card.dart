import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// 記録一覧の運動 1 件ぶんのカード（運動の記録・プランの完了で共通）。
/// 正本は `record-screens.js` の `ExRecord`。
///
/// 上から: 見出し（アイコン + 種別、右に日時）→ 題名（17 / 500）→ ノート（16・任意）→
/// 補足（13・textSecondary・任意。「消費 320 kcal · メッセージから」）。
/// 種類ごとのカード色・絵文字は使わず、アイコンと言葉で区別する。
class ExerciseEntryCard extends StatelessWidget {
  const ExerciseEntryCard({
    super.key,
    required this.icon,
    required this.type,
    required this.time,
    required this.title,
    this.note,
    this.meta,
  });

  /// 見出しのアイコン（筋トレ = dumbbell、有酸素 = footprints）
  final IconData icon;

  /// 種別（「有酸素」「筋トレ」「プランの完了」など）
  final String type;

  /// 右上の日時（「9月12日（土）18:20」。プランの完了は日付だけ）
  final String time;

  /// 題名（「ランニング 5.0 km · 30分」）
  final String title;

  /// 任意のノート（利用者のメモ・完了報告の感想）
  final String? note;

  /// 補足（「消費 320 kcal · メッセージから」）
  final String? meta;

  @override
  Widget build(BuildContext context) {
    final noteText = note?.trim();
    final metaText = meta?.trim();

    return FcCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FcCardHead(
            icon: icon,
            label: type,
            note: time,
            bottomSpacing: 4,
          ),
          Text(title, style: AppTextStyles.exerciseName(context)),
          if (noteText != null && noteText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                noteText,
                style: AppTextStyles.body(context).copyWith(height: 1.6),
              ),
            ),
          if (metaText != null && metaText.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(metaText, style: AppTextStyles.supplement(context)),
            ),
        ],
      ),
    );
  }
}

// ============================================
// Previews
// ============================================

Widget _previewApp(Brightness brightness, double textScale, Widget child) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: child,
        ),
      ),
    ),
  );
}

Widget _previewCards() => const Column(
      children: [
        ExerciseEntryCard(
          icon: LucideIcons.footprints,
          type: '有酸素',
          time: '9月12日（土）18:20',
          title: 'ランニング 5.0 km · 30分',
          meta: '消費 320 kcal · メッセージから',
        ),
        SizedBox(height: 16),
        ExerciseEntryCard(
          icon: LucideIcons.dumbbell,
          type: 'プランの完了',
          time: '9月9日（水）',
          title: '全身 · 4種目',
          note: 'スクワットのフォームを意識できました。',
          meta: '消費 280 kcal',
        ),
      ],
    );

@Preview(name: 'ExerciseEntryCard - 通常')
Widget previewExerciseEntryCard() =>
    _previewApp(Brightness.light, 1, _previewCards());

@Preview(name: 'ExerciseEntryCard - ダーク')
Widget previewExerciseEntryCardDark() =>
    _previewApp(Brightness.dark, 1, _previewCards());

@Preview(name: 'ExerciseEntryCard - 文字拡大 1.35')
Widget previewExerciseEntryCardLargeText() =>
    _previewApp(Brightness.light, 1.35, _previewCards());
