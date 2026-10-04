import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/exercise_records/providers/exercise_records_provider.dart';
import 'package:fit_connect_mobile/features/goals/providers/goal_provider.dart';
import 'package:fit_connect_mobile/features/meal_records/providers/meal_records_provider.dart';
import 'package:fit_connect_mobile/features/home/providers/latest_trainer_comment_provider.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/onboarding_flow/providers/onboarding_flow_provider.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';
import 'package:fit_connect_mobile/features/sleep_records/models/sleep_record_model.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/sleep_records_provider.dart';
import 'package:fit_connect_mobile/features/weight_records/models/weight_record_model.dart';
import 'package:fit_connect_mobile/features/weight_records/providers/weight_records_provider.dart';
import 'package:fit_connect_mobile/shared/models/period_filter.dart';

/// ホーム画面のテストで共有する、プロバイダーの差し替えとサンプルデータ。
/// Supabase には出ない（すべて差し替える）。

/// 体重記録をそのまま返す
class FakeWeightRecordsForHome extends WeightRecords {
  FakeWeightRecordsForHome(this.data);

  final List<WeightRecord> data;

  @override
  Future<List<WeightRecord>> build({
    PeriodFilter period = PeriodFilter.month,
  }) async =>
      data;
}

DateTime _day(DateTime base, [int daysAgo = 0, int hour = 0, int minute = 0]) =>
    DateTime(base.year, base.month, base.day - daysAgo, hour, minute);

Client sampleClient({
  String name = '佐藤',
  DateTime? createdAt,
  double? initial = 61.0,
  double? target = 65.0,
  String? description = '筋肉をつけて体重を増やす',
  DateTime? deadline,
  DateTime? achievedAt,
}) {
  final now = DateTime.now();
  return Client(
    clientId: 'client-1',
    name: name,
    trainerId: 'trainer-1',
    initialWeight: initial,
    targetWeight: target,
    goalDeadline: deadline,
    goalDescription: description,
    goalAchievedAt: achievedAt,
    createdAt: createdAt ?? DateTime(now.year, now.month, now.day - 40),
  );
}

Trainer sampleTrainer({String name = '田中'}) =>
    Trainer(id: 'trainer-1', name: name);

WeightRecord sampleWeight({
  required String id,
  required double weight,
  required DateTime at,
}) {
  return WeightRecord(
    id: id,
    clientId: 'client-1',
    weight: weight,
    recordedAt: at,
    source: 'message',
    createdAt: at,
    updatedAt: at,
  );
}

Message sampleMessage({
  required String id,
  required String sender, // 'trainer' | 'client'
  required String content,
  required DateTime at,
  List<String>? tags,
  String? replyTo,
  List<String>? imageUrls,
}) {
  return Message(
    id: id,
    senderId: sender == 'trainer' ? 'trainer-1' : 'client-1',
    receiverId: sender == 'trainer' ? 'client-1' : 'trainer-1',
    senderType: sender,
    receiverType: sender == 'trainer' ? 'client' : 'trainer',
    content: content,
    tags: tags,
    replyToMessageId: replyTo,
    imageUrls: imageUrls,
    createdAt: at,
    isEdited: false,
    updatedAt: at,
  );
}

SessionModel sampleSession({
  required DateTime at,
  int minutes = 60,
  String status = 'confirmed',
  String? type = 'パーソナル',
}) {
  final now = DateTime.now();
  return SessionModel(
    id: 'session-1',
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: at,
    durationMinutes: minutes,
    status: status,
    sessionType: type,
    createdAt: now,
    updatedAt: now,
  );
}

SleepRecord sampleSleep({int? minutes = 450, WakeupRating? rating}) {
  final now = DateTime.now();
  return SleepRecord(
    id: 'sleep-1',
    clientId: 'client-1',
    recordedDate: '${now.year}-${now.month}-${now.day}',
    totalSleepMinutes: minutes,
    wakeupRating: rating,
    source: minutes == null ? SleepSource.manual : SleepSource.healthkit,
    createdAt: now,
    updatedAt: now,
  );
}

Future<T> never<T>() => Completer<T>().future;

