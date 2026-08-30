import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:fit_connect_mobile/features/app_update/data/app_config_repository.dart';

part 'force_update_provider.g.dart';

/// 現在のバージョン [current] が最低サポートバージョン [min] 未満なら true
/// （純粋関数、テスト容易性のため分離）。
/// - '+ビルド番号'（例: `1.0.0+12`）は比較前に除去する
/// - major.minor.patch を数値で比較する（文字列比較ではない）
/// - どちらかがパース不能な場合は false（fail-open = 更新を要求しない）
bool isUpdateRequired(String current, String min) {
  final currentParts = _parseVersionCore(current);
  final minParts = _parseVersionCore(min);
  if (currentParts == null || minParts == null) return false;

  for (var i = 0; i < 3; i++) {
    if (currentParts[i] < minParts[i]) return true;
    if (currentParts[i] > minParts[i]) return false;
  }
  // 完全一致はサポート範囲内
  return false;
}

/// バージョン文字列を `[major, minor, patch]` に分解する。
/// '+' 以降（ビルド番号）は無視。3要素の非負整数でなければ null。
List<int>? _parseVersionCore(String version) {
  final core = version.split('+').first.trim();
  final parts = core.split('.');
  if (parts.length != 3) return null;

  final numbers = <int>[];
  for (final part in parts) {
    final n = int.tryParse(part);
    if (n == null || n < 0) return null;
    numbers.add(n);
  }
  return numbers;
}

/// アプリのパッケージ情報（実行中バージョンの取得）。
/// 強制アップデート判定のほか、設定画面のバージョン表示でも使用する。
@riverpod
Future<PackageInfo> packageInfo(PackageInfoRef ref) {
  return PackageInfo.fromPlatform();
}

/// 強制アップデート判定 Provider。
/// 要更新の場合のみ [AppConfig] を返し、更新不要・app_config 行なしは null。
/// 通信例外はそのまま throw する（タイムアウト・fail-open 制御は
/// AppUpdateGate 側で行う）。
@riverpod
Future<AppConfig?> forceUpdate(ForceUpdateRef ref) async {
  final config =
      await ref.watch(appConfigRepositoryProvider).fetchAppConfig();
  if (config == null) return null;

  final info = await ref.watch(packageInfoProvider.future);
  if (!isUpdateRequired(info.version, config.minSupportedVersion)) {
    return null;
  }
  return config;
}
