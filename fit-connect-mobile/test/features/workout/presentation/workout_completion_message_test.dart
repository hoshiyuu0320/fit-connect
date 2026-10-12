import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/workout/presentation/workout_completion_message.dart';

/// Web 側（`fit-connect/src/components/message/recordCardParser.ts`）が使う正規表現と同じもの
final _webAchievement = RegExp(r'^本日のワークアウトプラン「([^」]+)」を達成しました！');
final _webCalories = RegExp(r'🔥\s*消費カロリー:\s*(\d+)\s*kcal');

/// 再デザイン前（HEAD の `workout_screen.dart`）の組み立てをそのまま写したもの。
/// 純関数と 1 文字も違わないことを、組み合わせ全部で突き合わせる
String _legacyContent(String planTitle, String? feedback, int? calories) {
  final hasCalories = calories != null;
  final hasFeedback = feedback != null && feedback.isNotEmpty;

  String messageContent = '本日のワークアウトプラン「$planTitle」を達成しました！';
  if (hasCalories || hasFeedback) messageContent += '\n';
  if (hasCalories) messageContent += '\n🔥 消費カロリー: ${calories}kcal';
  if (hasFeedback) messageContent += '\n💬 $feedback';
  return messageContent;
}

void main() {
  group('buildWorkoutCompletionMessage（本文とタグ。Web との取り決めなので文字列で固定）', () {
    test('感想も消費カロリーもない: 1 行だけ（末尾に改行を付けない）', () {
      final m = buildWorkoutCompletionMessage(planTitle: '上半身');

      expect(m.content, '本日のワークアウトプラン「上半身」を達成しました！');
      expect(m.tags, ['#運動:完了']);
    });

    test('感想が空文字でも「なし」と同じ', () {
      final m = buildWorkoutCompletionMessage(planTitle: '上半身', feedback: '');

      expect(m.content, '本日のワークアウトプラン「上半身」を達成しました！');
    });

    test('消費カロリーだけ: 空行のあとに「🔥 消費カロリー: 280kcal」', () {
      final m = buildWorkoutCompletionMessage(planTitle: '上半身', calories: 280);

      expect(
        m.content,
        '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal',
      );
      expect(m.tags, ['#運動:完了']);
    });

    test('感想だけ: 空行のあとに「💬 感想」', () {
      final m = buildWorkoutCompletionMessage(
        planTitle: '上半身',
        feedback: '肩の動きがよくなってきました。',
      );

      expect(
        m.content,
        '本日のワークアウトプラン「上半身」を達成しました！\n\n💬 肩の動きがよくなってきました。',
      );
      expect(m.tags, ['#運動:完了']);
    });

    test('両方あり: 空行のあと「🔥 消費カロリー」→ 改行 →「💬 感想」の順', () {
      final m = buildWorkoutCompletionMessage(
        planTitle: '上半身',
        feedback: 'ラットプルダウンは最後のセットが重かったです。',
        calories: 280,
      );

      expect(
        m.content,
        '本日のワークアウトプラン「上半身」を達成しました！\n'
        '\n'
        '🔥 消費カロリー: 280kcal\n'
        '💬 ラットプルダウンは最後のセットが重かったです。',
      );
      expect(m.tags, ['#運動:完了']);
    });

    test('消費カロリー 0 は「あり」として扱う（null だけが「なし」）', () {
      final m = buildWorkoutCompletionMessage(planTitle: '上半身', calories: 0);

      expect(
        m.content,
        '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 0kcal',
      );
    });

    test('感想の改行・前後の空白はそのまま送る（加工しない）', () {
      final m = buildWorkoutCompletionMessage(
        planTitle: '上半身',
        feedback: ' 1行目\n2行目 ',
      );

      expect(
        m.content,
        '本日のワークアウトプラン「上半身」を達成しました！\n\n💬  1行目\n2行目 ',
      );
    });

    test('プラン名の既定（「ワークアウトプラン」）でも書式は同じ', () {
      final m = buildWorkoutCompletionMessage(planTitle: 'ワークアウトプラン');

      expect(m.content, '本日のワークアウトプラン「ワークアウトプラン」を達成しました！');
    });

    test('タグは毎回新しいリスト（呼び出し側が書き換えても次に影響しない）', () {
      final a = buildWorkoutCompletionMessage(planTitle: '上半身');
      a.tags.add('#x');
      final b = buildWorkoutCompletionMessage(planTitle: '上半身');

      expect(b.tags, ['#運動:完了']);
      expect(buildWorkoutCompletionTags(), ['#運動:完了']);
    });
  });

  group('Web の解析（recordCardParser.ts の正規表現）に一致する', () {
    test('先頭行はプラン名を取り出せる', () {
      final m = buildWorkoutCompletionMessage(planTitle: '脚の日');

      expect(_webAchievement.firstMatch(m.content)?.group(1), '脚の日');
    });

    test('消費カロリーは数値だけを取り出せる', () {
      final m = buildWorkoutCompletionMessage(
        planTitle: '上半身',
        feedback: '良かった',
        calories: 420,
      );

      expect(_webAchievement.hasMatch(m.content), isTrue);
      expect(_webCalories.firstMatch(m.content)?.group(1), '420');
    });

    test('消費カロリーがなければ、カロリーの行は出ない', () {
      final m = buildWorkoutCompletionMessage(planTitle: '上半身', feedback: '良かった');

      expect(_webCalories.hasMatch(m.content), isFalse);
      expect(_webAchievement.hasMatch(m.content), isTrue);
    });
  });

  group('再デザイン前の組み立て（HEAD）と 1 文字も変わらない', () {
    const titles = ['上半身', 'ワークアウトプラン', '脚の日（A）'];
    const feedbacks = <String?>[null, '', '良かった', '重かった\n最後のセットが', ' 空白 '];
    const caloriesList = <int?>[null, 0, 280, 1200];

    for (final title in titles) {
      for (final feedback in feedbacks) {
        for (final calories in caloriesList) {
          test('「$title」/ 感想 ${feedback == null ? 'null' : '「$feedback」'} / ${calories ?? 'null'}', () {
            final m = buildWorkoutCompletionMessage(
              planTitle: title,
              feedback: feedback,
              calories: calories,
            );

            expect(m.content, _legacyContent(title, feedback, calories));
            expect(m.tags, ['#運動:完了']);
          });
        }
      }
    }
  });
}
