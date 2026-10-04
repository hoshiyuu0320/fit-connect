import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'fc.dart';
import 'fc_previews.dart' show FcPreviewApp;

// ============================================
// Fc 追加部品（行・囲み・ボタン・グラフ）のプレビュー。
// 既存の fc_previews.dart は触らず、ここに集約する。
// ============================================

// --- 正本（record-screens.js）のサンプルデータ ---
const _weight = [
  FcChartPoint(61.6, label: '9/1'),
  FcChartPoint(61.8),
  FcChartPoint(61.7, label: '9/5'),
  FcChartPoint(62.1),
  FcChartPoint(62.2, label: '9/9'),
  FcChartPoint(62.3),
  FcChartPoint(62.4, label: '9/13'),
];

const _kcal = <double?>[
  1920, 2050, null, 2010, 1990, null, 2100, //
  1950, 1870, 1980, 2040, 1960, 1160,
];

const _weekdays = ['月', '火', '水', '木', '金', '土', '日'];
const _sleepWeek = <double?>[410, 430, null, 390, 420, 410, 450];

String _hm(double minutes) {
  final m = minutes.round();
  return '${m ~/ 60}:${(m % 60).toString().padLeft(2, '0')}';
}

const _stages = [
  FcSleepStage(label: '深い', minutes: 85, percent: 100),
  FcSleepStage(label: 'レム', minutes: 110, percent: 60),
  FcSleepStage(label: '浅い', minutes: 255, percent: 30),
  FcSleepStage(label: '覚醒', minutes: 20, percent: 0),
];

/// 画面の左右余白つきの縦並び（プレビュー用）
class _PreviewList extends StatelessWidget {
  const _PreviewList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final horizontal = AppSpacing.pageHorizontalOf(context);
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.fromLTRB(horizontal, 24, horizontal, 32),
          children: children,
        ),
      ),
    );
  }
}

/// ホームの「今日のまとめ」。状態違い（通常 / はじめて / 読込中）
class _SummaryCard extends StatelessWidget {
  const _SummaryCard({this.isNew = false, this.loading = false});

  final bool isNew;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    Widget metric(List<FcValuePart> parts) =>
        loading ? const FcRowValue.loading() : FcRowValue.metric(parts);

    return FcRowsCard(
      title: '今日のまとめ',
      padding: FcRowsCard.summaryPadding,
      children: [
        FcListRow(
          density: FcRowDensity.summary,
          icon: LucideIcons.utensils,
          title: '食事',
          caption: loading ? null : (isNew ? 'メッセージから記録できます' : '朝食・昼食を記録'),
          trailing: isNew && !loading
              ? const FcRowValue.missing()
              : metric(const [FcValuePart('2', '回')]),
          onTap: () {},
        ),
        FcListRow(
          density: FcRowDensity.summary,
          icon: LucideIcons.dumbbell,
          title: '運動',
          caption: '今週（9/7〜）',
          trailing: isNew && !loading
              ? const FcRowValue.missing()
              : metric(const [FcValuePart('3', '日')]),
          onTap: () {},
        ),
        FcListRow(
          density: FcRowDensity.summary,
          icon: LucideIcons.scale,
          title: '体重',
          caption: isNew || loading ? null : '前回から +0.1 kg · 7:30',
          trailing: isNew && !loading
              ? const FcRowValue.missing()
              : metric(const [FcValuePart('62.4', 'kg')]),
          onTap: () {},
        ),
        FcListRow(
          density: FcRowDensity.summary,
          icon: LucideIcons.moon,
          title: '睡眠',
          caption:
              loading ? null : (isNew ? 'ヘルスケアと連携すると自動で入ります' : 'HealthKit'),
          trailing: isNew && !loading
              ? const FcRowValue.action('目覚めを記録')
              : metric(
                  const [FcValuePart('7', '時間'), FcValuePart('30', '分')],
                ),
          onTap: () {},
        ),
      ],
    );
  }
}

/// 全部品を縦に並べたギャラリー
class FcExtraPreviewGallery extends StatefulWidget {
  const FcExtraPreviewGallery({super.key});

  @override
  State<FcExtraPreviewGallery> createState() => _FcExtraPreviewGalleryState();
}

class _FcExtraPreviewGalleryState extends State<FcExtraPreviewGallery> {
  bool _messages = true;
  bool _goal = true;
  bool _remind = false;