/// ホームのプロバイダーをまとめて差し替える。
///
/// [loading] が true なら、すべて読み込み中のまま（未完了の Future）。
/// 各データは null / 空で「はじめて」の状態になる。
List<Override> homeOverrides({
  bool loading = false,
  Client? client,
  Client? goal,
  Trainer? trainer,
  WeightRecord? latestWeight,
  List<WeightRecord> weightHistory = const [],
  List<Message> messages = const [],
  bool messagesFail = false,
  SessionModel? nextSession,
  int meals = 0,
  int exerciseDays = 0,
  SleepRecord? sleep,
  bool messageSent = false,
}) {
  if (loading) {
    return [
      currentClientProvider.overrideWith((ref) => never<Client?>()),
      currentGoalProvider.overrideWith((ref) => never<Client?>()),
      trainerProfileProvider.overrideWith((ref) => never<Trainer?>()),
      latestWeightRecordProvider.overrideWith((ref) => never<WeightRecord?>()),
      weightRecordsProvider(period: PeriodFilter.threeMonths)
          .overrideWith(() => FakeWeightRecordsForHome(const [])),
      latestTrainerCommentProvider.overrideWith((ref) => never<LatestTrainerComment?>()),
      nextSessionProvider.overrideWith((ref) => never<SessionModel?>()),
      upcomingSessionsProvider.overrideWith((ref) => never<List<SessionModel>>()),
      todayMealCountProvider.overrideWith((ref) => never<int>()),
      weeklyExerciseCountProvider.overrideWith((ref) => never<int>()),
      todaySleepRecordProvider.overrideWith((ref) => never<SleepRecord?>()),
      hasSentFirstMessageProvider.overrideWith((ref) => never<bool>()),
    ];
  }
  return [
    currentClientProvider.overrideWith((ref) async => client),
    currentGoalProvider.overrideWith((ref) async => goal),
    trainerProfileProvider.overrideWith((ref) async => trainer),
    latestWeightRecordProvider.overrideWith((ref) async => latestWeight),
    weightRecordsProvider(period: PeriodFilter.threeMonths)
        .overrideWith(() => FakeWeightRecordsForHome(weightHistory)),
    latestTrainerCommentProvider.overrideWith(
      (ref) async => messagesFail
          ? throw StateError('failed to load messages')
          : findLatestTrainerComment(messages),
    ),
    nextSessionProvider.overrideWith((ref) async => nextSession),
    upcomingSessionsProvider
        .overrideWith((ref) async => nextSession == null ? [] : [nextSession]),
    pastSessionsProvider.overrideWith((ref) async => []),
    todayMealCountProvider.overrideWith((ref) async => meals),
    weeklyExerciseCountProvider.overrideWith((ref) async => exerciseDays),
    todaySleepRecordProvider.overrideWith((ref) async => sleep),
    hasSentFirstMessageProvider.overrideWith((ref) async => messageSent),
  ];
}

/// 目標に向けた体重・メッセージ・予定・記録がそろった通常の日のサンプル。
List<Override> normalHomeOverrides({DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(today.year, today.month, today.day);
  final session = d.add(const Duration(days: 2, hours: 19));
  return homeOverrides(
    client: sampleClient(),
    goal: sampleClient(deadline: DateTime(today.year, 12, 31)),
    trainer: sampleTrainer(),
    latestWeight: sampleWeight(id: 'w1', weight: 62.4, at: _day(d, 0, 7, 30)),
    weightHistory: [
      sampleWeight(id: 'w1', weight: 62.4, at: _day(d, 0, 7, 30)),
      sampleWeight(id: 'w0', weight: 62.3, at: _day(d, 2, 7, 25)),
    ],
    messages: [
      sampleMessage(
        id: 'm1',
        sender: 'client',
        content: '朝食です',
        at: _day(d, 0, 8, 50),
        tags: ['#食事:朝食'],
      ),
      sampleMessage(
        id: 'm2',
        sender: 'trainer',
        content: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
        at: _day(d, 0, 9, 10),
        replyTo: 'm1',
      ),
    ],
    nextSession: sampleSession(at: session),
    meals: 2,
    exerciseDays: 3,
    sleep: sampleSleep(),
    messageSent: true,
  );
}

/// 390 × 844 に [child] を置いて pump する（ライト/ダーク・文字拡大つき。
/// 上のセーフエリア 47 と、ナビぶんの下余白 121 を再現する）。
Future<void> pumpHome(
  WidgetTester tester,
  Widget child, {
  required List<Override> overrides,
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  bool settle = true,
}) async {
  tester.view.physicalSize = size * 3;
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode:
            brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, c) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 47, bottom: 121),
          ),
          child: c!,
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }
}
