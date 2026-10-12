import 'package:flutter/widgets.dart';
import 'package:lucide_icons/lucide_icons.dart';

/// 運動の「系統」。記録タブの種類フィルタ（すべて / 筋トレ / 有酸素）と、
/// 週ストリップ・月カードの印、合計の内訳に使う。
///
/// 運動の種類（`exercise_type`）は 9 種ある。そのままでは多すぎるので、次の対応で 2 系統にまとめる。
///
/// | 系統 | exercise_type |
/// | --- | --- |
/// | 筋トレ | `strength_training` |
/// | 有酸素 | `cardio` `walking` `running` `cycling` `swimming` |
/// | どちらでもない | `yoga` `pilates` `other`（と未知の値） |
///
/// 「どちらでもない」運動は、フィルタが「すべて」のときだけ出る（筋トレ・有酸素のどちらを選んでも出ない）。
/// プランの完了（`workout_assignments`）は筋トレとして数える。
///
/// 色は割り振らず、アイコン（筋トレ = dumbbell、有酸素 = footprints）と言葉で区別する。
enum ExerciseKind {
  /// 筋トレ
  strength,

  /// 有酸素（ウォーキング・ランニング・サイクリング・水泳を含む）
  cardio,

  /// 筋トレ・有酸素のどちらにも入らない（ヨガ・ピラティス・その他）
  other,
}

/// 筋トレ系の `exercise_type`
const Set<String> _strengthTypes = {'strength_training'};

/// 有酸素系の `exercise_type`
const Set<String> _cardioTypes = {
  'cardio',
  'walking',
  'running',
  'cycling',
  'swimming',
};

/// `exercise_type` → 系統
ExerciseKind exerciseKindOf(String exerciseType) {
  if (_strengthTypes.contains(exerciseType)) return ExerciseKind.strength;
  if (_cardioTypes.contains(exerciseType)) return ExerciseKind.cardio;
  return ExerciseKind.other;
}

extension ExerciseKindX on ExerciseKind {
  /// フィルタ・内訳の表示名（筋トレ / 有酸素）。`other` はまとめた名前を持たない
  String get label => switch (this) {
        ExerciseKind.strength => '筋トレ',
        ExerciseKind.cardio => '有酸素',
        ExerciseKind.other => 'その他',
      };

  /// アイコン（筋トレ = dumbbell、有酸素 = footprints、その他 = activity）
  IconData get icon => switch (this) {
        ExerciseKind.strength => LucideIcons.dumbbell,
        ExerciseKind.cardio => LucideIcons.footprints,
        ExerciseKind.other => LucideIcons.activity,
      };
}

/// `exercise_type` の表示名（記録カードの題名に使う）
String exerciseTypeLabel(String exerciseType) {
  switch (exerciseType) {
    case 'strength_training':
      return '筋トレ';
    case 'cardio':
      return '有酸素運動';
    case 'walking':
      return 'ウォーキング';
    case 'running':
      return 'ランニング';
    case 'cycling':
      return 'サイクリング';
    case 'swimming':
      return '水泳';
    case 'yoga':
      return 'ヨガ';
    case 'pilates':
      return 'ピラティス';
    default:
      return 'その他';
  }
}

/// 種目まで決まっている種類か（ランニングなど）。
/// `strength_training` / `cardio` / `other` は「大まかな種類」で、題名は記録のメモを使う
bool exerciseTypeIsSpecific(String exerciseType) =>
    !const {'strength_training', 'cardio', 'other'}.contains(exerciseType);

/// メモが「数値と単位だけ」でないか。
///
/// メッセージから作った記録のメモは、タグを除いた本文（例:「5km 30分 320kcal」）で、
/// 距離・時間・消費カロリーは別の項目に取り込まれている。数値と単位だけのメモを
/// そのまま出すと、題名や補足の行と二重になるので、意味のある文字が残るものだけを出す。
/// [exerciseType] を渡すと、その種類の名前（「ランニング」など）だけのメモも「意味なし」とみなす
/// （題名にすでに書いてあるため）。
bool exerciseMemoIsMeaningful(String? memo, {String? exerciseType}) {
  if (memo == null) return false;
  var text = memo;
  if (exerciseType != null) {
    text = text.replaceAll(exerciseTypeLabel(exerciseType), '');
  }
  final stripped = text
      .replaceAll(
        RegExp(
          r'km|kg|kcal|min|cal|キロ|カロリー|時間|分|秒|歩|回|セット|[0-9０-９.,．、。・×xX\s]',
          caseSensitive: false,
        ),
        '',
      )
      .trim();
  return stripped.isNotEmpty;
}
