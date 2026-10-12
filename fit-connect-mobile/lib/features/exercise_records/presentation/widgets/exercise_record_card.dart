import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';
import 'package:intl/intl.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/exercise_records/models/exercise_record_model.dart';
import 'package:fit_connect_mobile/features/meal_records/presentation/widgets/record_date_format.dart';
import 'exercise_entry_card.dart';
import 'exercise_kind.dart';

/// 運動の記録 1 件のカード。正本は `record-screens.js` の `ExRecord`（運動の記録の分）。
///
/// - 見出し: 系統のアイコン（筋トレ = dumbbell / 有酸素 = footprints）+ 系統名（右に日時「9月12日（土）18:20」）。
///   筋トレ・有酸素のどちらでもない種類（ヨガなど）は activity のアイコンに種類の名前
/// - 題名（17 / 500）と、任意のノート（16）、補足（「消費 320 kcal · メッセージから」）。
///   組み立ては [exerciseRecordTitle] / [exerciseRecordNote] / [exerciseRecordMeta]
class ExerciseRecordCard extends StatelessWidget {
  const ExerciseRecordCard({super.key, required this.record});

  final ExerciseRecord record;

  @override
  Widget build(BuildContext context) {
    final kind = exerciseKindOf(record.exerciseType);
    return ExerciseEntryCard(
      icon: kind.icon,
      type: exerciseRecordKindLabel(record),
      time: recordDateTimeLabel(record.recordedAt),
      title: exerciseRecordTitle(record),
      note: exerciseRecordNote(record),
      meta: exerciseRecordMeta(record),
    );
  }
}

/// 見出しの種別。筋トレ・有酸素はまとめた名前、どちらでもない種類は種類の名前（ヨガなど）
String exerciseRecordKindLabel(ExerciseRecord record) {
  final kind = exerciseKindOf(record.exerciseType);
  return kind == ExerciseKind.other
      ? exerciseTypeLabel(record.exerciseType)
      : kind.label;
}

/// 題名。例:「ランニング 5.0 km · 30分」
///
/// - 種目まで決まっている種類（ランニングなど）: 種類の名前 + 距離 + 「 · 」+ 時間
/// - 大まかな種類（筋トレ・有酸素・その他）: メモに意味のある文字があればそのメモ
///   （例:「プランク 1分 × 3セット」）、なければ種類の名前 + 距離 + 時間
String exerciseRecordTitle(ExerciseRecord record) {
  final specific = exerciseTypeIsSpecific(record.exerciseType);
  final meaningfulMemo = exerciseMemoIsMeaningful(
    record.memo,
    exerciseType: record.exerciseType,
  );

  if (!specific && meaningfulMemo) {
    return record.memo!.trim();
  }

  final head = StringBuffer(exerciseTypeLabel(record.exerciseType));
  if (record.distance != null) {
    head.write(' ${record.distance!.toStringAsFixed(1)} km');
  }
  return [
    head.toString(),
    if (record.duration != null) '${record.duration}分',
  ].join(' · ');
}

/// ノート。種目まで決まっている種類で、メモに意味のある文字があるときだけ。
/// （大まかな種類ではメモが題名になる。数値と単位だけのメモは題名・補足と二重になるので出さない）
String? exerciseRecordNote(ExerciseRecord record) {
  if (!exerciseTypeIsSpecific(record.exerciseType)) return null;
  if (!exerciseMemoIsMeaningful(
    record.memo,
    exerciseType: record.exerciseType,
  )) {
    return null;
  }
  return record.memo!.trim();
}

/// 補足。例:「消費 320 kcal · メッセージから」。どちらも無ければ null
String? exerciseRecordMeta(ExerciseRecord record) {
  final parts = <String>[
    if (record.calories != null)
      '消費 ${NumberFormat('#,###').format(record.calories!.round())} kcal',
    if (record.source == 'message') 'メッセージから',
  ];
  return parts.isEmpty ? null : parts.join(' · ');
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

ExerciseRecord _record(
  String id,
  String type,
  DateTime at, {
  String? memo,
  int? duration,
  double? distance,
  double? calories,
  String source = 'message',
}) =>
    ExerciseRecord(
      id: id,
      clientId: 'client-1',
      exerciseType: type,
      memo: memo,
      duration: duration,
      distance: distance,
      calories: calories,
      recordedAt: at,
      source: source,
      createdAt: at,
      updatedAt: at,
    );

Widget _previewRecords() {
  final now = DateTime.now();
  return Column(
    children: [
      ExerciseRecordCard(
        record: _record('1', 'running', now,
            duration: 30, distance: 5, calories: 320),
      ),
      const SizedBox(height: 16),
      ExerciseRecordCard(
        record: _record('2', 'strength_training', now, memo: 'プランク 1分 × 3セット'),
      ),
      const SizedBox(height: 16),
      ExerciseRecordCard(
        record: _record('3', 'yoga', now,
            duration: 45, memo: '朝のストレッチを中心に', source: 'manual'),
      ),
    ],
  );
}

@Preview(name: 'ExerciseRecordCard - 通常')
Widget previewExerciseRecordCard() =>
    _previewApp(Brightness.light, 1, _previewRecords());

@Preview(name: 'ExerciseRecordCard - ダーク')
Widget previewExerciseRecordCardDark() =>
    _previewApp(Brightness.dark, 1, _previewRecords());

@Preview(name: 'ExerciseRecordCard - 文字拡大 1.35')
Widget previewExerciseRecordCardLargeText() =>
    _previewApp(Brightness.light, 1.35, _previewRecords());
