import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:intl/intl.dart';
import 'package:lucide_icons/lucide_icons.dart';

import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/records_overview/models/daily_nutrition_stat.dart';

/// 栄養トレンド合成チャート
///
/// 体重ライン（kg）と PFC を kcal 換算で積み上げた棒を、
/// **単一の CustomPainter** が 1 つの共通ジオメトリ上に描画する。
///
/// 旧実装は fl_chart の BarChart / LineChart を Stack で 2 枚重ねていたが、
/// 両者の X 軸座標系がズレて棒・点・日付・ツールチップが揃わない構造的問題が
/// あったため、全要素を共通の `xCenter(i)` から導出する自前描画へ作り直した。
///
/// レイヤー（背面→前面）:
///   1. 横グリッド線（kcal 目盛）
///   2. 淡い PFC 積み上げ棒
///   3. 体重エリア塗り
///   4. 目標ライン（緑破線）
///   5. 体重折れ線
///   6. 体重ドット（白抜き青リング）
///   7. アクティブ縦線
///   8. 軸テキスト（左 kcal / 右 kg / 下 日付）
///
/// 凡例は呼び出し側 `records_overview_screen.dart` の `_Legend` が担当する。
class NutritionTrendChart extends StatefulWidget {
  final List<DailyNutritionStat> data;
  final double height;
  final double? targetWeight;

  const NutritionTrendChart({
    super.key,
    required this.data,
    this.height = 240,
    this.targetWeight,
  });

  @override
  State<NutritionTrendChart> createState() => _NutritionTrendChartState();
}

class _NutritionTrendChartState extends State<NutritionTrendChart> {
  /// タッチ中の日のインデックス（指を離す/外れると null）
  int? _touchedIndex;

  // PFC kcal/g 換算係数
  static const double _kcalPerGProtein = 4.0;
  static const double _kcalPerGFat = 9.0;
  static const double _kcalPerGCarbs = 4.0;

