import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/record_streak/data/record_streak_repository.dart';
import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';
import 'package:fit_connect_mobile/shared/utils/record_tags.dart';

part 'record_streak_provider.g.dart';

/// 今のクライアントの記録の連続（DB の get_record_streak。設計 §6.1・§6.2）。
///
/// 自動破棄なので、ホームを作るたびに読み直す（記録タブ・メッセージ・プランで付けた記録は、
/// ホームに戻れば反映される）。アプリが前面に戻ったとき（app.dart）と、目覚めの評価を付けたとき
/// （SleepRecords.upsertWakeupRating）にも `ref.invalidate` で読み直す。
/// ログインしていない（クライアントが分からない）ときは null
@riverpod
Future<RecordStreakStatus?> recordStreak(Ref ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return null;
  // await より前に取得しておく（await の後で ref を使わない）
  final repository = ref.watch(recordStreakRepositoryProvider);
  return repository.fetch(clientId);
}

/// 送ったタグの先取り（設計 §6.3）。記録になるタグを送ったときの
/// (client id, サーバーが付けた送信時刻の日本時間の日付, 端末の時計で送った時刻)。
///
/// メッセージから作られる記録は、DB の webhook の後で数秒遅れて入る。送った直後にホームへ戻っても
/// 今日記録済みに見えるよう、送ったことを覚えておく（[recordStreakViewProvider] が DB の結果と合わせる）。
/// 効くのは送ってから 60 秒（[RecordStreakTagOverlay.window]）のあいだだけで、過ぎたら DB の値だけを見る。
/// そのため、タグが記録にならなかったとき（全角の数字・範囲外の値など）や、送ったあとにタグを消す編集を
/// したときも、次に読み直せば DB のとおりに戻る。
/// 覚えるのはアプリを終えるまで（keepAlive）。ログアウトしても消さず、効くかどうかは
/// client id・日付・送ってからの時間で決める
@Riverpod(keepAlive: true)
class RecordStreakTagOverlay extends _$RecordStreakTagOverlay {
  /// [now] は端末の今の時刻を返す。テストで差し替える（省略時は DateTime.now）
  RecordStreakTagOverlay({DateTime Function()? now})
      : _now = now ?? DateTime.now;

  /// 先取りが効く長さ（送ってから 60 秒。ちょうど 60 秒までは効く）。
  ///
  /// 記録が webhook の後で数秒遅れて作られる間を埋めるためだけのもの。過ぎたら DB の値だけを見る。
  /// 端末の時計で数える（起点の送った時刻も端末の時計）。過ぎたときに行を自分では作り直さない
  /// （ホームを開いたとき・前面に戻ったときに作り直す）
  static const window = Duration(seconds: 60);

  final DateTime Function() _now;

  @override
  ({String clientId, String jstDateKey, DateTime sentAt})? build() => null;

  /// メッセージを送れたとき（PaginatedMessages.sendMessage）に、送ったタグ [tags] と、
  /// サーバーが付けた送信時刻 [createdAt]（messages.created_at）を渡す。
  ///
  /// サーバーが記録を作るタグ（[tagsCreateRecord]。最初のタグだけを見る）で、クライアントが分かるときだけ、
  /// (今の client id, [createdAt] の日本時間の日付, 端末の今の時刻) を覚える（前に覚えたものは置き換える）。
  /// それ以外は何もしない。
  /// 日付は端末の時計でなく [createdAt] で決める（サーバーは記録の recorded_at にも
  /// messages.created_at を使うので、端末の時計が 0 時の前後でずれていても、記録と同じ日になる）
  void onMessageSent(List<String> tags, {required DateTime createdAt}) {
    if (!tagsCreateRecord(tags)) return;
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) return;
    state = (
      clientId: clientId,
      jstDateKey: jstDateKey(createdAt),
      sentAt: _now(),
    );
  }

  /// 覚えた先取りで、[clientId] の [asOfDate]（DB の今日）を今、記録済みとして扱うか。
  ///
  /// 覚えた client id と日付が同じで、送ってから [window] 以内（端末の今の時刻で数える）のときだけ true。
  /// 端末の時計が送った時刻より前に戻っていたら（時計を動かした）効かせない
  bool countsToday({required String? clientId, required String asOfDate}) {
    final overlay = state;
    if (overlay == null ||
        overlay.clientId != clientId ||
        overlay.jstDateKey != asOfDate) {
      return false;
    }
    final elapsed = _now().difference(overlay.sentAt);
    return !elapsed.isNegative && elapsed <= window;
  }
}

/// ホームの「記録の連続」の行に出す状態（[recordStreakProvider] と送ったタグの先取りを合わせる。
/// 設計 §6.1・§6.3・§6.4）。
///
/// [recordStreakProvider] の状態を AsyncValue.whenData で写す。Riverpod 2.6.1 の whenData が
/// 前の値を残すのは、前の値の AsyncData（読み直しの間）だけ:
/// - 読み直し（invalidate。前面に戻ったとき・目覚めの評価を付けたとき）の間 → 前の値の AsyncData（isRefreshing）
/// - 読み直しに失敗した → 前の値を持たない AsyncError（ホームは行を消す。前の値は残さない）
/// - client id が変わった（ログインし直したなど）→ 前の値を持たない AsyncLoading
///   （ホームはスケルトン。前の人の値を出さない）
/// - 初めての読み込み中・読めない → AsyncLoading / AsyncError
/// - ログインしていない → AsyncData(null)
///
/// 先取りが効くのは、覚えた client id が今の人で、覚えた日付が DB の今日（asOfDate）と同じで、
/// 送ってから [RecordStreakTagOverlay.window] 以内のときだけ（[RecordStreakTagOverlay.countsToday]）。
/// 送ってからの時間は、この状態を作るたびに調べる（過ぎたときに自分では作り直さない）
@riverpod
AsyncValue<RecordStreakView?> recordStreakView(Ref ref) {
  final statusAsync = ref.watch(recordStreakProvider);
  // 先取りを覚えたら作り直す（state を見る）。効くかどうかは notifier が端末の時計で調べる
  ref.watch(recordStreakTagOverlayProvider);
  final overlay = ref.watch(recordStreakTagOverlayProvider.notifier);
  final clientId = ref.watch(currentClientIdProvider);
  // 前の値を持つ AsyncError・AsyncLoading（読み直しの失敗・client id の変化）は、whenData が
  // 前の値を落とした AsyncError / AsyncLoading にする（上の一覧。どちらも意図した動き）
  return statusAsync.whenData((status) {
    if (status == null) return null;
    return recordStreakViewOf(
      status,
      countedTodayByTags: overlay.countsToday(
        clientId: clientId,
        asOfDate: status.asOfDate,
      ),
    );
  });
}
