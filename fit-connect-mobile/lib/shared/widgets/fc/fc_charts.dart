import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';

// ============================================
// グラフ（折れ線・棒・睡眠の内訳）
// 正本: parts.js の `LineChart` / `Bars`、record-screens.js の `StageBar`
// いずれも `fl_chart` に依存しない（CustomPaint / 通常の Widget）。
// ============================================

/// [FcLineChart] のデータ点
@immutable
class FcChartPoint {
  const FcChartPoint(this.value, {this.label});

  final double value;

  /// x 軸のラベル（例: `9/1`）。null の点にはラベルを出さない
  final String? label;

  @override
  bool operator ==(Object other) =>
      other is FcChartPoint && other.value == value && other.label == label;

  @override
  int get hashCode => Object.hash(value, label);
}

/// 折れ線グラフ（体重の推移など）。
///
/// - 横線 3 本（separator 1px）、目標線（textSecondary・1px・破線 4/4）と右端のラベル（11px）
/// - 折れ線（accent・2px・丸め）、点（半径 2.5・塗り surface・枠 accent 1.5）、
///   **最後の点だけ半径 4・塗り accent**
/// - x ラベル（11px・textSecondary・中央）。ラベル文字は 11px 固定（正本も固定）
/// - 上に 16、下に 24（x ラベルがあるとき）または 6 の余白。全体の高さが [height]
/// - [min] / [max] を省略するとデータと [goal] から余白 10% を足して決める。
///   値が範囲を超えると枠の外に描かれるので、指定するときは全データと目標を含める
/// - [semanticLabel]（例:「9月の体重の推移」）が読み上げ。グラフ本体は読み上げ対象外
/// - 幅は親いっぱい（有限の幅が必要）
///
/// 例: `FcLineChart(data: points, goal: 65, goalLabel: '目標 65.0 kg', height: 150, semanticLabel: '9月の体重の推移')`
class FcLineChart extends StatelessWidget {
  const FcLineChart({
    super.key,
    required this.data,
    required this.semanticLabel,
    this.goal,
    this.goalLabel,
    this.min,
    this.max,
    this.height = 150,
  });

  final List<FcChartPoint> data;
  final String semanticLabel;

  /// 目標値（破線）。null なら描かない
  final double? goal;

  /// 目標線の上（右端）に出す文字（例: `目標 65.0 kg`）
  final String? goalLabel;

  /// y 軸の下端・上端の値。null なら自動
  final double? min;
  final double? max;

  /// グラフ全体の高さ（x ラベルの領域を含む）
  final double height;

  (double, double) _resolveRange() {
    final values = <double>[
      for (final p in data) p.value,
      if (goal != null) goal!,
    ];
    var lo = min;
    var hi = max;
    if (lo == null || hi == null) {
      if (values.isEmpty) {
        lo ??= 0;
        hi ??= 1;
      } else {
        final dataLo = values.reduce(math.min);
        final dataHi = values.reduce(math.max);
        final pad = dataHi == dataLo ? 1.0 : (dataHi - dataLo) * 0.1;
        lo ??= dataLo - pad;
        hi ??= dataHi + pad;
      }
    }
    if (hi <= lo) hi = lo + 1;
    return (lo, hi);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final (lo, hi) = _resolveRange();
    // ラベルは 11px 固定（文字拡大でグラフが潰れない）。フォントはテーマに合わせる
    final labelStyle = DefaultTextStyle.of(context)
        .style
        .merge(AppTextStyles.navLabel(context))
        .copyWith(
          color: colors.textSecondary,
          decoration: TextDecoration.none,
        );

    return Semantics(
      image: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: SizedBox(
        width: double.infinity,
        height: height,
        child: CustomPaint(
          painter: _FcLineChartPainter(
            data: data,
            min: lo,
            max: hi,
            goal: goal,
            goalLabel: goalLabel,
            gridColor: colors.separator,
            goalColor: colors.textSecondary,
            lineColor: colors.accent,
            pointFillColor: colors.surface,
            labelStyle: labelStyle,
          ),
        ),
      ),
    );
  }
}