  // チャート余白（kcalラベル/kgラベル/日付ラベル用）
  static const double _mLeft = 40;
  static const double _mRight = 34;
  static const double _mTop = 16;
  static const double _mBottom = 26;

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data.isEmpty) {
      return _EmptyState(height: widget.height);
    }

    final geom = _buildGeometry();

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = constraints.maxWidth;
          final n = data.length;
          final plotW = w - _mLeft - _mRight;
          final bandW = plotW / n;

          return Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => _updateTouch(d.localPosition.dx, bandW, n),
                  onTapUp: (_) => _clearTouch(),
                  onTapCancel: _clearTouch,
                  onHorizontalDragStart: (d) =>
                      _updateTouch(d.localPosition.dx, bandW, n),
                  onHorizontalDragUpdate: (d) =>
                      _updateTouch(d.localPosition.dx, bandW, n),
                  onHorizontalDragEnd: (_) => _clearTouch(),
                  child: CustomPaint(
                    size: Size(w, widget.height),
                    painter: _NutritionChartPainter(
                      data: data,
                      geom: geom,
                      touchedIndex: _touchedIndex,
                      targetWeight: widget.targetWeight,
                    ),
                  ),
                ),
              ),
              // ツールチップ オーバーレイ
              if (_touchedIndex != null &&
                  _touchedIndex! >= 0 &&
                  _touchedIndex! < data.length)
                ..._buildTooltipOverlay(w, bandW),
            ],
          );
        },
      ),
    );
  }

  void _updateTouch(double dx, double bandW, int n) {
    final idx = ((dx - _mLeft) / bandW).floor().clamp(0, n - 1);
    if (idx != _touchedIndex) {
      setState(() => _touchedIndex = idx);
    }
  }

  void _clearTouch() {
    if (_touchedIndex != null) {
      setState(() => _touchedIndex = null);
    }
  }

  /// スケール・目盛・体重範囲をまとめたジオメトリを構築する。
  _ChartGeometry _buildGeometry() {
    final data = widget.data;

    // kcal 軸の最大値（500 単位切り上げ、最低 1000）
    final maxKcal = _computeMaxKcal();

    // kg 軸の範囲（記録体重＋目標体重を含めて整数化）
    final weights =
        data.map((d) => d.weight).whereType<double>().toList(growable: true);
    final hasWeight = weights.isNotEmpty;
    if (hasWeight && widget.targetWeight != null) {
      weights.add(widget.targetWeight!);
    }
    final rawMin = hasWeight ? weights.reduce((a, b) => a < b ? a : b) : 0.0;
    final rawMax = hasWeight ? weights.reduce((a, b) => a > b ? a : b) : 1.0;
    final minWeight = hasWeight ? (rawMin - 1).floorToDouble() : 0.0;
    final maxWeight = hasWeight ? (rawMax + 1).ceilToDouble() : 1.0;

    return _ChartGeometry(
      maxKcal: maxKcal,
      minWeight: minWeight,
      maxWeight: maxWeight,
      hasWeight: hasWeight,
      bottomInterval: _bottomInterval(),
    );
  }

  double _computeMaxKcal() {
    var max = 0.0;
    for (final d in widget.data) {
      final pfc = d.protein * _kcalPerGProtein +
          d.fat * _kcalPerGFat +
          d.carbs * _kcalPerGCarbs;
      final v = pfc > d.calories ? pfc : d.calories;
      if (v > max) max = v;
    }
    if (max <= 0) return 1000;
    final rounded = ((max / 500).ceil()) * 500;
    final r = rounded.toDouble();
    return r < 1000 ? 1000 : r;
  }

  int _bottomInterval() {
    final n = widget.data.length;
    if (n <= 7) return 1;
    if (n <= 14) return 2;
    if (n <= 31) return 5;
    if (n <= 60) return 10;
    return 14;
  }

  /// タッチ中の日のリッチなダークツールチップを構築（縦線は Painter が描く）。
  List<Widget> _buildTooltipOverlay(double w, double bandW) {
    final data = widget.data;
    final index = _touchedIndex!;
    final d = data[index];

    final xCenter = _mLeft + bandW * (index + 0.5);

    // ツールチップ幅は固定（チャートが極端に狭い場合のみ縮める）
    final tipW = (w - 8) < 168.0 ? (w - 8) : 168.0;

    // 既定は点の右側。右にはみ出すなら左側へフリップ。最終的に画面内へクランプ。
    var left = xCenter + 10;
    if (left + tipW > w - 2) {
      left = xCenter - 10 - tipW;
    }
    final maxLeft = (w - tipW - 2).clamp(0.0, double.infinity);
    left = left.clamp(2.0, maxLeft);

    return [
      Positioned(
        top: 2,
        left: left,
        child: IgnorePointer(
          child: SizedBox(
            width: tipW,
            child: _TooltipCard(stat: d),
          ),
        ),
      ),
    ];
  }
}

/// チャートのスケール定義（幅 W は Painter 側で受け取る）。
class _ChartGeometry {
  final double maxKcal;
  final double minWeight;
  final double maxWeight;
  final bool hasWeight;
  final int bottomInterval;

  const _ChartGeometry({
    required this.maxKcal,
    required this.minWeight,
    required this.maxWeight,
    required this.hasWeight,
    required this.bottomInterval,
  });
}

/// 全要素を 1 つの座標系で描く CustomPainter。
class _NutritionChartPainter extends CustomPainter {
  final List<DailyNutritionStat> data;
  final _ChartGeometry geom;
  final int? touchedIndex;
  final double? targetWeight;

  // 余白（State 側と一致させる）
  static const double mLeft = _NutritionTrendChartState._mLeft;
  static const double mRight = _NutritionTrendChartState._mRight;
  static const double mTop = _NutritionTrendChartState._mTop;
  static const double mBottom = _NutritionTrendChartState._mBottom;

