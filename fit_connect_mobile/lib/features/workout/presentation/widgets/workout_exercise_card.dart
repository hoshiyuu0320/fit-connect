import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:fit_connect_mobile/core/theme/app_colors.dart';
import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/workout/models/actual_set_model.dart';
import 'package:lucide_icons/lucide_icons.dart';

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
  });

  final String exerciseName;
  final int targetSets;
  final int targetReps;
  final double? targetWeight;
  final String? memo;
  final bool isCompleted;
  final List<ActualSet>? actualSets;
  final void Function(List<ActualSet>) onSetsUpdated;

  @override
  State<WorkoutExerciseCard> createState() => _WorkoutExerciseCardState();
}

class _WorkoutExerciseCardState extends State<WorkoutExerciseCard> {
  bool _isExpanded = false;
  late List<ActualSet> _localSets;
  late List<TextEditingController> _repsControllers;
  late List<TextEditingController> _weightControllers;
  late List<FocusNode> _repsFocusNodes;
  late List<FocusNode> _weightFocusNodes;

  @override
  void initState() {
    super.initState();
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
        text: s.weight == 0 ? '' : _formatWeight(s.weight),
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

  String _formatWeight(double weight) {
    if (weight == weight.truncateToDouble()) {
      return weight.toInt().toString();
    }
    return weight.toString();
  }

  String _buildSetsRepsText() {
    final base = '${widget.targetSets} セット × ${widget.targetReps} 回';
    if (widget.targetWeight != null) {
      return '$base / ${_formatWeight(widget.targetWeight!)}kg';
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

  void _onDoneChanged(int index, bool? value) {
    setState(() {
      _localSets[index] = _localSets[index].copyWith(done: value ?? false);
    });
    widget.onSetsUpdated(_localSets);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final card = Card(
      elevation: 1,
      color: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header row
          InkWell(
            onTap: _toggleExpanded,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Left: completion indicator
                  Icon(
                    widget.isCompleted
                        ? LucideIcons.checkCircle2
                        : LucideIcons.circle,
                    size: 24,
                    color: widget.isCompleted
                        ? AppColors.emerald500
                        : colors.textHint,
                  ),
                  const SizedBox(width: 8),

                  // Center: exercise info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.exerciseName,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                            decoration: widget.isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _buildSetsRepsText(),
                          style: TextStyle(
                            fontSize: 14,
                            color: colors.textSecondary,
                            decoration: widget.isCompleted
                                ? TextDecoration.lineThrough
                                : TextDecoration.none,
                            decorationColor: colors.textSecondary,
                          ),
                        ),
                        if (widget.memo != null && widget.memo!.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            widget.memo!,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textHint,
                              fontStyle: FontStyle.italic,
                              decoration: widget.isCompleted
                                  ? TextDecoration.lineThrough
                                  : TextDecoration.none,
                              decorationColor: colors.textHint,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),

                  // Right: dumbbell + chevron
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Icon(
                      LucideIcons.dumbbell,
                      size: 18,
                      color: colors.textHint,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    _isExpanded
                        ? LucideIcons.chevronUp
                        : LucideIcons.chevronDown,
                    size: 20,
                    color: colors.textHint,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),

          // Expanded set rows
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeInOut,
            child: _isExpanded
                ? Container(
                    color: colors.surfaceDim,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
                    child: Column(
                      children: [
                        // Column header
                        Padding(
                          padding: const EdgeInsets.only(bottom: 6),
                          child: Row(
                            children: [
                              const SizedBox(width: 50),
                              SizedBox(
                                width: 60,
                                child: Text(
                                  '回数',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const SizedBox(width: 12),
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 70,
                                child: Text(
                                  '重量',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              Text(
                                '完了',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                          ),
                        ),

                        // Set rows
                        ...List.generate(_localSets.length, (i) {
                          final set = _localSets[i];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 6),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // Set number label
                                SizedBox(
                                  width: 50,
                                  child: Text(
                                    'Set ${set.setNumber}',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ),

                                // Reps input
                                SizedBox(
                                  width: 60,
                                  height: 40,
                                  child: TextFormField(
                                    controller: _repsControllers[i],
                                    focusNode: _repsFocusNodes[i],
                                    keyboardType: TextInputType.number,
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      suffixText: '回',
                                      suffixStyle: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: colors.surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colors.border,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colors.border,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (v) => _onRepsChanged(i, v),
                                  ),
                                ),

                                const SizedBox(width: 8),

                                Text(
                                  '×',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),

                                const SizedBox(width: 8),

                                // Weight input
                                SizedBox(
                                  width: 70,
                                  height: 40,
                                  child: TextFormField(
                                    controller: _weightControllers[i],
                                    focusNode: _weightFocusNodes[i],
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colors.textPrimary,
                                    ),
                                    decoration: InputDecoration(
                                      suffixText: 'kg',
                                      suffixStyle: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                      contentPadding:
                                          const EdgeInsets.symmetric(
                                        horizontal: 4,
                                        vertical: 8,
                                      ),
                                      isDense: true,
                                      filled: true,
                                      fillColor: colors.surface,
                                      border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colors.border,
                                        ),
                                      ),
                                      enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: BorderSide(
                                          color: colors.border,
                                        ),
                                      ),
                                      focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        borderSide: const BorderSide(
                                          color: AppColors.primary,
                                          width: 1.5,
                                        ),
                                      ),
                                    ),
                                    onChanged: (v) => _onWeightChanged(i, v),
                                  ),
                                ),

                                const Spacer(),

                                // Done checkbox
                                SizedBox(
                                  width: 32,
                                  height: 32,
                                  child: Checkbox(
                                    value: set.done,
                                    onChanged: (val) => _onDoneChanged(i, val),
                                    activeColor: AppColors.emerald500,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );

    if (widget.isCompleted) {
      return Opacity(opacity: 0.5, child: card);
    }
    return card;
  }
}

// ============================================
// Previews
// ============================================

final _sampleSetsPartial = [
  const ActualSet(setNumber: 1, reps: 8, weight: 40, done: true),
  const ActualSet(setNumber: 2, reps: 10, weight: 40, done: true),
  const ActualSet(setNumber: 3, reps: 8, weight: 40, done: false),
];

final _sampleSetsAll = [
  const ActualSet(setNumber: 1, reps: 8, weight: 40, done: true),
  const ActualSet(setNumber: 2, reps: 10, weight: 40, done: true),
  const ActualSet(setNumber: 3, reps: 8, weight: 40, done: true),
];

class _ExpandedUncompletedPreview extends StatefulWidget {
  @override
  State<_ExpandedUncompletedPreview> createState() =>
      _ExpandedUncompletedPreviewState();
}

class _ExpandedUncompletedPreviewState
    extends State<_ExpandedUncompletedPreview> {
  List<ActualSet> _sets = [];

  @override
  void initState() {
    super.initState();
    _sets = [];
  }

  @override
  Widget build(BuildContext context) {
    return WorkoutExerciseCard(
      exerciseName: 'ベンチプレス',
      targetSets: 3,
      targetReps: 10,
      targetWeight: 40.0,
      isCompleted: false,
      actualSets: _sets.isEmpty ? null : _sets,
      onSetsUpdated: (sets) => setState(() => _sets = sets),
    );
  }
}

class _PartiallyCompletedPreview extends StatefulWidget {
  @override
  State<_PartiallyCompletedPreview> createState() =>
      _PartiallyCompletedPreviewState();
}

class _PartiallyCompletedPreviewState
    extends State<_PartiallyCompletedPreview> {
  late List<ActualSet> _sets;

  @override
  void initState() {
    super.initState();
    _sets = List.from(_sampleSetsPartial);
  }

  @override
  Widget build(BuildContext context) {
    return WorkoutExerciseCard(
      exerciseName: 'ベンチプレス',
      targetSets: 3,
      targetReps: 10,
      targetWeight: 40.0,
      isCompleted: false,
      actualSets: _sets,
      onSetsUpdated: (sets) => setState(() => _sets = sets),
    );
  }
}

class _AllCompletedPreview extends StatefulWidget {
  @override
  State<_AllCompletedPreview> createState() => _AllCompletedPreviewState();
}

class _AllCompletedPreviewState extends State<_AllCompletedPreview> {
  late List<ActualSet> _sets;

  @override
  void initState() {
    super.initState();
    _sets = List.from(_sampleSetsAll);
  }

  @override
  Widget build(BuildContext context) {
    return WorkoutExerciseCard(
      exerciseName: 'ベンチプレス',
      targetSets: 3,
      targetReps: 10,
      targetWeight: 40.0,
      isCompleted: true,
      actualSets: _sets,
      onSetsUpdated: (sets) => setState(() => _sets = sets),
    );
  }
}

class _CollapsedPreview extends StatefulWidget {
  @override
  State<_CollapsedPreview> createState() => _CollapsedPreviewState();
}

class _CollapsedPreviewState extends State<_CollapsedPreview> {
  List<ActualSet> _sets = [];

  @override
  Widget build(BuildContext context) {
    return WorkoutExerciseCard(
      exerciseName: 'スクワット',
      targetSets: 4,
      targetReps: 8,
      targetWeight: 60.0,
      memo: 'フォームに注意',
      isCompleted: false,
      actualSets: _sets.isEmpty ? null : _sets,
      onSetsUpdated: (sets) => setState(() => _sets = sets),
    );
  }
}

@Preview(name: 'WorkoutExerciseCard - Expanded Uncompleted')
Widget previewWorkoutExerciseCardExpandedUncompleted() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _ExpandedUncompletedPreview(),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutExerciseCard - Partially Completed')
Widget previewWorkoutExerciseCardPartiallyCompleted() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PartiallyCompletedPreview(),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutExerciseCard - All Completed')
Widget previewWorkoutExerciseCardAllCompleted() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _AllCompletedPreview(),
        ),
      ),
    ),
  );
}

@Preview(name: 'WorkoutExerciseCard - Collapsed')
Widget previewWorkoutExerciseCardCollapsed() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _CollapsedPreview(),
        ),
      ),
    ),
  );
}