class _FcLineChartPainter extends CustomPainter {
  _FcLineChartPainter({
    required this.data,
    required this.min,
    required this.max,
    required this.goal,
    required this.goalLabel,
    required this.gridColor,
    required this.goalColor,
    required this.lineColor,
    required this.pointFillColor,
    required this.labelStyle,
  });

  final List<FcChartPoint> data;
  final double min;
  final double max;
  final double? goal;
  final String? goalLabel;
  final Color gridColor;
  final Color goalColor;
  final Color lineColor;
  final Color pointFillColor;
  final TextStyle labelStyle;

  static const double _top = 16;
  static const double _inset = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final hasLabels = data.any((d) => d.label != null);
    final bottom = hasLabels ? 24.0 : 6.0;
    final plotHeight = math.max(0.0, h - _top - bottom);

    double x(int i) => data.length == 1
        ? w / 2
        : _inset + i * (w - _inset * 2) / (data.length - 1);
    double y(double v) => _top + (max - v) / (max - min) * plotHeight;

    // 横線 3 本
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final f in const [0.0, 0.5, 1.0]) {
      final yy = _top + f * plotHeight;
      canvas.drawLine(Offset(0, yy), Offset(w, yy), gridPaint);
    }

    // 目標線（破線 4/4）とラベル
    if (goal != null) {
      final gy = y(goal!);
      final goalPaint = Paint()
        ..color = goalColor
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke;
      final dashed = Path();
      for (var dx = 0.0; dx < w; dx += 8) {
        dashed.moveTo(dx, gy);
        dashed.lineTo(math.min(dx + 4, w), gy);
      }
      canvas.drawPath(dashed, goalPaint);
      if (goalLabel != null) {
        _paintText(
          canvas,
          goalLabel!,
          x: w,
          baselineY: gy - 6,
          alignEnd: true,
        );
      }
    }

    if (data.isNotEmpty) {
      // 折れ線
      final path = Path();
      for (var i = 0; i < data.length; i++) {
        final px = x(i);
        final py = y(data[i].value);
        if (i == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      canvas.drawPath(
        path,
        Paint()
          ..color = lineColor
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke
          ..strokeJoin = StrokeJoin.round
          ..strokeCap = StrokeCap.round,
      );

      // 点（最後だけ大きく塗る）
      final last = data.length - 1;
      final ringPaint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < data.length; i++) {
        final center = Offset(x(i), y(data[i].value));
        final radius = i == last ? 4.0 : 2.5;
        canvas.drawCircle(
          center,
          radius,
          Paint()
            ..color = i == last ? lineColor : pointFillColor
            ..style = PaintingStyle.fill,
        );
        canvas.drawCircle(center, radius, ringPaint);
      }

      // x ラベル
      for (var i = 0; i < data.length; i++) {
        final label = data[i].label;
        if (label == null) continue;
        _paintText(canvas, label, x: x(i), baselineY: h - 4, alignEnd: false);
      }
    }
  }

  /// [baselineY] に文字のベースラインを合わせて描く（SVG の `<text>` と同じ）
  void _paintText(
    Canvas canvas,
    String text, {
    required double x,
    required double baselineY,
    required bool alignEnd,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: labelStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final baseline = painter.computeDistanceToActualBaseline(
      TextBaseline.alphabetic,
    );
    final left = alignEnd ? x - painter.width : x - painter.width / 2;
    painter.paint(canvas, Offset(left, baselineY - baseline));
    painter.dispose();
  }

  @override
  bool shouldRepaint(_FcLineChartPainter old) =>
      !listEquals(old.data, data) ||
      old.min != min ||
      old.max != max ||
      old.goal != goal ||
      old.goalLabel != goalLabel ||
      old.gridColor != gridColor ||
      old.goalColor != goalColor ||
      old.lineColor != lineColor ||
      old.pointFillColor != pointFillColor ||
      old.labelStyle != labelStyle;
}

/// [FcBars] の 1 本
@immutable
class FcBarItem {
  const FcBarItem({
    this.value,
    this.text = '',
    this.highlighted = false,
    this.label = '',
  });

  /// 棒の値（`max` に対する割合で高さが決まる）。**null は「未取得」**（0 と区別する）
  final double? value;

  /// 棒の上に出す値の文字（例: `6:50`）。読み上げにも使う
  final String text;