  _NutritionChartPainter({
    required this.data,
    required this.geom,
    required this.touchedIndex,
    required this.targetWeight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final n = data.length;
    final plotW = w - mLeft - mRight;
    final plotH = h - mTop - mBottom;
    if (plotW <= 0 || plotH <= 0 || n == 0) return;

    final bandW = plotW / n;
    final top = mTop;
    final bottom = mTop + plotH; // = h - mBottom

    double xCenter(int i) => mLeft + bandW * (i + 0.5);

    // kcal スケール: [0, maxKcal] -> [bottom, top]
    double yK(double v) {
      final t = (v / geom.maxKcal).clamp(0.0, 1.0);
      return bottom - t * plotH;
    }

    // kg スケール: [minWeight, maxWeight] -> [bottom, top]
    final wSpan = (geom.maxWeight - geom.minWeight);
    double yW(double v) {
      if (wSpan <= 0) return bottom;
      final t = ((v - geom.minWeight) / wSpan).clamp(0.0, 1.0);
      return bottom - t * plotH;
    }

    // ---- 1. 横グリッド線（kcal 目盛: 0, 1/4, 1/2, 3/4, max）----
    _paintGrid(canvas, w, yK);

    // ---- 2. 淡い PFC 積み上げ棒 ----
    _paintBars(canvas, xCenter, yK, bandW);

    // 体重系（記録がある場合のみ）
    if (geom.hasWeight) {
      // ---- 3. 体重エリア塗り ----
      _paintWeightArea(canvas, xCenter, yW, bottom);
      // ---- 4. 目標ライン ----
      if (targetWeight != null) {
        _paintGoalLine(canvas, w, yW(targetWeight!));
      }
      // ---- 5. 体重折れ線 ----
      _paintWeightLine(canvas, xCenter, yW);
      // ---- 6. ドット ----
      _paintDots(canvas, xCenter, yW);
    }

    // ---- 7. アクティブ縦線 ----
    if (touchedIndex != null &&
        touchedIndex! >= 0 &&
        touchedIndex! < n &&
        data[touchedIndex!].weight != null) {
      final cx = xCenter(touchedIndex!);
      final paint = Paint()
        ..color = AppColors.slate300
        ..strokeWidth = 1;
      canvas.drawLine(Offset(cx, top), Offset(cx, bottom), paint);
    }

    // ---- 8. 軸テキスト ----
    _paintKcalAxis(canvas, yK);
    if (geom.hasWeight) {
      _paintWeightAxis(canvas, w, yW);
    }
    _paintDateAxis(canvas, xCenter, w, bandW, h);
  }

  void _paintGrid(Canvas canvas, double w, double Function(double) yK) {
    final paint = Paint()
      ..color = AppColors.slate200
      ..strokeWidth = 1;
    final left = mLeft;
    final right = w - mRight;
    for (var i = 0; i <= 4; i++) {
      final v = geom.maxKcal * i / 4;
      final y = yK(v);
      _drawDashedLine(
        canvas,
        Offset(left, y),
        Offset(right, y),
        paint,
        dashWidth: 3,
        dashGap: 3,
      );
    }
  }

  void _paintBars(
    Canvas canvas,
    double Function(int) xCenter,
    double Function(double) yK,
    double bandW,
  ) {
    final barW = (bandW * 0.62).clamp(3.0, 16.0);
    final half = barW / 2;

    final pPaint = Paint()
      ..color = AppColors.pfcProtein.withValues(alpha: 0.55);
    final fPaint = Paint()..color = AppColors.pfcFat.withValues(alpha: 0.55);
    final cPaint = Paint()..color = AppColors.pfcCarbs.withValues(alpha: 0.55);

    final placeholderPaint = Paint()
      ..color = AppColors.slate300
      ..strokeWidth = 1;

    for (var i = 0; i < data.length; i++) {
      final d = data[i];
      final cx = xCenter(i);

      if (!d.hasAnyRecord) {
        // 記録なし日: yK(160) 付近に薄い破線プレースホルダ
        final y = yK(160);
        _drawDashedLine(
          canvas,
          Offset(cx - half, y),
          Offset(cx + half, y),
          placeholderPaint,
          dashWidth: 2,
          dashGap: 2,
        );
        continue;
      }

      final pKcal = d.protein * _NutritionTrendChartState._kcalPerGProtein;
      final fKcal = d.fat * _NutritionTrendChartState._kcalPerGFat;
      final cKcal = d.carbs * _NutritionTrendChartState._kcalPerGCarbs;
      if (pKcal + fKcal + cKcal <= 0) continue;

      var acc = 0.0;
      // protein
      _drawBarSegment(canvas, cx, half, yK(acc), yK(acc + pKcal), pPaint,
          roundTop: false);
      acc += pKcal;
      // fat
      _drawBarSegment(canvas, cx, half, yK(acc), yK(acc + fKcal), fPaint,
          roundTop: false);
      acc += fKcal;
      // carbs（最上段のみ上端を軽く角丸）
      _drawBarSegment(canvas, cx, half, yK(acc), yK(acc + cKcal), cPaint,
          roundTop: true);
    }
  }

  void _drawBarSegment(
    Canvas canvas,
    double cx,
    double half,
    double yBottom,
    double yTop,
    Paint paint, {
    required bool roundTop,
  }) {
    final rect = Rect.fromLTRB(cx - half, yTop, cx + half, yBottom);
    if (rect.height <= 0) return;
    if (roundTop) {
      final rrect = RRect.fromRectAndCorners(
        rect,
        topLeft: const Radius.circular(2),
        topRight: const Radius.circular(2),
      );
      canvas.drawRRect(rrect, paint);
    } else {
      canvas.drawRect(rect, paint);
    }
  }

  void _paintWeightArea(
    Canvas canvas,
    double Function(int) xCenter,
    double Function(double) yW,
    double bottom,
  ) {
    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final w = data[i].weight;
      if (w != null) pts.add(Offset(xCenter(i), yW(w)));
    }
    if (pts.isEmpty) return;

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path
      ..lineTo(pts.last.dx, bottom)
      ..lineTo(pts.first.dx, bottom)
      ..close();

    final topY = pts.map((p) => p.dy).reduce((a, b) => a < b ? a : b);
    final gradient = ui.Gradient.linear(
      Offset(0, topY),
      Offset(0, bottom),
      [
        AppColors.primary600.withValues(alpha: 0.16),
        AppColors.primary600.withValues(alpha: 0.02),
      ],
    );
    final paint = Paint()..shader = gradient;
    canvas.drawPath(path, paint);
  }

