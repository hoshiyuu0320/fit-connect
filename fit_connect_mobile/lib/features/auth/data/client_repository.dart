import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'client_repository.g.dart';

/// ClientRepositoryのProvider
@riverpod
ClientRepository clientRepository(ClientRepositoryRef ref) {
  return ClientRepository(SupabaseService.client);
}

/// クライアント情報の取得・更新を行うRepository
class ClientRepository {
  final SupabaseClient _supabase;

  ClientRepository(this._supabase);

  /// クライアント情報を取得
  Future<Client?> fetchClient(String clientId) async {
    try {
      final response = await _supabase
          .from('clients')
          .select()
          .eq('client_id', clientId)
          .maybeSingle();

      if (response == null) return null;
      return Client.fromJson(response);
    } catch (e) {
      throw Exception('クライアント情報の取得に失敗しました: $e');
    }
  }

  /// クライアント名を更新
  Future<void> updateClientName(String clientId, String name) async {
    try {
      await _supabase.from('clients').update({
        'name': name,
      }).eq('client_id', clientId);
    } catch (e) {
      throw Exception('クライアント名の更新に失敗しました: $e');
    }
  }
}