  /// 強調する棒（今日・最新）。accent の色
  final bool highlighted;

  /// 棒の下の x ラベル（例: `月`）。空なら出さない
  final String label;
}

/// 棒グラフ（直近 7 日の睡眠・摂取カロリーなど）。
///
/// - 列は等幅、棒は列の幅いっぱい（最大 28）・角丸 7・最小高さ 4・最大は [height]
/// - **ハイライト = accent、それ以外 = textSecondary の 28%**
/// - 値が null の列は高さ 2・separator の線にし、[showValues] のとき「未取得」を出す
/// - 値の文字は 11px（文字拡大は 1.15 倍まで・列に収まらなければ縮小）。x ラベルは caption
///   （ハイライトは accent・500）
/// - [semanticLabel] を渡すとグラフ全体の見出しとして読み上げる。各列は「ラベル 値」で読む
///
/// 例: `FcBars(max: 540, height: 96, items: [FcBarItem(value: 410, text: '6:50', label: '月'), ...])`
class FcBars extends StatelessWidget {
  const FcBars({
    super.key,
    required this.items,
    required this.max,
    this.height = 110,
    this.showValues = true,
    this.gap = 8,
    this.semanticLabel,
  });

  final List<FcBarItem> items;

  /// 棒が最大の高さになる値
  final double max;

  /// 棒の領域の高さ（値の文字・x ラベルは含まない）
  final double height;

  /// 棒の上に値の文字を出すか
  final bool showValues;

  /// 列と列の間隔
  final double gap;

  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final valueScaler =
        MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.15);

    final chart = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          Expanded(
            child: _FcBarColumn(
              index: i,
              item: items[i],
              max: max,
              height: height,
              showValues: showValues,
              valueScaler: valueScaler,
              colors: colors,
            ),
          ),
        ],
      ],
    );

    if (semanticLabel == null) return chart;
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: chart,
    );
  }
}

class _FcBarColumn extends StatelessWidget {
  const _FcBarColumn({
    required this.index,
    required this.item,
    required this.max,
    required this.height,
    required this.showValues,
    required this.valueScaler,
    required this.colors,
  });

  final int index;
  final FcBarItem item;
  final double max;
  final double height;
  final bool showValues;
  final TextScaler valueScaler;
  final AppColorsExtension colors;

  static const double _maxBarWidth = 28;

  String get _semanticText {
    final valueText = item.value == null ? '未取得' : item.text;
    return [item.label, valueText].where((s) => s.isNotEmpty).join(' ');
  }