  @override
  Widget build(BuildContext context) {
    return _PreviewList(
      children: [
        const FcPageHeading(title: '追加部品'),

        // --- 行・行カード ---
        const FcSectionTitle('行と行カード'),
        const SizedBox(height: AppSpacing.md),
        const _SummaryCard(),
        const SizedBox(height: AppSpacing.cardGap),
        FcRowsCard(
          children: [
            FcListRow.toggle(
              title: 'トレーナーからのメッセージ',
              value: _messages,
              onChanged: (v) => setState(() => _messages = v),
            ),
            FcListRow.toggle(
              title: '目標の達成',
              value: _goal,
              onChanged: (v) => setState(() => _goal = v),
            ),
            FcListRow.toggle(
              title: 'セッションのリマインド',
              caption: '前日と当日の朝にお知らせ',
              value: _remind,
              onChanged: (v) => setState(() => _remind = v),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcRowsCard(
          children: [
            FcListRow(
              icon: LucideIcons.heartPulse,
              title: 'HealthKit',
              caption: '連携中 · 睡眠 · 最終同期 9月13日（日）7:32',
              onTap: () {},
            ),
            FcListRow(title: '利用規約', externalLink: true, onTap: () {}),
            FcListRow(
              icon: LucideIcons.logOut,
              title: 'ログアウト',
              chevron: false,
              onTap: () {},
            ),
            Builder(
              builder: (context) => FcListRow(
                title: 'アカウントを削除',
                color: AppColors.of(context).error,
                chevron: false,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcRowsCard(
          children: [
            for (final r in const [
              ('9月13日（日）7:30', 'メッセージから', '62.4 kg', false),
              ('9月9日（水）', '目覚め だるい · 手動の記録のみ', '未取得', true),
            ])
              FcListRow(
                density: FcRowDensity.record,
                title: r.$1,
                caption: r.$2,
                trailing: FcRowValue.text(r.$3, muted: r.$4),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcCard(
          paddingOverride: const EdgeInsets.fromLTRB(20, 16, 20, 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FcCardHead(
                  icon: LucideIcons.utensils,
                  label: 'PFCバランス（1日平均）',
                  note: '推定'),
              FcStatList(
                items: const [
                  FcStatItem(
                    label: 'たんぱく質',
                    description: '記録した10日の平均',
                    value: '95 g',
                  ),
                  FcStatItem(label: '脂質', value: '64 g'),
                  FcStatItem(label: '炭水化物', value: null),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xxl),

        // --- 囲み・ボタン ---
        const FcSectionTitle('囲み・ボタン'),
        const SizedBox(height: AppSpacing.md),
        FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FcInfoBox(
                child: Row(
                  children: [
                    Expanded(child: _InfoCell(label: '就寝', value: '23:30')),
                    Expanded(child: _InfoCell(label: '起床', value: '7:20')),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const FcInfoBox(
                child: Text('写真からの推定（目安）640 kcal'),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Row(
          children: [
            FcIconButton(
              icon: LucideIcons.camera,
              semanticLabel: '写真を添付',
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.sm),
            FcIconButton(
              icon: LucideIcons.arrowUp,
              semanticLabel: '送信',
              primary: true,
              onPressed: () {},
            ),
            const SizedBox(width: AppSpacing.sm),
            const FcIconButton(
              icon: LucideIcons.arrowUp,
              semanticLabel: '送信（入力が空）',
              primary: true,
              onPressed: null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Builder(
              builder: (context) => FcIconButton(
                icon: LucideIcons.refreshCw,
                semanticLabel: '睡眠を同期',
                iconColor: AppColors.of(context).accent,
                onPressed: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcCard(
          // 「×」の負マージン相当は、カードの余白を減らして配置側で調整する
          paddingOverride: EdgeInsets.fromLTRB(
            18,
            18 - FcCloseButton.verticalBleed,
            18 - FcCloseButton.endBleed,
            18,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(LucideIcons.utensils, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  const Expanded(child: Text('食事を記録')),
                  FcCloseButton(onPressed: () {}),
                ],
              ),
              const SizedBox(height: 12 - FcCloseButton.verticalBleed),
              const Text('フォームの本文'),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: const [
            FcPhotoPlaceholder(width: 72, height: 72, radius: 14),
            SizedBox(width: AppSpacing.sm),
            Expanded(
              child:
                  FcPhotoPlaceholder(height: 132, radius: 20, label: '食事の写真'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),

        // --- グラフ ---
        const FcSectionTitle('グラフ'),
        const SizedBox(height: AppSpacing.md),
        const _ChartCards(),
      ],
    );
  }
}

class _InfoCell extends StatelessWidget {
  const _InfoCell({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTextStyles.caption(context)),
        Text(
          value,
          style: AppTextStyles.exerciseName(context)
              .copyWith(fontFeatures: AppTextStyles.tabularFigures),
        ),
      ],
    );
  }
}

/// グラフ 3 種（折れ線・棒・睡眠の内訳）をカードに入れて並べる
class _ChartCards extends StatelessWidget {
  const _ChartCards();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FcCardHead(
                icon: LucideIcons.scale,
                label: '体重',
                note: '9月1日〜13日',
              ),
              const SizedBox(height: AppSpacing.md),
              const FcNum(value: '62.4', unit: 'kg'),
              const SizedBox(height: 14),
              const FcLineChart(
                data: _weight,
                goal: 65,
                goalLabel: '目標 65.0 kg',
                min: 61,
                max: 65.4,
                height: 150,
                semanticLabel: '9月の体重の推移',
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FcCardHead(
                icon: LucideIcons.utensils,
                label: '摂取カロリー',
                note: '推定',
              ),
              const SizedBox(height: AppSpacing.lg),
              FcBars(
                showValues: false,
                gap: 4,
                height: 84,
                max: 2400,
                semanticLabel: '1日ごとの摂取カロリー',
                items: [
                  for (var i = 0; i < _kcal.length; i++)
                    FcBarItem(
                      value: _kcal[i],
                      text: _kcal[i]?.round().toString() ?? '',
                      highlighted: i == 12,
                      label:
                          const [0, 3, 6, 9, 12].contains(i) ? '${i + 1}' : '',
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FcBars(
                max: 540,
                height: 96,
                semanticLabel: '直近7日間の睡眠時間',
                items: [
                  for (var i = 0; i < _sleepWeek.length; i++)
                    FcBarItem(
                      value: _sleepWeek[i],
                      text: _sleepWeek[i] == null ? '' : _hm(_sleepWeek[i]!),
                      highlighted: i == 6,
                      label: _weekdays[i],
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.cardGap),
        const FcCard(
          child: FcSleepStageBar(stages: _stages),
        ),
      ],
    );
  }
}

/// 行の状態違い（通常 / はじめて / 読込中）を並べたプレビュー
class FcExtraStatesPreview extends StatelessWidget {
  const FcExtraStatesPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PreviewList(
      children: [
        FcSectionTitle('通常'),
        SizedBox(height: AppSpacing.md),
        _SummaryCard(),
        SizedBox(height: AppSpacing.xxl),
        FcSectionTitle('はじめて（未記録・操作）'),
        SizedBox(height: AppSpacing.md),
        _SummaryCard(isNew: true),
        SizedBox(height: AppSpacing.xxl),
        FcSectionTitle('読込中'),
        SizedBox(height: AppSpacing.md),
        _SummaryCard(loading: true),
      ],
    );
  }
}

/// グラフだけのプレビュー（折れ線の 1 件・ラベルなしも含む）
class FcExtraChartsPreview extends StatelessWidget {
  const FcExtraChartsPreview({super.key});

  @override
  Widget build(BuildContext context) {
    return const _PreviewList(
      children: [
        _ChartCards(),
        SizedBox(height: AppSpacing.cardGap),
        FcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              FcLineChart(
                data: [FcChartPoint(62.4, label: '9/13')],
                height: 110,
                semanticLabel: '体重（1件）',
              ),
              SizedBox(height: AppSpacing.lg),
              FcLineChart(
                data: [
                  FcChartPoint(61.6),
                  FcChartPoint(61.8),
                  FcChartPoint(62.4),
                ],
                height: 90,
                semanticLabel: '体重（ラベルなし）',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------
// Previews
// ---------------------------------------------

@Preview(name: 'Fc 追加部品 - Light')
Widget previewFcExtraLight() => const FcPreviewApp(
      brightness: Brightness.light,
      home: FcExtraPreviewGallery(),
    );

@Preview(name: 'Fc 追加部品 - Dark')
Widget previewFcExtraDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: FcExtraPreviewGallery(),
    );

@Preview(name: 'Fc 追加部品 - 文字拡大 1.35')
Widget previewFcExtraLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: FcExtraPreviewGallery(),
    );

@Preview(name: 'FcListRow - 状態（通常・はじめて・読込中）Light')
Widget previewFcListRowStatesLight() => const FcPreviewApp(
      brightness: Brightness.light,
      home: FcExtraStatesPreview(),
    );

@Preview(name: 'FcListRow - 状態（通常・はじめて・読込中）Dark')
Widget previewFcListRowStatesDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: FcExtraStatesPreview(),
    );

@Preview(name: 'FcListRow - 文字拡大 1.35')
Widget previewFcListRowLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: FcExtraStatesPreview(),
    );

@Preview(name: 'グラフ（折れ線・棒・睡眠の内訳）- Light')
Widget previewFcChartsLight() => const FcPreviewApp(
      brightness: Brightness.light,
      home: FcExtraChartsPreview(),
    );

@Preview(name: 'グラフ（折れ線・棒・睡眠の内訳）- Dark')
Widget previewFcChartsDark() => const FcPreviewApp(
      brightness: Brightness.dark,
      home: FcExtraChartsPreview(),
    );

@Preview(name: 'グラフ（折れ線・棒・睡眠の内訳）- 文字拡大 1.35')
Widget previewFcChartsLargeText() => const FcPreviewApp(
      brightness: Brightness.light,
      textScale: 1.35,
      home: FcExtraChartsPreview(),
    );