  void _paintGoalLine(Canvas canvas, double w, double y) {
    final paint = Paint()
      ..color = AppColors.success
      ..strokeWidth = 1.5;
    _drawDashedLine(
      canvas,
      Offset(mLeft, y),
      Offset(w - mRight, y),
      paint,
      dashWidth: 5,
      dashGap: 4,
    );

    // 右端ラベル「目標 XX.X」
    final tp = TextPainter(
      text: TextSpan(
        text: '目標 ${targetWeight!.toStringAsFixed(1)}',
        style: const TextStyle(
          color: AppColors.success,
          fontSize: 9,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
      textAlign: TextAlign.right,
    )..layout();
    tp.paint(canvas, Offset(w - mRight - tp.width, y - tp.height - 1));
  }

  void _paintWeightLine(
    Canvas canvas,
    double Function(int) xCenter,
    double Function(double) yW,
  ) {
    final pts = <Offset>[];
    for (var i = 0; i < data.length; i++) {
      final w = data[i].weight;
      if (w != null) pts.add(Offset(xCenter(i), yW(w)));
    }
    if (pts.length < 2) {
      // 1 点でも点は別途打つので line は描かない
      return;
    }
    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    final paint = Paint()
      ..color = AppColors.primary600
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeJoin = StrokeJoin.round
      ..strokeCap = StrokeCap.round;
    canvas.drawPath(path, paint);
  }

  void _paintDots(
    Canvas canvas,
    double Function(int) xCenter,
    double Function(double) yW,
  ) {
    final fillPaint = Paint()..color = Colors.white;
    for (var i = 0; i < data.length; i++) {
      final w = data[i].weight;
      if (w == null) continue;
      final c = Offset(xCenter(i), yW(w));
      final active = touchedIndex == i;
      final r = active ? 5.0 : 3.5;
      final strokeW = active ? 3.0 : 2.5;
      final ringPaint = Paint()
        ..color = AppColors.primary600
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeW;
      canvas.drawCircle(c, r, fillPaint);
      canvas.drawCircle(c, r, ringPaint);
    }
  }

  void _paintKcalAxis(Canvas canvas, double Function(double) yK) {
    for (var i = 0; i <= 4; i++) {
      final v = geom.maxKcal * i / 4;
      if (v == 0) continue; // 0 は描画しない（コーナー衝突回避）
      final y = yK(v);
      final tp = TextPainter(
        text: TextSpan(
          text: '${v.toInt()}',
          style: const TextStyle(color: AppColors.slate500, fontSize: 9),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.right,
      )..layout();
      // 左マージン内に右寄せ
      tp.paint(canvas, Offset(mLeft - 6 - tp.width, y - tp.height / 2));
    }
  }

  void _paintWeightAxis(Canvas canvas, double w, double Function(double) yW) {
    final wRange = geom.maxWeight - geom.minWeight;
    final interval = wRange <= 5 ? 1 : (wRange / 4).ceil();
    for (var v = geom.minWeight; v <= geom.maxWeight + 0.01; v += interval) {
      // 最小値ラベルは描画しない
      if (v <= geom.minWeight + 0.01) continue;
      final y = yW(v);
      final tp = TextPainter(
        text: TextSpan(
          text: v.toInt().toString(),
          style: const TextStyle(
            color: AppColors.primary600,
            fontSize: 9,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: ui.TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(w - mRight + 6, y - tp.height / 2));
    }
  }

  void _paintDateAxis(
    Canvas canvas,
    double Function(int) xCenter,
    double w,
    double bandW,
    double h,
  ) {
    final interval = geom.bottomInterval;
    final left = mLeft;
    final right = w - mRight;
    final yLabel = h - mBottom + 6;

    for (var i = 0; i < data.length; i++) {
      if (i % interval != 0) continue;
      final tp = TextPainter(
        text: TextSpan(
          text: DateFormat('M/d').format(data[i].date),
          style: const TextStyle(color: AppColors.slate500, fontSize: 9),
        ),
        textDirection: ui.TextDirection.ltr,
        textAlign: TextAlign.center,
      )..layout();

      // 中央寄せ。両端はプロット内にクランプしてはみ出し防止。
      var dx = xCenter(i) - tp.width / 2;
      if (dx < left) dx = left;
      if (dx + tp.width > right) dx = right - tp.width;
      tp.paint(canvas, Offset(dx, yLabel));
    }
  }

  /// 水平/任意方向の破線を描く。
  void _drawDashedLine(
    Canvas canvas,
    Offset start,
    Offset end,
    Paint paint, {
    required double dashWidth,
    required double dashGap,
  }) {
    final total = (end - start).distance;
    if (total <= 0) return;
    final dir = (end - start) / total;
    var drawn = 0.0;
    while (drawn < total) {
      final segLen = (drawn + dashWidth) > total ? total - drawn : dashWidth;
      final a = start + dir * drawn;
      final b = start + dir * (drawn + segLen);
      canvas.drawLine(a, b, paint);
      drawn += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(covariant _NutritionChartPainter old) {
    return old.data != data ||
        old.touchedIndex != touchedIndex ||
        old.targetWeight != targetWeight ||
        old.geom.maxKcal != geom.maxKcal ||
        old.geom.minWeight != geom.minWeight ||
        old.geom.maxWeight != geom.maxWeight;
  }
}

class _EmptyState extends StatelessWidget {
  final double height;
  const _EmptyState({required this.height});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              LucideIcons.barChart2,
              size: 40,
              color: AppColors.slate300,
            ),
            SizedBox(height: 12),
            Text(
              '記録がまだありません',
              style: TextStyle(
                color: AppColors.slate500,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
            SizedBox(height: 4),
            Text(
              '体重・食事を記録するとグラフが表示されます',
              style: TextStyle(
                color: AppColors.slate400,
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// タッチ中の日のデータを表示するダーク角丸カード型ツールチップ。
///
/// 構成: ヘッダー（日付+曜日）→ 体重行 → 摂取行 → 区切り → PFCチップ。
/// 記録がない日は「記録なし」のみ表示する。
class _TooltipCard extends StatelessWidget {
  final DailyNutritionStat stat;
  const _TooltipCard({required this.stat});

  // 曜日（DateTime.weekday は 月=1..日=7）
  static const List<String> _weekdayJa = ['月', '火', '水', '木', '金', '土', '日'];

  @override
  Widget build(BuildContext context) {
    final d = stat;
    final weekday = _weekdayJa[d.date.weekday - 1];
    final header = '${DateFormat('M/d').format(d.date)} ($weekday)';

    return Container(
      constraints: const BoxConstraints(minWidth: 120),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.slate900,
        borderRadius: BorderRadius.circular(7),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.25),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // ヘッダー
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              header,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                height: 1.1,
              ),
            ),
          ),
          if (!d.hasAnyRecord)
            const Text(
              '記録なし',
              style: TextStyle(
                color: AppColors.slate400,
                fontSize: 10.5,
                height: 1.2,
              ),
            )
          else ...[
            // 体重行
            _kvRow(
              '体重',
              d.weight != null ? '${d.weight!.toStringAsFixed(1)} kg' : '—',
            ),
            // 摂取行
            _kvRow('摂取', '${d.calories.toStringAsFixed(0)} kcal'),
            // 区切り線
            Container(
              margin: const EdgeInsets.only(top: 5),
              padding: const EdgeInsets.only(top: 5),
              height: 1,
              color: Colors.white.withValues(alpha: 0.14),
            ),
            const SizedBox(height: 5),
            // PFC チップ行
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _pfcChip(AppColors.pfcProtein, 'P', d.protein),
                const SizedBox(width: 8),
                _pfcChip(AppColors.pfcFat, 'F', d.fat),
                const SizedBox(width: 8),
                _pfcChip(AppColors.pfcCarbs, 'C', d.carbs),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// 左ラベル / 右値の両端寄せ行
  Widget _kvRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 1),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.slate300,
              fontSize: 10.5,
              height: 1.2,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 10.5,
              fontWeight: FontWeight.bold,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  /// 色付き四角 + ' P 130g' のチップ
  Widget _pfcChip(Color color, String label, num grams) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Text(
          ' $label ${grams.toStringAsFixed(0)}g',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Previews
// ---------------------------------------------------------------------------

List<DailyNutritionStat> _samplePastWeek() {
  final today = DateTime.now();
  final base = DateTime(today.year, today.month, today.day);
  return [
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 6)),
      weight: 65.4,
      calories: 1850,
      protein: 110,
      fat: 55,
      carbs: 200,
    ),
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 5)),
      weight: 65.2,
      calories: 1920,
      protein: 120,
      fat: 60,
      carbs: 210,
    ),
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 4)),
      weight: 65.0,
      calories: 1780,
      protein: 105,
      fat: 50,
      carbs: 195,
    ),
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 3)),
      calories: 0,
    ),
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 2)),
      weight: 64.7,
      calories: 2100,
      protein: 130,
      fat: 65,
      carbs: 230,
    ),
    DailyNutritionStat(
      date: base.subtract(const Duration(days: 1)),
      weight: 64.5,
      calories: 1950,
      protein: 118,
      fat: 58,
      carbs: 215,
    ),
    DailyNutritionStat(
      date: base,
      weight: 64.3,
      calories: 1880,
      protein: 112,
      fat: 56,
      carbs: 205,
    ),
  ];
}

@Preview(name: 'NutritionTrendChart - Week')
Widget previewNutritionTrendChartWeek() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 16, 16, 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.slate200),
            ),
            child: NutritionTrendChart(
                data: _samplePastWeek(), targetWeight: 64.0),
          ),
        ),
      ),
    ),
  );
}

@Preview(name: 'NutritionTrendChart - Empty')
Widget previewNutritionTrendChartEmpty() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.slate200),
            ),
            child: const NutritionTrendChart(data: []),
          ),
        ),
      ),
    ),
  );
}
