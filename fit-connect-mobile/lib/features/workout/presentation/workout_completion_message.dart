/// ワークアウトの完了報告としてトレーナーへ送るメッセージ（本文とタグ）。
///
/// **この書式は Web 側との取り決めなので、変えてはいけない。**
/// Web の `fit-connect/src/components/message/recordCardParser.ts` が、
/// 本文の `^本日のワークアウトプラン「([^」]+)」を達成しました！` と
/// `🔥\s*消費カロリー:\s*(\d+)\s*kcal` を解析して記録カードにする。
/// タグ `#運動:完了` は記録の判定（`messages.tags`）に使われる。
/// 絵文字・全角かっこ・改行の数まで含めて固定（`test/.../workout_completion_message_test.dart` が文字列で固定している）。
library;

/// 送るメッセージ（本文とタグ）
class WorkoutCompletionMessage {
  const WorkoutCompletionMessage({required this.content, required this.tags});

  final String content;
  final List<String> tags;
}

/// 完了報告のタグ（毎回新しいリストを返す）
List<String> buildWorkoutCompletionTags() => ['#運動:完了'];

/// 完了報告の本文とタグを組み立てる。
///
/// - 先頭は常に「本日のワークアウトプラン「{プラン名}」を達成しました！」
/// - 消費カロリー（[calories] が null でない）か感想（[feedback] が空でない）があれば、先頭の後ろに空行を 1 つ入れる
/// - 消費カロリーがあれば「🔥 消費カロリー: {n}kcal」、感想があれば「💬 {感想}」を、この順に改行で続ける
WorkoutCompletionMessage buildWorkoutCompletionMessage({
  required String planTitle,
  String? feedback,
  int? calories,
}) {
  final hasCalories = calories != null;
  final hasFeedback = feedback != null && feedback.isNotEmpty;

  String messageContent = '本日のワークアウトプラン「$planTitle」を達成しました！';
  if (hasCalories || hasFeedback) messageContent += '\n';
  if (hasCalories) messageContent += '\n🔥 消費カロリー: ${calories}kcal';
  if (hasFeedback) messageContent += '\n💬 $feedback';

  return WorkoutCompletionMessage(
    content: messageContent,
    tags: buildWorkoutCompletionTags(),
  );
}
