import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/record_streak/domain/record_streak_view.dart';
import 'package:fit_connect_mobile/features/record_streak/providers/record_streak_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';

import '../../shared/fake_supabase_rest_server.dart';

const _clientId = '22222222-2222-2222-2222-222222222222';
const _sleepRecordsPath = '/rest/v1/sleep_records';
const _streakRpcPath = '/rest/v1/rpc/get_record_streak';

/// get_record_streak が返す行（DB の今日は 2026-11-23。昨日までは続いていない）
List<Map<String, dynamic>> _streakRows({required bool recordedToday}) => [
      {
        'as_of_date': '2026-11-23',
        'recorded_today': recordedToday,
        'streak_until_yesterday': 0,
      },
    ];

/// SleepRecords.upsertWakeupRating（目覚めの評価）のテスト。
///
/// SleepRecords は SupabaseService.client（= Supabase.instance.client）を直接使うので、Supabase を
/// 偽サーバー（FakeSupabaseRestServer）へ向けて初期化する。記録の連続（recordStreakProvider）も、
/// 本物の Repository で同じ偽サーバーから読む
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeSupabaseRestServer server;

  setUpAll(() async {
    // TestWidgetsFlutterBinding は HTTP をすべて 400 にする（HttpOverrides.global）。
    // 偽サーバー（127.0.0.1）へは本物の通信で届ける（外れるのは、このファイルの isolate だけ）
    HttpOverrides.global = null;
    server = await FakeSupabaseRestServer.start();
    SharedPreferences.setMockInitialValues({});
    // セッションなし・自動更新なし（auth は通信しない）
    await Supabase.initialize(
      url: server.url,
      anonKey: 'test-anon-key',
      authOptions: const FlutterAuthClientOptions(
        autoRefreshToken: false,
        localStorage: EmptyLocalStorage(),
      ),
    );
  });

  tearDownAll(() async {
    await Supabase.instance.dispose();
    await server.close();
  });

  test('目覚めの評価を付けると、記録の連続を読み直す（ホームを離れずに「これから」が「今日記録済み」になる）', () async {
    // 今日の睡眠の行はまだ無い（評価で manual の行を作る）。記録の連続は、今日まだで続いていない
    server
      ..respond(_sleepRecordsPath, [])
      ..respond(_streakRpcPath, _streakRows(recordedToday: false));
    final container = ProviderContainer(overrides: [
      currentClientIdProvider.overrideWith((ref) => _clientId),
    ]);
    addTearDown(container.dispose);
    // ホームの行と睡眠の一覧の代わりに購読して保つ（どちらも自動破棄）
    final sleepRecords = sleepRecordsProvider();
    container
      ..listen(recordStreakViewProvider, (_, __) {})
      ..listen(sleepRecords, (_, __) {});
    await container.read(recordStreakProvider.future);
    await container.read(sleepRecords.future);
    expect(
      container.read(recordStreakViewProvider),
      const AsyncData<RecordStreakView?>(RecordStreakNone()),
    );

    // 評価を保存すると、DB では今日記録済みになる（目覚めの評価は記録の連続に数える）
    server.respond(_streakRpcPath, _streakRows(recordedToday: true));
    await container.read(sleepRecords.notifier).upsertWakeupRating(
          recordedDate: '2026-11-23',
          rating: WakeupRating.refreshed,
        );
    await container.read(recordStreakProvider.future);
    // 睡眠の一覧の読み直し（invalidateSelf）も終わらせておく（偽サーバーを閉じる前に）
    await container.read(sleepRecords.future);

    expect(
      container.read(recordStreakViewProvider),
      const AsyncData<RecordStreakView?>(RecordStreakRecordedToday(days: 1)),
    );
    expect(
      server.requests.where((r) => r.path == _streakRpcPath),
      hasLength(2),
    );
    // 評価は今日の睡眠の行として保存した
    expect(
      server.requests
          .singleWhere((r) => r.method == 'POST' && r.path == _sleepRecordsPath)
          .body,
      {
        'client_id': _clientId,
        'recorded_date': '2026-11-23',
        'wakeup_rating': 3,
        'source': 'manual',
      },
    );
  });
}
