import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

class ClientNoteRepository {
  final _supabase = SupabaseService.client;

  /// 共有済みカルテ一覧を取得（クライアント用）
  Future<List<ClientNote>> getSharedNotes({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select()
        .eq('client_id', clientId)
        .eq('is_shared', true)
        .order('created_at', ascending: false);

    return (response as List).map((json) => ClientNote.fromJson(json)).toList();
  }

  /// 共有済みカルテ件数を取得（Home画面サマリー用、将来実装）
  Future<int> getSharedNotesCount({
    required String clientId,
  }) async {
    final response = await _supabase
        .from('client_notes')
        .select('id')
        .eq('client_id', clientId)
        .eq('is_shared', true);

    return (response as List).length;
  }
}
