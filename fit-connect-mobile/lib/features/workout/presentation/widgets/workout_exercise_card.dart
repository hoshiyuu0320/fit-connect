import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widget_previews.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_spacing.dart';
import 'package:fit_connect_mobile/core/theme/app_text_styles.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_format.dart';
import 'package:fit_connect_mobile/shared/utils/trainer_name.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc_previews.dart';

/// 今日のプランの種目カード（正本 `plan-screens.js` の `ExerciseCard`）。
///
/// - 閉じているとき: 完了マーク（26）・種目名・「3セット × 10回 · 12 kg」・chevron-down
/// - 開くと（chevron は 180 度）: セットごとの行（セット名・重量欄・回数欄・セット完了）と、
///   トレーナーのメモ（あれば）
/// - 重量・回数の入力は、欄を離れたとき（フォーカスが外れたとき）と、セット完了を切り替えたときに
///   [onSetsUpdated] で保存する。種目の完了は、全セットが完了したときに親（プロバイダー）が決める
/// - 文字を拡大すると、セットの行は欄を折り返して縦に積み直す（縮めない）
class WorkoutExerciseCard extends StatefulWidget {
  const WorkoutExerciseCard({
    super.key,
    required this.exerciseName,
    required this.targetSets,
    required this.targetReps,
    this.targetWeight,
    this.memo,
    required this.isCompleted,
    this.actualSets,
    required this.onSetsUpdated,
    this.trainerName,
    this.initiallyExpanded = false,
  });

  final String exerciseName;
  final int targetSets;
  final int targetReps;
  final double? targetWeight;
  final String? memo;
  final bool isCompleted;
  final List<ActualSet>? actualSets;
  final void Function(List<ActualSet>) onSetsUpdated;

  /// トレーナーの名前（メモの見出し「{名前}トレーナーのメモ」に使う。null なら「トレーナーのメモ」）
  final String? trainerName;

  /// 最初から開いておくか（画面側で、いま取り組む種目だけ開く）
  final bool initiallyExpanded;

  @override
  State<WorkoutExerciseCard> createState() => _WorkoutExerciseCardState();
}

class _WorkoutExerciseCardState extends State<WorkoutExerciseCard> {
  late bool _isExpanded;
  late List<ActualSet> _localSets;
  late List<TextEditingController> _repsControllers;
  late List<TextEditingController> _weightControllers;
  late List<FocusNode> _repsFocusNodes;
  late List<FocusNode> _weightFocusNodes;

