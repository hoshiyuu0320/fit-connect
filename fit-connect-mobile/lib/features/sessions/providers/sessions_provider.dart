import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/data/session_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'sessions_provider.g.dart';

/// SessionRepositoryのProvider
@riverpod
SessionRepository sessionRepository(SessionRepositoryRef ref) {
  return SessionRepository();
}

/// 今後のセッション一覧を取得するProvider（開始時刻の昇順）。
/// 「今後」＝終了時刻が未来（SessionRepository の仕分け規則を参照）
@riverpod
Future<List<SessionModel>> upcomingSessions(UpcomingSessionsRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repository = ref.watch(sessionRepositoryProvider);
  return repository.getUpcomingSessions(clientId: clientId);
}

/// 過去のセッション一覧を取得するProvider（開始時刻の降順・最大50件）。
/// 「過去」＝終了時刻が過去（SessionRepository の仕分け規則を参照）
@riverpod
Future<List<SessionModel>> pastSessions(PastSessionsRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repository = ref.watch(sessionRepositoryProvider);
  return repository.getPastSessions(clientId: clientId);
}

/// 直近の次回セッションを取得するProvider（予定が無ければnull）。
///
/// 「今後」にはキャンセル/完了済みも時系列どおり含まれるが、ホームの
/// 「次回のセッション」としては予定として生きているものを指したいので、
/// 終了扱いのステータスは読み飛ばす（一覧の「今後」には残り続ける）。
@riverpod
Future<SessionModel?> nextSession(NextSessionRef ref) async {
  final sessions = await ref.watch(upcomingSessionsProvider.future);

  for (final session in sessions) {
    if (!session.isClosed) return session;
  }
  return null;
}
