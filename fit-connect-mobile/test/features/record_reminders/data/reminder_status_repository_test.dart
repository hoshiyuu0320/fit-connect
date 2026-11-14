import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show PostgrestException, SupabaseClient;
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:fit_connect_mobile/features/record_reminders/data/reminder_status_repository.dart';
import 'package:fit_connect_mobile/features/record_reminders/models/reminder_kind.dart';

import '../../../shared/fake_supabase_rest_server.dart';

const _clientId = '22222222-2222-2222-2222-222222222222';
const _weightPath = '/rest/v1/weight_records';
const _mealPath = '/rest/v1/meal_records';
const _assignmentsPath = '/rest/v1/workout_assignments';

/// workout_assignments に workout_plans(plan_type) を embed した1行
Map<String, dynamic> _assignmentRow(String assignedDate, String? planType) => {
      'assigned_date': assignedDate,
      'workout_plans': planType == null ? null : {'plan_type': planType},
    };

// 本物の SupabaseClient を偽サーバーへ向け、組み立てられる HTTP リクエスト（本人・日本時間の日の範囲・
// 時差付きの境界・列・絞り込み）と、応答に対する振る舞いを確かめる。
// embed（workout_plans の結合）そのものは偽サーバーでは評価されないので、select の指定と、
// embed された plan_type での絞り込みだけを確かめる。
void main() {
  late tz.Location tokyo;

  setUpAll(() {
    tzdata.initializeTimeZones();
    tokyo = tz.getLocation('Asia/Tokyo');
  });

  group('ReminderStatusRepository（偽サーバー経由）', () {
    late FakeSupabaseRestServer server;
    late SupabaseClient client;
    late ReminderStatusRepository repository;

    setUp(() async {
      server = await FakeSupabaseRestServer.start();
      client = server.client();
      repository = ReminderStatusRepository(client: client);
    });

    tearDown(() async {
      await client.dispose();
      await server.close();
    });

    /// [path] へのただ1つのリクエスト
    RecordedRequest requestTo(String path) =>
        server.requests.singleWhere((r) => r.path == path);

    group('fetchRecordedToday', () {
      test('本人・今日（日本時間）の範囲を時差付きの UTC・半開区間で読み、体重と食事の種類を返す', () async {
        server.respond(_weightPath, [
          {'id': 'w-1'},
        ]);
        server.respond(_mealPath, [
          {'meal_type': 'breakfast'},
          {'meal_type': 'dinner'},
          {'meal_type': 'breakfast'},
        ]);

        final recorded = await repository.fetchRecordedToday(
          clientId: _clientId,
          nowJst: tz.TZDateTime(tokyo, 2026, 11, 7, 10, 0),
        );

        expect(recorded, {
          ReminderKind.weight,
          ReminderKind.breakfast,
          ReminderKind.dinner,
        });
        expect(server.requests, hasLength(2));

        // 2026-11-07 00:00 JST = 2026-11-06 15:00 UTC 〜 2026-11-08 00:00 JST
        const bounds = [
          'gte.2026-11-06T15:00:00.000Z',
          'lt.2026-11-07T15:00:00.000Z',
        ];

        final weight = requestTo(_weightPath);
        expect(weight.method, 'GET');
        expect(weight.query['select'], 'id');
        expect(weight.query['client_id'], 'eq.$_clientId');
        expect(
          weight.uri.queryParametersAll['recorded_at'],
          unorderedEquals(bounds),
        );
        // 有無だけ分かればよいので1行まで
        expect(weight.query['limit'], '1');

        final meal = requestTo(_mealPath);
        expect(meal.method, 'GET');
        expect(meal.query['select'], 'meal_type');
        expect(meal.query['client_id'], 'eq.$_clientId');
        expect(
          meal.uri.queryParametersAll['recorded_at'],
          unorderedEquals(bounds),
        );
        // 間食（snack）は読まない
        expect(meal.query['meal_type'], 'in.("breakfast","lunch","dinner")');
      });

      test('日付の変わり目: 00:30 JST は UTC では前日だが、日本時間のその日の範囲で読む', () async {
        server.respond(_weightPath, []);
        server.respond(_mealPath, []);

        await repository.fetchRecordedToday(
          clientId: _clientId,
          nowJst: tz.TZDateTime(tokyo, 2026, 11, 8, 0, 30),
        );

        for (final path in [_weightPath, _mealPath]) {
          expect(
            requestTo(path).uri.queryParametersAll['recorded_at'],
            unorderedEquals([
              'gte.2026-11-07T15:00:00.000Z',
              'lt.2026-11-08T15:00:00.000Z',
            ]),
            reason: path,
          );
        }
      });

      test('記録が無ければ空。間食しか無ければ空', () async {
        server.respond(_weightPath, []);
        server.respond(_mealPath, [
          {'meal_type': 'snack'},
        ]);

        final recorded = await repository.fetchRecordedToday(
          clientId: _clientId,
          nowJst: tz.TZDateTime(tokyo, 2026, 11, 7, 23, 59),
        );

        expect(recorded, isEmpty);
      });

      test('食事だけ（体重なし）', () async {
        server.respond(_weightPath, []);
        server.respond(_mealPath, [
          {'meal_type': 'lunch'},
        ]);

        final recorded = await repository.fetchRecordedToday(
          clientId: _clientId,
          nowJst: tz.TZDateTime(tokyo, 2026, 11, 7, 14, 0),
        );

        expect(recorded, {ReminderKind.lunch});
      });

      test('どちらかの読み取りに失敗したら投げる（呼び出し元が直前の結果に戻す）', () async {
        server.respond(_weightPath, {'message': 'upstream error'}, status: 503);
        server.respond(_mealPath, [
          {'meal_type': 'lunch'},
        ]);

        await expectLater(
          repository.fetchRecordedToday(
            clientId: _clientId,
            nowJst: tz.TZDateTime(tokyo, 2026, 11, 7, 10, 0),
          ),
          throwsA(isA<PostgrestException>()),
        );

        server.respond(_weightPath, []);
        server.respond(
          _mealPath,
          {'code': '42501', 'message': 'permission denied'},
          status: 401,
        );

        await expectLater(
          repository.fetchRecordedToday(
            clientId: _clientId,
            nowJst: tz.TZDateTime(tokyo, 2026, 11, 7, 10, 0),
          ),
          throwsA(isA<PostgrestException>()),
        );
      });
    });

    group('fetchPendingWorkoutDates', () {
      test('本人・pending・期間（両端を含む）で絞り、プランを embed してセルフガイドの日付だけ返す', () async {
        server.respond(_assignmentsPath, [
          _assignmentRow('2026-11-07', 'self_guided'),
          _assignmentRow('2026-11-08', 'session'),
          // プランを読めない行（RLS など）は除く（WorkoutRepository と同じ）
          _assignmentRow('2026-11-09', null),
          _assignmentRow('2026-11-10', 'self_guided'),
          _assignmentRow('2026-11-10', 'self_guided'),
          _assignmentRow('2026-11-13', 'self_guided'),
        ]);

        final dates = await repository.fetchPendingWorkoutDates(
          clientId: _clientId,
          fromDateKey: '2026-11-07',
          toDateKey: '2026-11-13',
        );

        expect(dates, {'2026-11-07', '2026-11-10', '2026-11-13'});

        final request = requestTo(_assignmentsPath);
        expect(request.method, 'GET');
        expect(
            request.query['select'], 'assigned_date,workout_plans(plan_type)');
        expect(request.query['client_id'], 'eq.$_clientId');
        expect(request.query['status'], 'eq.pending');
        expect(
          request.uri.queryParametersAll['assigned_date'],
          unorderedEquals(['gte.2026-11-07', 'lte.2026-11-13']),
        );
      });

      test('割り当てが無ければ空', () async {
        server.respond(_assignmentsPath, []);

        final dates = await repository.fetchPendingWorkoutDates(
          clientId: _clientId,
          fromDateKey: '2026-11-07',
          toDateKey: '2026-11-13',
        );

        expect(dates, isEmpty);
      });

      test('読み取りに失敗したら投げる', () async {
        server.respond(
          _assignmentsPath,
          {'message': 'upstream error'},
          status: 500,
        );

        await expectLater(
          repository.fetchPendingWorkoutDates(
            clientId: _clientId,
            fromDateKey: '2026-11-07',
            toDateKey: '2026-11-13',
          ),
          throwsA(isA<PostgrestException>()),
        );
      });
    });
  });
}