  /// カードの余白（正本: 16 × 20。トークンの標準余白 20 と異なるのでここだけの定数）
  static const EdgeInsets _cardPadding =
      EdgeInsets.symmetric(horizontal: 20, vertical: 16);

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.initiallyExpanded;
    _initLocalSets();
    _initControllers();
  }

  void _initLocalSets() {
    if (widget.actualSets != null && widget.actualSets!.isNotEmpty) {
      _localSets = List.from(widget.actualSets!);
    } else {
      _localSets = List.generate(
        widget.targetSets,
        (i) => ActualSet(
          setNumber: i + 1,
          reps: widget.targetReps,
          weight: widget.targetWeight ?? 0,
          done: false,
        ),
      );
    }
  }

  void _initControllers() {
    _repsControllers = _localSets.map((s) {
      final controller = TextEditingController(
        text: s.reps == 0 ? '' : s.reps.toString(),
      );
      return controller;
    }).toList();

    _weightControllers = _localSets.map((s) {
      final controller = TextEditingController(
        text: s.weight == 0 ? '' : formatWorkoutWeight(s.weight),
      );
      return controller;
    }).toList();

    _repsFocusNodes = List.generate(_localSets.length, (_) {
      final node = FocusNode();
      return node;
    });

    _weightFocusNodes = List.generate(_localSets.length, (_) {
      final node = FocusNode();
      return node;
    });

    for (int i = 0; i < _localSets.length; i++) {
      final index = i;
      _repsFocusNodes[index].addListener(() {
        if (!_repsFocusNodes[index].hasFocus) {
          widget.onSetsUpdated(_localSets);
        }
      });
      _weightFocusNodes[index].addListener(() {
        if (!_weightFocusNodes[index].hasFocus) {
          widget.onSetsUpdated(_localSets);
        }
      });
    }
  }

  void _disposeControllers() {
    for (final c in _repsControllers) {
      c.dispose();
    }
    for (final c in _weightControllers) {
      c.dispose();
    }
    for (final n in _repsFocusNodes) {
      n.dispose();
    }
    for (final n in _weightFocusNodes) {
      n.dispose();
    }
  }

  @override
  void didUpdateWidget(WorkoutExerciseCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final newSets = widget.actualSets;
    final oldSets = oldWidget.actualSets;
    if (newSets != oldSets) {
      _disposeControllers();
      _initLocalSets();
      _initControllers();
    }
  }

  @override
  void dispose() {
    _disposeControllers();
    super.dispose();
  }

  /// 「3セット × 10回 · 12 kg」（重量の目標が無いときは回数まで）
  String _buildDetailText() {
    final base = '${widget.targetSets}セット × ${widget.targetReps}回';
    if (widget.targetWeight != null) {
      return '$base · ${formatWorkoutWeight(widget.targetWeight!)} kg';
    }
    return base;
  }

  void _toggleExpanded() {
    setState(() {
      _isExpanded = !_isExpanded;
    });
  }

  void _onRepsChanged(int index, String value) {
    final parsed = int.tryParse(value) ?? _localSets[index].reps;
    setState(() {
      _localSets[index] = _localSets[index].copyWith(reps: parsed);
    });
  }

  void _onWeightChanged(int index, String value) {
    final parsed = double.tryParse(value) ?? _localSets[index].weight;
    setState(() {
      _localSets[index] = _localSets[index].copyWith(weight: parsed);
    });
  }

  void _onDoneToggled(int index) {
    setState(() {
      _localSets[index] =
          _localSets[index].copyWith(done: !_localSets[index].done);
    });
    widget.onSetsUpdated(_localSets);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final reduceMotion = AppMotion.reduceOf(context);
    final detail = _buildDetailText();

    return FcCard(
      paddingOverride: _cardPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ヘッダー（押すと開閉）
          Semantics(
            expanded: _isExpanded,
            child: FcPressable(
              onTap: _toggleExpanded,
              minSize: const Size(0, AppSizes.minTouch),
              semanticLabel:
                  '${widget.exerciseName}、$detail、${widget.isCompleted ? '完了' : '未完了'}',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  FcDoneMark(done: widget.isCompleted, size: 26),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.exerciseName,
                          style: AppTextStyles.exerciseName(context),
                        ),
                        Padding(
                          // 正本の meta は 1px 空ける
                          padding: const EdgeInsets.only(top: 1),
                          child: Text(
                            detail,
                            style: AppTextStyles.supplement(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  AnimatedRotation(
                    turns: _isExpanded ? 0.5 : 0,
                    duration: reduceMotion ? Duration.zero : AppMotion.select,
                    curve: Curves.easeInOut,
                    child: Icon(
                      LucideIcons.chevronDown,
                      size: 18,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // セットの行・トレーナーのメモ
          AnimatedSize(
            duration: reduceMotion ? Duration.zero : AppMotion.select,
            curve: Curves.easeInOut,
            alignment: Alignment.topCenter,
            child: _isExpanded
                ? Padding(
                    padding: const EdgeInsets.only(top: AppSpacing.md),
                    child: _buildExpandedBody(context),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _buildExpandedBody(BuildContext context) {
    final colors = AppColors.of(context);
    final memo = widget.memo;
    final hasMemo = memo != null && memo.isNotEmpty;
    final memoStyle = AppTextStyles.supplement(context)
        .copyWith(color: colors.textPrimary, height: 1.6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < _localSets.length; i++) ...[
          if (i > 0) const FcSeparator(),
          _SetRow(
            set: _localSets[i],
            repsController: _repsControllers[i],
            weightController: _weightControllers[i],
            repsFocusNode: _repsFocusNodes[i],
            weightFocusNode: _weightFocusNodes[i],
            onRepsChanged: (v) => _onRepsChanged(i, v),
            onWeightChanged: (v) => _onWeightChanged(i, v),
            onDoneToggled: () => _onDoneToggled(i),
          ),
        ],
        if (hasMemo)
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: FcInfoBox(
              // 正本のメモは 11 × 14
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${trainerDisplayName(widget.trainerName)}のメモ',
                    style: memoStyle.copyWith(fontWeight: FontWeight.w500),
                  ),
                  Text(memo, style: memoStyle),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// 1 セット分の行: 「セット1」＋ 重量欄 ＋ 回数欄 ＋ セット完了。
class _SetRow extends StatelessWidget {
  const _SetRow({
    required this.set,
    required this.repsController,
    required this.weightController,
    required this.repsFocusNode,
    required this.weightFocusNode,
    required this.onRepsChanged,
    required this.onWeightChanged,
    required this.onDoneToggled,
  });

  final ActualSet set;
  final TextEditingController repsController;
  final TextEditingController weightController;
  final FocusNode repsFocusNode;
  final FocusNode weightFocusNode;
  final ValueChanged<String> onRepsChanged;
  final ValueChanged<String> onWeightChanged;
  final VoidCallback onDoneToggled;

  /// 「セット1」の最小幅（正本 52）
  static const double _labelMinWidth = 52;

  /// 行の上下余白。正本は 9。欄の押せる範囲を 44 にするために欄の上下へ 2 ずつ足すので、その分を引く
  static const double _verticalPadding = 7;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: _verticalPadding),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minWidth: _labelMinWidth),
            child: Text(
              'セット${set.setNumber}',
              softWrap: false,
              style: AppTextStyles.supplement(context),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          // 欄は 2 つ並べる。文字を大きくして収まらなければ、2 つ目が次の行へ折り返す
          Expanded(
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.xs,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                _SetField(
                  controller: weightController,
                  focusNode: weightFocusNode,
                  unit: 'kg',
                  semanticLabel: 'セット${set.setNumber} 重量（kg）',
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  ],
                  onChanged: onWeightChanged,
                ),
                _SetField(
                  controller: repsController,
                  focusNode: repsFocusNode,
                  unit: '回',
                  semanticLabel: 'セット${set.setNumber} 回数',
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  onChanged: onRepsChanged,
                ),
              ],
            ),
          ),
          // 見た目は 28 の丸。押せる範囲は 44×44（右端に寄せて本文の右端と揃える）
          FcPressable(
            onTap: onDoneToggled,
            // 何セット目かが分かるよう番号を含める（例:「セット1 完了」）
            semanticLabel: 'セット${set.setNumber} ${set.done ? '完了' : '未完了'}',
            child: SizedBox(
              width: AppSizes.minTouch,
              height: AppSizes.minTouch,
              child: Align(
                alignment: Alignment.centerRight,
                child: FcDoneMark(done: set.done, size: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 重量・回数の小さな数値入力（正本 `SetField`）。
///
/// 最小高さ 40・surface の面・1px の separator の枠・角丸 12・文字 16・単位 13（textSecondary）。
/// 空のときは「—」。編集中は枠が accent になる（どこを入力しているか分かるように。正本にはない）。
/// 入力欄の外側の上下 2 も押すと入力欄に移るので、押せる範囲は 44。
class _SetField extends StatelessWidget {
  const _SetField({
    required this.controller,
    required this.focusNode,
    required this.unit,
    required this.semanticLabel,
    required this.keyboardType,
    required this.inputFormatters,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String unit;
  final String semanticLabel;
  final TextInputType keyboardType;
  final List<TextInputFormatter> inputFormatters;
  final ValueChanged<String> onChanged;

  /// 正本の最小幅は 74。小数（22.5）や 3 桁が欄の中で切れないよう、単位の分を含めて 80 にした
  static const double _baseWidth = 80;

  /// 欄の最小高さ（正本 40）
  static const double _minHeight = 40;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    // 文字を拡大したら欄も同じ割合で広げる（数字と単位が切れないように）
    final width = MediaQuery.textScalerOf(context).scale(_baseWidth);
    final valueStyle = AppTextStyles.bodyNumber(context);

    return AnimatedBuilder(
      animation: focusNode,
      builder: (context, _) {
        final focused = focusNode.hasFocus;
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: focusNode.requestFocus,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Container(
              width: width,
              constraints: const BoxConstraints(minHeight: _minHeight),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(AppRadius.input),
                border: Border.all(
                  color: focused ? colors.accent : colors.separator,
                  width: focused ? 1.5 : 1,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      label: semanticLabel,
                      textField: true,
                      child: TextField(
                        controller: controller,
                        focusNode: focusNode,
                        keyboardType: keyboardType,
                        inputFormatters: inputFormatters,
                        style: valueStyle,
                        cursorColor: colors.accent,
                        decoration: InputDecoration(
                          isCollapsed: true,
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                          hintText: '—',
                          hintStyle: valueStyle.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        onChanged: onChanged,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  ExcludeSemantics(
                    child: Text(
                      unit,
                      softWrap: false,
                      style: AppTextStyles.numUnit(context),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ============================================
// Previews
// ============================================

const _sampleSetsPartial = [
  ActualSet(setNumber: 1, reps: 12, weight: 30, done: true),
  ActualSet(setNumber: 2, reps: 12, weight: 30, done: true),
  ActualSet(setNumber: 3, reps: 0, weight: 30, done: false),
];

const _sampleSetsAll = [
  ActualSet(setNumber: 1, reps: 12, weight: 25, done: true),
  ActualSet(setNumber: 2, reps: 12, weight: 25, done: true),
  ActualSet(setNumber: 3, reps: 12, weight: 25, done: true),
];

class _PreviewCard extends StatefulWidget {
  const _PreviewCard({
    required this.name,
    required this.sets,
    required this.completed,
    required this.expanded,
    this.memo,
    this.targetWeight,
  });

  final String name;
  final List<ActualSet>? sets;
  final bool completed;
  final bool expanded;
  final String? memo;
  final double? targetWeight;

  @override
  State<_PreviewCard> createState() => _PreviewCardState();
}

class _PreviewCardState extends State<_PreviewCard> {
  late List<ActualSet>? _sets = widget.sets;

  @override
  Widget build(BuildContext context) {
    return WorkoutExerciseCard(
      exerciseName: widget.name,
      targetSets: 3,
      targetReps: 12,
      targetWeight: widget.targetWeight,
      memo: widget.memo,
      isCompleted: widget.completed,
      actualSets: _sets,
      trainerName: '田中',
      initiallyExpanded: widget.expanded,
      onSetsUpdated: (sets) => setState(() => _sets = sets),
    );
  }
}

Widget _previewExerciseCards(Brightness brightness, {double textScale = 1.0}) {
  return FcPreviewApp(
    brightness: brightness,
    textScale: textScale,
    home: Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.pageHorizontal),
          children: const [
            _PreviewCard(
              name: 'ダンベルプレス',
              sets: _sampleSetsAll,
              completed: true,
              expanded: false,
              targetWeight: 12,
            ),
            SizedBox(height: AppSpacing.cardGap),
            _PreviewCard(
              name: 'ラットプルダウン',
              sets: _sampleSetsPartial,
              completed: false,
              expanded: true,
              memo: '肘を後ろに引く意識で、反動を使わずに。',
              targetWeight: 30,
            ),
            SizedBox(height: AppSpacing.cardGap),
            _PreviewCard(
              name: 'シーテッドロー',
              sets: null,
              completed: false,
              expanded: false,
              targetWeight: 25,
            ),
          ],
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutExerciseCard - 開いている・途中')
Widget previewWorkoutExerciseCardExpandedPartial() =>
    _previewExerciseCards(Brightness.light);

@Preview(name: 'WorkoutExerciseCard - ダーク')
Widget previewWorkoutExerciseCardDark() =>
    _previewExerciseCards(Brightness.dark);

@Preview(name: 'WorkoutExerciseCard - 文字特大 (1.35)')
Widget previewWorkoutExerciseCardLargeText() =>
    _previewExerciseCards(Brightness.light, textScale: 1.35);

@Preview(name: 'WorkoutExerciseCard - 全セット完了（閉じている）')
Widget previewWorkoutExerciseCardAllCompleted() {
  return FcPreviewApp(
    brightness: Brightness.light,
    home: const Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(AppSpacing.pageHorizontal),
          child: _PreviewCard(
            name: 'ベンチプレス',
            sets: _sampleSetsAll,
            completed: true,
            expanded: false,
            targetWeight: 40,
          ),
        ),
      ),
    ),
  );
}
