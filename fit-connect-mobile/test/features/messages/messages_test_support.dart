import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;

import 'package:fit_connect_mobile/core/theme/app_theme.dart';
import 'package:fit_connect_mobile/features/auth/models/trainer_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';
import 'package:fit_connect_mobile/features/messages/models/message_model.dart';
import 'package:fit_connect_mobile/features/messages/presentation/screens/message_screen.dart';
import 'package:fit_connect_mobile/features/messages/providers/messages_provider.dart';
import 'package:fit_connect_mobile/features/messages/providers/paginated_messages_state.dart';
import 'package:fit_connect_mobile/features/subscription/providers/ai_features_enabled_provider.dart';
import 'package:fit_connect_mobile/shared/widgets/fc/fc.dart';

/// メッセージ画面のテスト用の部品（ネットワークに出ない）。

const String testClientId = 'client-1';
const String testTrainerId = 'trainer-1';

/// 自分（クライアント）か、トレーナーのメッセージを作る
Message testMessage({
  required String id,
  required bool mine,
  required String content,
  required DateTime at,
  List<String>? tags,
  List<String>? imageUrls,
  String? replyTo,
  bool isEdited = false,
}) {
  return Message(
    id: id,
    senderId: mine ? testClientId : testTrainerId,
    receiverId: mine ? testTrainerId : testClientId,
    senderType: mine ? 'client' : 'trainer',
    receiverType: mine ? 'trainer' : 'client',
    content: content,
    imageUrls: imageUrls,
    tags: tags,
    replyToMessageId: replyTo,
    createdAt: at,
    isEdited: isEdited,
    updatedAt: at,
  );
}

class FakeMessages extends PaginatedMessages {
  FakeMessages(this.messages, {this.hasMore = false});

  final List<Message> messages;
  final bool hasMore;

  /// 送信されたメッセージの本文（テストで確かめる）
  static final List<String> sent = [];

  @override
  Future<PaginatedMessagesState> build() async => PaginatedMessagesState(
        messages: messages,
        hasMore: hasMore,
        isLoadingMore: false,
      );

  @override
  Future<void> markConversationAsRead() async {}

  @override
  Future<void> sendMessage({
    required String content,
    List<String>? imageUrls,
    List<String>? tags,
    String? replyToMessageId,
    Map<String, dynamic>? metadata,
  }) async {
    sent.add(content);
  }
}

class NeverMessages extends PaginatedMessages {
  @override
  Future<PaginatedMessagesState> build() =>
      Completer<PaginatedMessagesState>().future;

  @override
  Future<void> markConversationAsRead() async {}
}

class FailingMessages extends PaginatedMessages {
  @override
  Future<PaginatedMessagesState> build() async =>
      throw StateError('failed to load messages');

  @override
  Future<void> markConversationAsRead() async {}
}

class FakeAuth extends AuthNotifier {
  @override
  Future<supabase.User?> build() async => const supabase.User(
        id: testClientId,
        appMetadata: {},
        userMetadata: {},
        aud: 'authenticated',
        createdAt: '2026-01-01T00:00:00Z',
      );
}

enum FakeThread { messages, loading, error }

List<Override> messageScreenOverrides({
  List<Message> messages = const [],
  FakeThread thread = FakeThread.messages,
  String trainerName = '田中トレーナー',
  bool aiEnabled = false,
  bool hasMore = false,
}) {
  return [
    authNotifierProvider.overrideWith(() => FakeAuth()),
    trainerProfileProvider.overrideWith(
      (ref) async => Trainer(id: testTrainerId, name: trainerName),
    ),
    paginatedMessagesProvider.overrideWith(
      () => switch (thread) {
        FakeThread.loading => NeverMessages(),
        FakeThread.error => FailingMessages(),
        FakeThread.messages => FakeMessages(messages, hasMore: hasMore),
      },
    ),
    aiFeaturesEnabledProvider.overrideWith((ref) async => aiEnabled),
  ];
}

