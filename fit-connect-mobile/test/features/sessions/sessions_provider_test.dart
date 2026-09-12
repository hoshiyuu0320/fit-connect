import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fit_connect_mobile/features/sessions/models/session_model.dart';
import 'package:fit_connect_mobile/features/sessions/providers/sessions_provider.dart';

/// テスト用のSessionModelを組み立てるヘルパー。
/// ※ 日時のフィクスチャは必ず DateTime.now() 基準の相対値で作ること
SessionModel _makeSession({
  required String id,
  required Duration fromNow,
  required String status,
  int durationMinutes = 60,
}) {
  final now = DateTime.now();
  return SessionModel(
    id: id,
    trainerId: 'trainer-1',
    clientId: 'client-1',
    sessionDate: now.add(fromNow),
    durationMinutes: durationMinutes,
    status: status,
    createdAt: now,
    updatedAt: now,
  );
}

/// upcomingSessions を差し替えた ProviderContainer を作る
ProviderContainer _containerWithUpcoming(List<SessionModel> sessions) {
  final container = ProviderContainer(
    overrides: [
      upcomingSessionsProvider.overrideWith((ref) async => sessions),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  group('nextSessionProvider', () {
    test('「今後」の先頭をそのまま返す', () async {
      final head = _makeSession(
        id: 'session-1',
        fromNow: const Duration(days: 1),
        status: 'confirmed',
      );
      final container = _containerWithUpcoming([
        head,
        _makeSession(
          id: 'session-2',
          fromNow: const Duration(days: 5),
          status: 'scheduled',
        ),
      ]);

      final next = await container.read(nextSessionProvider.future);
      expect(next?.id, head.id);
    });

    test('先頭がキャンセル済みなら次の生きている予定を返す', () async {
      // 未来のキャンセルは「今後」に残る（一覧では見せる）が、
      // ホームの「次回のセッション」としては読み飛ばす
      final container = _containerWithUpcoming([
        _makeSession(
          id: 'cancelled-1',
          fromNow: const Duration(days: 1),
          status: 'cancelled',
        ),
        _makeSession(
          id: 'alive-1',
          fromNow: const Duration(days: 4),
          status: 'scheduled',
        ),
      ]);

      final next = await container.read(nextSessionProvider.future);
      expect(next?.id, 'alive-1');
    });

    test('キャンセル/完了しか無ければnull（＝ホームは「予定なし」）', () async {
      final container = _containerWithUpcoming([
        _makeSession(
          id: 'cancelled-1',
          fromNow: const Duration(days: 1),
          status: 'cancelled',
        ),
        _makeSession(
          id: 'completed-1',
          fromNow: const Duration(days: 2),
          status: 'completed',
        ),
      ]);

      expect(await container.read(nextSessionProvider.future), isNull);
    });

    test('「今後」が空ならnull', () async {
      final container = _containerWithUpcoming([]);

      expect(await container.read(nextSessionProvider.future), isNull);
    });

    test('開始済みで終了前のセッションは次回として返る（開催中に消えない）', () async {
      // 18:00開始60分を18:01に見た状況
      final ongoing = _makeSession(
        id: 'ongoing-1',
        fromNow: const Duration(minutes: -1),
        status: 'confirmed',
      );
      final container = _containerWithUpcoming([ongoing]);

      final next = await container.read(nextSessionProvider.future);
      expect(next?.id, 'ongoing-1');
      expect(next?.isUpcoming, isTrue);
    });
  });
}
