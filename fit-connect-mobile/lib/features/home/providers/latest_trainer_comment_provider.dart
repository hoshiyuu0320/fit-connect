import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/data/message_repository.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/models/tag_model.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';

// ============================================
// ホーム専用: 担当トレーナーの最新コメント
// ============================================
// メッセージ画面の `paginatedMessagesProvider` は Realtime を購読するので、ホームからは
// 使わない（取得中に破棄されると購読が解除されずに残るため）。ここでは既存の
// `MessageRepository` の取得だけを使い、Realtime は張らない。

/// 最新のトレーナーのコメントと、それが返信している記録の種別。
class LatestTrainerComment {
  const LatestTrainerComment({required this.message, this.recordLabel});

  final Message message;

  /// 返信先の記録の種類（「朝食」「体重」など）。返信先が分からなければ null
  final String? recordLabel;

  /// 本文。画像だけのメッセージは「写真を送りました」
  String get body {
    final text = (message.content ?? '').trim();
    if (text.isNotEmpty) return text;
    return '写真を送りました';
  }
}

/// 会話の中から、トレーナーが最後に送ったメッセージを探す。無ければ null。
///
/// - 並び順に頼らず `createdAt` が最新のものを選ぶ
/// - 本文も画像も無いメッセージは対象外
/// - 返信先（`replyToMessageId`）が [messages] の中に見つかり、そのタグが食事・運動・体重の
///   どれかなら、その種類を [LatestTrainerComment.recordLabel] にする（タグに詳細があれば
///   「朝食」のように詳細を使う）
LatestTrainerComment? findLatestTrainerComment(List<Message> messages) {
  Message? latest;
  for (final m in messages) {
    if (m.senderType != 'trainer') continue;
    final hasText = (m.content ?? '').trim().isNotEmpty;
    final hasImage = (m.imageUrls ?? const <String>[]).isNotEmpty;
    if (!hasText && !hasImage) continue;
    if (latest == null || m.createdAt.isAfter(latest.createdAt)) latest = m;
  }
  if (latest == null) return null;
  return LatestTrainerComment(
    message: latest,
    recordLabel: _recordLabelOfReplyTarget(latest, messages),
  );
}

const _recordCategories = {'食事', '運動', '体重'};

String? _recordLabelOfReplyTarget(Message reply, List<Message> all) {
  final targetId = reply.replyToMessageId;
  if (targetId == null) return null;
  Message? target;
  for (final m in all) {
    if (m.id == targetId) {
      target = m;
      break;
    }
  }
  if (target == null) return null;
  for (final raw in target.tags ?? const <String>[]) {
    final tag = TagData.parse(raw);
    if (!_recordCategories.contains(tag.category)) continue;
    final detail = tag.detail?.trim();
    return (detail == null || detail.isEmpty) ? tag.category : detail;
  }
  return null;
}

/// 新しいほうから [pageSize] 件ずつ（最大 [maxPages] ページ）取り、
/// トレーナーのメッセージが見つかった時点で止める。
///
/// 最新のコメントと、その返信先（直前の自分のメッセージ）が同じページに入っていれば足りる。
/// 自分のメッセージが続いてトレーナーの最新がページの外にあるときだけ、遡って取る。
/// 見つからなければ null（メッセージがまだ無い）。取得に失敗したら例外をそのまま投げる。
Future<LatestTrainerComment?> fetchLatestTrainerComment({
  required MessageRepository repository,
  required String userId,
  required String trainerId,
  int pageSize = 30,
  int maxPages = 3,
}) async {
  var collected = <Message>[];
  DateTime? before;
  for (var page = 0; page < maxPages; page++) {
    final batch = await repository.fetchMessages(
      userId: userId,
      otherUserId: trainerId,
      limit: pageSize,
      before: before,
    );
    if (batch.isEmpty) break;
    // fetchMessages は古い順。遡るページは前に足す
    collected = [...batch, ...collected];

    final found = findLatestTrainerComment(collected);
    if (found != null) return found;
    // 取れた件数がページに満たなければ、これより古いメッセージは無い
    if (batch.length < pageSize) break;
    before = batch.first.createdAt;
  }
  return null;
}

/// ホームの「担当トレーナーの最新コメント」。
///
/// - 取得は 1 回だけ（Realtime は購読しない）。ホームを開くたびに取り直す（autoDispose）
/// - 新着の通知（未読数）が変わったら取り直す
/// - メッセージがまだ無いときは null、取得に失敗したときは `AsyncError`
/// - テストでは `latestTrainerCommentProvider.overrideWith((ref) async => ...)` で差し替える
final latestTrainerCommentProvider =
    FutureProvider.autoDispose<LatestTrainerComment?>((ref) async {
  final user = await ref.watch(authNotifierProvider.future);
  final client = await ref.watch(currentClientProvider.future);
  final trainerId = client?.trainerId;
  if (user == null || trainerId == null) return null;

  // 未読数の値が変わった（新着・既読）のをきっかけに取り直す。
  // 最初の読み込み完了では取り直さない（`watch` だと loading → data の遷移で二重に取得する）
  ref.listen<AsyncValue<int>>(unreadMessageCountProvider, (previous, next) {
    final before = previous?.valueOrNull;
    final after = next.valueOrNull;
    if (next is AsyncData<int> &&
        before != null &&
        after != null &&
        before != after) {
      ref.invalidateSelf();
    }
  });

  final repository = ref.watch(messageRepositoryProvider);
  return fetchLatestTrainerComment(
    repository: repository,
    userId: user.id,
    trainerId: trainerId,
  );
});
