import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'consent_repository.g.dart';

/// ConsentRepositoryのProvider
@riverpod
ConsentRepository consentRepository(ConsentRepositoryRef ref) {
  return ConsentRepository(SupabaseService.client);
}

/// 同意記録（user_consents）の取得・保存を行うRepository
class ConsentRepository {
  /// 現行の規約・ポリシーのバージョン。
  /// Web側 fit-connect/src/lib/supabase/saveUserConsents.ts の CONSENT_VERSION と
  /// 必ず一致させること（規約改定時は両方を更新する）。
  static const consentVersion = '2026-07-12';

  /// 同意が必要なドキュメント一覧（user_consents.document の値）
  static const requiredDocuments = ['terms', 'privacy', 'ai_processing'];

  final SupabaseClient _supabase;

  ConsentRepository(this._supabase);

  /// 現行バージョン（[consentVersion]）の同意が
  /// [requiredDocuments] すべてについて記録済みかを返す。
  Future<bool> hasCurrentConsent(String userId) async {
    final rows = await _supabase
        .from('user_consents')
        .select('document')
        .eq('user_id', userId)
        .eq('version', consentVersion);

    final consented = rows.map((row) => row['document'] as String?).toSet();
    return requiredDocuments.every(consented.contains);
  }

  /// 現行バージョンへの同意を全ドキュメント一括でINSERTする。
  /// 失敗時は throw（呼び出し側でリトライ導線を出す）。
  Future<void> recordConsent(String userId) async {
    await _supabase.from('user_consents').insert([
      for (final document in requiredDocuments)
        {
          'user_id': userId,
          'user_type': 'client',
          'document': document,
          'version': consentVersion,
        },
    ]);
  }
}