/// 実機と同じく、下部ナビ（FcBottomNavLayout）の中にメッセージ画面を置いて pump する。
Future<void> pumpMessageScreen(
  WidgetTester tester, {
  List<Override> overrides = const [],
  Brightness brightness = Brightness.light,
  double textScale = 1.0,
  Size size = const Size(390, 844),
  EdgeInsets viewPadding = EdgeInsets.zero,
  double keyboardHeight = 0,
  String? initialDraft,
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
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            // キーボード表示中は padding.bottom が 0 になる（実機と同じ）
            padding: keyboardHeight > 0
                ? viewPadding.copyWith(bottom: 0)
                : viewPadding,
            viewPadding: viewPadding,
            viewInsets: EdgeInsets.only(bottom: keyboardHeight),
          ),
          child: child!,
        ),
        home: FcBottomNavLayout(
          body: Scaffold(body: MessageScreen(initialDraft: initialDraft)),
          bottomNav: FcBottomNav(
            currentIndex: 1,
            onTap: (_) {},
            items: const [
              FcBottomNavItem(icon: LucideIcons.home, label: 'ホーム'),
              FcBottomNavItem(icon: LucideIcons.messageSquare, label: 'メッセージ'),
              FcBottomNavItem(icon: LucideIcons.dumbbell, label: 'プラン'),
              FcBottomNavItem(icon: LucideIcons.barChart2, label: '記録'),
              FcBottomNavItem(icon: LucideIcons.settings, label: '設定'),
            ],
          ),
        ),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

/// 正本 `ThreadMorning` + `ThreadEvening` と同じ内容のサンプル（今日・昨日の日付で作る）
List<Message> sampleThread({DateTime? now}) {
  final today = now ?? DateTime.now();
  final d = DateTime(today.year, today.month, today.day);
  DateTime at(int daysAgo, int h, int m) =>
      d.subtract(Duration(days: daysAgo)).add(Duration(hours: h, minutes: m));

  return [
    testMessage(
      id: 'm1',
      mine: true,
      content: '#運動:有酸素 ランニング 5.0 km · 30分\nいつもより少し長めに走りました。',
      tags: const ['#運動:有酸素'],
      at: at(1, 18, 20),
    ),
    testMessage(
      id: 'm2',
      mine: false,
      content: 'いいペースですね。翌日は脚の張りを見ながら、ストレッチも入れてみてください。',
      at: at(1, 19, 5),
    ),
    testMessage(
      id: 'm3',
      mine: true,
      content: '#体重 62.4 kg',
      tags: const ['#体重'],
      at: at(0, 7, 30),
    ),
    testMessage(
      id: 'm4',
      mine: true,
      content: '#食事:朝食 ごはん・卵・ヨーグルト',
      tags: const ['#食事:朝食'],
      at: at(0, 8, 10),
    ),
    testMessage(
      id: 'm5',
      mine: false,
      content: '朝食の記録、ありがとうございます。たんぱく質がとれていて良いですね。今日も自分のペースで。',
      at: at(0, 9, 10),
    ),
    testMessage(
      id: 'm6',
      mine: true,
      content: 'ありがとうございます。昼もたんぱく質を意識してみます。',
      replyTo: 'm5',
      isEdited: true,
      at: at(0, 9, 24),
    ),
    testMessage(
      id: 'm7',
      mine: true,
      content: '本日のワークアウトプラン「上半身」を達成しました！\n\n🔥 消費カロリー: 280kcal\n💬 肩の動きがよくなってきました。',
      tags: const ['#運動:完了'],
      at: at(0, 18, 40),
    ),
    testMessage(
      id: 'm8',
      mine: false,
      content: 'お疲れさまでした。最後のセットが重いときは、重さはそのままで回数を10回にしてみましょう。',
      at: at(0, 19, 12),
    ),
  ];
}
