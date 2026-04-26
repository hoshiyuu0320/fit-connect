import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';

part 'health_provider.g.dart';

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

  @override
  Future<HealthSettingsState> build() async {
    final prefs = await SharedPreferences.getInstance();
    return HealthSettingsState(
      isEnabled: prefs.getBool(_keyEnabled) ?? false,
      isWeightEnabled: prefs.getBool(_keyWeightEnabled) ?? false,
      isSleepEnabled: prefs.getBool(_keySleepEnabled) ?? false,
      isMorningDialogEnabled: prefs.getBool(_keyMorningDialogEnabled) ?? true,
      lastSyncAt: _parseDateTime(prefs.getString(_keyLastSync)),
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

  /// 最終同期日時を更新
  Future<void> updateLastSyncAt(DateTime dateTime) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyLastSync, dateTime.toIso8601String());
    ref.invalidateSelf();
  }

  DateTime? _parseDateTime(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}

/// 設定状態
class HealthSettingsState {
  final bool isEnabled;
  final bool isWeightEnabled;
  final bool isSleepEnabled;
  final bool isMorningDialogEnabled;
  final DateTime? lastSyncAt;

  const HealthSettingsState({
    required this.isEnabled,
    required this.isWeightEnabled,
    required this.isSleepEnabled,
    required this.isMorningDialogEnabled,
    this.lastSyncAt,
  });

  HealthSettingsState copyWith({
    bool? isEnabled,
    bool? isWeightEnabled,
    bool? isSleepEnabled,
    bool? isMorningDialogEnabled,
    DateTime? lastSyncAt,
  }) =>
      HealthSettingsState(
        isEnabled: isEnabled ?? this.isEnabled,
        isWeightEnabled: isWeightEnabled ?? this.isWeightEnabled,
        isSleepEnabled: isSleepEnabled ?? this.isSleepEnabled,
        isMorningDialogEnabled:
            isMorningDialogEnabled ?? this.isMorningDialogEnabled,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
}