  @override
  Widget build(BuildContext context) {
    final missing = item.value == null;
    final highlighted = item.highlighted;

    final valueStyle = AppTextStyles.navLabel(context).copyWith(
      height: 1.3,
      color: highlighted ? colors.accent : colors.textSecondary,
      fontFeatures: AppTextStyles.tabularFigures,
    );
    final labelStyle = AppTextStyles.caption(context).copyWith(
      color: highlighted ? colors.accent : colors.textSecondary,
      fontWeight: highlighted ? FontWeight.w500 : FontWeight.w400,
    );

    final safeMax = max <= 0 ? 1.0 : max;
    final barHeight = missing
        ? 2.0
        : (item.value! / safeMax * height)
            .clamp(4.0, math.max(4.0, height))
            .toDouble();
    final barColor = missing
        ? colors.separator
        : (highlighted
            ? colors.accent
            : colors.textSecondary.withValues(alpha: 0.28));

    return Semantics(
      container: true,
      label: _semanticText,
      excludeSemantics: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showValues) ...[
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                missing ? '未取得' : item.text,
                maxLines: 1,
                softWrap: false,
                textScaler: valueScaler,
                style: valueStyle,
              ),
            ),
            const SizedBox(height: 6),
          ],
          SizedBox(
            height: height,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final barWidth = math.min(_maxBarWidth, constraints.maxWidth);
                return Align(
                  alignment: Alignment.bottomCenter,
                  child: SizedBox(
                    width: barWidth,
                    height: barHeight,
                    child: DecoratedBox(
                      key: ValueKey('fc-bar-$index'),
                      decoration: BoxDecoration(
                        color: barColor,
                        borderRadius: BorderRadius.circular(missing ? 1 : 7),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 18),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                item.label,
                maxLines: 1,
                softWrap: false,
                style: labelStyle,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// [FcSleepStageBar] の 1 区間
@immutable
class FcSleepStage {
  const FcSleepStage({
    required this.label,
    required this.minutes,
    required this.percent,
  });

  /// 区間の名前（例: `深い` `レム` `浅い` `覚醒`）
  final String label;

  /// 長さ（分）。帯の幅の比率になる
  final int minutes;

  /// 色の濃さ（0〜100）。accent を surface に混ぜる割合。0 は separator 色（覚醒など）
  final int percent;
}

/// 睡眠の内訳（帯グラフ ＋ 凡例）。色の濃淡と文字で区別し、カテゴリ色は使わない。
///
/// - 帯: 高さ 10・角丸 5・区間の間 2。各区間の幅は [FcSleepStage.minutes] の比率
/// - 色: accent を surface に `percent`% 混ぜた色（0 は separator）
/// - 凡例: 2 列（四角 8・角丸 2・ラベル 13 / textSecondary・時間 13 / 500 tabular）。
///   時間は `1時間25分` / `20分`。文字が大きいとき（1.25 倍以上）は 1 列に積む
/// - 上下の余白は含まない（正本は帯の上に 16）。読み上げは [semanticLabel] ＋ 各区間を 1 つに
///
/// 例: `FcSleepStageBar(stages: [FcSleepStage(label: '深い', minutes: 85, percent: 100), ...])`
class FcSleepStageBar extends StatelessWidget {
  const FcSleepStageBar({
    super.key,
    required this.stages,
    this.semanticLabel = '睡眠の内訳',
  });

  final List<FcSleepStage> stages;
  final String semanticLabel;

  /// 分を `〇時間〇〇分`（60 分未満は `〇分`）にする。睡眠の履歴の時間にも使える
  static String formatMinutes(int minutes) {
    if (minutes >= 60) {
      final h = minutes ~/ 60;
      final m = (minutes % 60).toString().padLeft(2, '0');
      return '$h時間$m分';
    }
    return '$minutes分';
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);

    Color fill(int percent) => percent == 0
        ? colors.separator
        : Color.lerp(colors.surface, colors.accent, percent / 100)!;

    final summary = [
      for (final s in stages) '${s.label} ${formatMinutes(s.minutes)}',
    ].join('、');

    final visible = [
      for (var i = 0; i < stages.length; i++)
        if (stages[i].minutes > 0) i,
    ];

    final bar = ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: SizedBox(
        height: 10,
        child: visible.isEmpty
            ? ColoredBox(color: colors.separator)
            : Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var n = 0; n < visible.length; n++) ...[
                    if (n > 0) const SizedBox(width: 2),
                    Expanded(
                      flex: stages[visible[n]].minutes,
                      child: ColoredBox(
                        key: ValueKey('fc-sleep-stage-${visible[n]}'),
                        color: fill(stages[visible[n]].percent),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );

    final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final columns = scale >= 1.25 ? 1 : 2;

    Widget legendItem(FcSleepStage stage) {
      return Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: fill(stage.percent),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(stage.label, style: AppTextStyles.supplement(context)),
          ),
          const SizedBox(width: 6),
          Text(
            formatMinutes(stage.minutes),
            style: AppTextStyles.supplement(context).copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
              fontFeatures: AppTextStyles.tabularFigures,
            ),
          ),
        ],
      );
    }

    final legend = <Widget>[];
    for (var i = 0; i < stages.length; i += columns) {
      if (i > 0) legend.add(const SizedBox(height: AppSpacing.sm));
      legend.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var c = 0; c < columns; c++) ...[
              if (c > 0) const SizedBox(width: AppSpacing.md),
              Expanded(
                child: i + c < stages.length
                    ? legendItem(stages[i + c])
                    : const SizedBox.shrink(),
              ),
            ],
          ],
        ),
      );
    }

    return Semantics(
      container: true,
      label: summary.isEmpty ? semanticLabel : '$semanticLabel、$summary',
      excludeSemantics: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          bar,
          const SizedBox(height: AppSpacing.md),
          ...legend,
        ],
      ),
    );
  }
}
