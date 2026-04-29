import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';

part 'health_provider.g.dart';

/// ヘルスケア同期の状態
enum HealthSyncStatus { idle, syncing, success, error }

/// HealthRepository のプロバイダ
@riverpod
HealthRepository healthRepository(HealthRepositoryRef ref) {
  return HealthRepository();
}

/// HealthKit 連携が利用可能かどうか
@riverpod
Future<bool> healthAvailable(HealthAvailableRef ref) async {
  final repo = ref.watch(healthRepositoryProvider);
  return repo.isAvailable();
}

/// ヘルスケア連携設定の状態管理
@riverpod
class HealthSettings extends _$HealthSettings {
  static const _keyEnabled = 'health_enabled';
  static const _keyWeightEnabled = 'health_weight_enabled';
  static const _keySleepEnabled = 'health_sleep_enabled';
  static const _keyMorningDialogEnabled = 'health_morning_dialog_enabled';
  static const _keyLastSync = 'health_last_sync';
  static const _keyLastSyncStatus = 'health_last_sync_status';
  static const _keyLastSyncError = 'health_last_sync_error';

  @override
  Future<HealthSettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    return HealthSettingsState(
      isEnabled: prefs.getBool(_keyEnabled) ?? false,
      isWeightEnabled: prefs.getBool(_keyWeightEnabled) ?? false,
      isSleepEnabled: prefs.getBool(_keySleepEnabled) ?? false,
      isMorningDialogEnabled: prefs.getBool(_keyMorningDialogEnabled) ?? true,
      lastSyncAt: _parseDateTime(prefs.getString(_keyLastSync)),
      lastSyncStatus: _parseStatus(prefs.getString(_keyLastSyncStatus)),
      lastSyncError: prefs.getString(_keyLastSyncError),
    );
  }

  /// マスター連携のON/OFF切替
  Future<bool> toggleEnabled(bool value) async {
    if (value) {
      final repo = ref.read(healthRepositoryProvider);
      final granted = await repo.requestPermission();
      if (!granted) return false;
    }

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyEnabled, value);
    if (!value) {
      await prefs.setBool(_keyWeightEnabled, false);
      await prefs.setBool(_keySleepEnabled, false);
    }
    ref.invalidateSelf();
    return true;
  }

  /// 体重データ連携のON/OFF切替
  Future<void> toggleWeightEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyWeightEnabled, value);
    ref.invalidateSelf();
  }

  /// 睡眠データ連携のON/OFF切替（ON時にSLEEP権限をリクエスト）
  Future<bool> toggleSleepEnabled(bool value) async {
    if (value) {
      final repo = ref.read(healthRepositoryProvider);
      final granted = await repo.requestPermission(includeSleep: true);
      if (!granted) return false;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keySleepEnabled, value);
    ref.invalidateSelf();
    return true;
  }

  /// 朝の目覚めダイアログのON/OFF切替
  Future<void> toggleMorningDialogEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_keyMorningDialogEnabled, value);
    ref.invalidateSelf();
  }

  /// 最終同期日時を更新（互換性維持のため残置。内部的には updateSyncResult を呼ぶ）
  Future<void> updateLastSyncAt(DateTime dateTime) async {
    await updateSyncResult(
      status: HealthSyncStatus.success,
      error: null,
      syncedAt: dateTime,
    );
  }

  /// 同期結果を保存（status / error / syncedAt をまとめて永続化）
  ///
  /// - status: 必須。idle/syncing/success/error
  /// - error: エラーメッセージ。success 時は null を渡してクリアする
  /// - syncedAt: 成功時のみ渡す。null の場合は lastSyncAt を更新しない
  Future<void> updateSyncResult({
    required HealthSyncStatus status,
    String? error,
    DateTime? syncedAt,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSyncStatus, status.name);

    if (error == null) {
      await prefs.remove(_keyLastSyncError);
    } else {
      await prefs.setString(_keyLastSyncError, error);
    }

    if (syncedAt != null) {
      await prefs.setString(_keyLastSync, syncedAt.toIso8601String());
    }
    ref.invalidateSelf();
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  HealthSyncStatus _parseStatus(String? value) {
    if (value == null) return HealthSyncStatus.idle;
    for (final s in HealthSyncStatus.values) {
      if (s.name == value) return s;
    }
    return HealthSyncStatus.idle;
  }
}

/// 設定状態
class HealthSettingsState {
  final bool isEnabled;
  final bool isWeightEnabled;
  final bool isSleepEnabled;
  final bool isMorningDialogEnabled;
  final DateTime? lastSyncAt;
  final HealthSyncStatus lastSyncStatus;
  final String? lastSyncError;

  const HealthSettingsState({
    required this.isEnabled,
    required this.isWeightEnabled,
    required this.isSleepEnabled,
    required this.isMorningDialogEnabled,
    this.lastSyncAt,
    this.lastSyncStatus = HealthSyncStatus.idle,
    this.lastSyncError,
  });

  HealthSettingsState copyWith({
    bool? isEnabled,
    bool? isWeightEnabled,
    bool? isSleepEnabled,
    bool? isMorningDialogEnabled,
    DateTime? lastSyncAt,
    HealthSyncStatus? lastSyncStatus,
    String? lastSyncError,
  }) =>
      HealthSettingsState(
        isEnabled: isEnabled ?? this.isEnabled,
        isWeightEnabled: isWeightEnabled ?? this.isWeightEnabled,
        isSleepEnabled: isSleepEnabled ?? this.isSleepEnabled,
        isMorningDialogEnabled:
            isMorningDialogEnabled ?? this.isMorningDialogEnabled,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        lastSyncStatus: lastSyncStatus ?? this.lastSyncStatus,
        lastSyncError: lastSyncError ?? this.lastSyncError,
      );
}
