import 'dart:async';

import 'package:fit_connect_mobile/features/record_streak/data/record_streak_repository.dart';
import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';

/// 取得した client id を記録し、client id ごとに決めた結果を返す RecordStreakRepository
/// （Supabase には出ない）。
///
/// `recordStreakRepositoryProvider.overrideWithValue(FakeRecordStreakRepository())` で差し替えて、
/// 本物の recordStreakProvider・recordStreakViewProvider の動き（読み直し・失敗・client id の変化）を確かめる。
class FakeRecordStreakRepository implements RecordStreakRepository {
  /// fetch に渡された client id（呼ばれた順）
  final fetchedClientIds = <String>[];

  /// client id ごとの結果
  final results = <String, RecordStreakStatus>{};

  /// 渡すと fetch がこの例外で失敗する（[gate] を待った後で調べる）
  Object? error;

  /// 渡すと fetch はこれが完了するまで待つ（読み込み中を作る）
  Completer<void>? gate;

  @override
  Future<RecordStreakStatus> fetch(String clientId) async {
    fetchedClientIds.add(clientId);
    final pending = gate;
    if (pending != null) await pending.future;
    final failure = error;
    if (failure != null) throw failure;
    final result = results[clientId];
    if (result == null) throw StateError('結果を決めていない client id: $clientId');
    return result;
  }
}
