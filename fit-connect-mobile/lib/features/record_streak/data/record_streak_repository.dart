import 'package:flutter_riverpod/flutter_riverpod.dart' show Ref;
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

import 'package:fit_connect_mobile/features/record_streak/models/record_streak_status.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'record_streak_repository.g.dart';

/// RecordStreakRepositoryのProvider
@riverpod
RecordStreakRepository recordStreakRepository(Ref ref) {
  return RecordStreakRepository(SupabaseService.client);
}

/// 記録の連続（DB の関数 get_record_streak）の取得を行うRepository（設計 §5.1・§6.1）。
///
/// 関数は SECURITY INVOKER で、呼んだ人の RLS がそのまま効く。他人の client_id を渡しても、
/// 記録が見えないので (今日, false, 0) が返る（設計 §5.2）
class RecordStreakRepository {
  RecordStreakRepository(this._supabase);

  final SupabaseClient _supabase;

  static const _rpc = 'get_record_streak';

  /// [clientId] の記録の連続を取得する。
  ///
  /// 関数は記録が無くても必ず 1 行返す（RETURNS TABLE なので応答は配列）ので、先頭の行を読む。
  /// 行が無ければ StateError。通信・関数のエラー（関数がまだ無い DB など）はそのまま投げる
  Future<RecordStreakStatus> fetch(String clientId) async {
    final response = await _supabase.rpc(
      _rpc,
      params: {'p_client_id': clientId},
    );
    final rows = response as List;
    if (rows.isEmpty) {
      throw StateError('$_rpc が行を返しませんでした');
    }
    return RecordStreakStatus.fromRow(rows.first as Map<String, dynamic>);
  }
}
