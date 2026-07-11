import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'account_deletion_repository.g.dart';

/// AccountDeletionRepositoryのProvider
@riverpod
AccountDeletionRepository accountDeletionRepository(
    AccountDeletionRepositoryRef ref) {
  return AccountDeletionRepository(SupabaseService.client);
}

/// アカウント削除（delete-account Edge Function 呼び出し）を行うRepository
class AccountDeletionRepository {
  final SupabaseClient _supabase;

  AccountDeletionRepository(this._supabase);

  /// delete-account Edge Function を呼び出してアカウントを完全削除する
  ///
  /// FunctionsClient は現在のセッションの Authorization ヘッダを自動付与するため、
  /// 削除対象の指定は不要（Edge Function 側が JWT からユーザーを特定する）。
  /// 失敗時は例外を投げる（呼び出し元で再試行可能）。
  Future<void> deleteAccount() async {
    try {
      final response = await _supabase.functions.invoke('delete-account');
      final data = response.data;
      if (data is! Map || data['success'] != true) {
        throw Exception('アカウント削除に失敗しました');
      }
    } on FunctionException catch (e) {
      final details = e.details;
      final message = (details is Map && details['message'] != null)
          ? details['message']
          : (e.reasonPhrase ?? 'status ${e.status}');
      throw Exception('アカウント削除に失敗しました: $message');
    }
  }
}
