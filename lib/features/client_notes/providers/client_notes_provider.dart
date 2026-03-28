import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/client_notes/models/client_note_model.dart';
import 'package:fit_connect_mobile/features/client_notes/data/client_note_repository.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

part 'client_notes_provider.g.dart';

/// ClientNoteRepositoryのProvider
@riverpod
ClientNoteRepository clientNoteRepository(ClientNoteRepositoryRef ref) {
  return ClientNoteRepository();
}

/// 共有済みカルテ一覧を取得するProvider
@riverpod
Future<List<ClientNote>> sharedClientNotes(SharedClientNotesRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final repository = ref.watch(clientNoteRepositoryProvider);
  return repository.getSharedNotes(clientId: clientId);
}
