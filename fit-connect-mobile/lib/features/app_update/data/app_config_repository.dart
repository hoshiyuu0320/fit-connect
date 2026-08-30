import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';

part 'app_config_repository.g.dart';

/// AppConfigRepositoryのProvider
@riverpod
AppConfigRepository appConfigRepository(AppConfigRepositoryRef ref) {
  return AppConfigRepository(SupabaseService.client);
}

/// アプリ全体設定（app_config 単一行テーブル・id=1 固定）。
/// スキーマ: supabase/migrations/20260829000100_create_app_config.sql
class AppConfig {
  const AppConfig({
    required this.minSupportedVersion,
    this.latestVersion,
    this.iosStoreUrl,
    this.androidStoreUrl,
    this.updateMessage,
  });

  /// サポートする最小アプリバージョン（semver: major.minor.patch）
  final String minSupportedVersion;

  /// 最新リリースバージョン（表示用・任意）
  final String? latestVersion;

  /// App Store の URL。NULL の場合ダイアログは文言のみ（ボタン無し）
  final String? iosStoreUrl;

  /// Google Play の URL。NULL の場合ダイアログは文言のみ（ボタン無し）
  final String? androidStoreUrl;

  /// 強制アップデートダイアログに表示する任意メッセージ。NULL ならデフォルト文言
  final String? updateMessage;

  factory AppConfig.fromMap(Map<String, dynamic> map) {
    return AppConfig(
      minSupportedVersion: map['min_supported_version'] as String? ?? '1.0.0',
      latestVersion: map['latest_version'] as String?,
      iosStoreUrl: map['ios_store_url'] as String?,
      androidStoreUrl: map['android_store_url'] as String?,
      updateMessage: map['update_message'] as String?,
    );
  }
}

/// アプリ全体設定（app_config）の取得を行うRepository
class AppConfigRepository {
  final SupabaseClient _supabase;

  AppConfigRepository(this._supabase);

  /// app_config（id=1 の単一行）を取得する。
  /// 行が存在しない場合は null。
  /// 通信失敗時は throw（呼び出し側で fail-open = 通常起動にする）。
  Future<AppConfig?> fetchAppConfig() async {
    final row = await _supabase
        .from('app_config')
        .select()
        .eq('id', 1)
        .maybeSingle();

    if (row == null) return null;
    return AppConfig.fromMap(row);
  }
}
