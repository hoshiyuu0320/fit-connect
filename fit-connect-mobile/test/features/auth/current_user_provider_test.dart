import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart' as supabase;
import 'package:fit_connect_mobile/features/auth/data/client_repository.dart';
import 'package:fit_connect_mobile/features/auth/models/client_model.dart';
import 'package:fit_connect_mobile/features/auth/providers/auth_provider.dart';
import 'package:fit_connect_mobile/features/auth/providers/current_user_provider.dart';

import '../../shared/fake_supabase_rest_server.dart';

const _userId = '22222222-2222-2222-2222-222222222222';
const _trainerId = '11111111-1111-1111-1111-111111111111';
const _clientsPath = '/rest/v1/clients';

const _user = supabase.User(
  id: _userId,
  appMetadata: {},
  userMetadata: {},
  aud: 'authenticated',
  createdAt: '2026-01-01T00:00:00Z',
);

/// build() が固定のユーザー（[user] が null なら未ログイン）を返す認証。Supabase には出ない
class _FakeAuth extends AuthNotifier {
  _FakeAuth(this.user);

  final supabase.User? user;

  @override
  Future<supabase.User?> build() async => user;
}

/// clients の1行（PostgREST の応答）
Map<String, dynamic> _clientRow() => {
      'client_id': _userId,
      'name': 'テスト太郎',
      'email': 'taro@example.com',
      'trainer_id': _trainerId,
      'gender': 'male',
      'age': 30,
      'height': 170.5,
      'initial_weight': 70.0,
      'target_weight': 65.0,
      'goal_deadline': '2026-12-31T00:00:00Z',
      'goal_description': '体重を落とす',
      'goal_set_at': '2026-09-01T00:00:00Z',
      'goal_achieved_at': null,
      'profile_image_url': null,
      'created_at': '2026-09-01T00:00:00Z',
    };

/// currentClientProvider は「行が無い」ときだけ null を返す。
/// 取得に失敗した（オフライン・5xx・JSON の不整合）ときは AsyncError にする。
/// null にすると app.dart が「残ったセッション」とみなしてサインアウトしてしまうため。
void main() {
  late FakeSupabaseRestServer server;
  late supabase.SupabaseClient client;

  setUp(() async {
    server = await FakeSupabaseRestServer.start();
    client = server.client();
  });

  tearDown(() async {
    await client.dispose();
    await server.close();
  });

  ProviderContainer containerFor({bool signedIn = true}) {
    final container = ProviderContainer(
      overrides: [
        authNotifierProvider.overrideWith(
          () => _FakeAuth(signedIn ? _user : null),
        ),
        clientRepositoryProvider.overrideWithValue(ClientRepository(client)),
      ],
    );
    addTearDown(container.dispose);
    // autoDispose なので、読む間は購読して生かしておく（画面が watch している状態）
    container.listen(currentClientProvider, (_, __) {});
    return container;
  }

  group('currentClientProvider', () {
    test('clients の行がある: Client を返し、本人の client_id で絞って問い合わせる', () async {
      server.respond(_clientsPath, [_clientRow()]);
      final container = containerFor();

      final result = await container.read(currentClientProvider.future);

      expect(result, isNotNull);
      expect(result!.clientId, _userId);
      expect(result.trainerId, _trainerId);
      expect(result.name, 'テスト太郎');
      expect(server.requests, hasLength(1));
      final request = server.requests.single;
      expect(request.method, 'GET');
      expect(request.path, _clientsPath);
      expect(request.query['client_id'], 'eq.$_userId');
    });

    test('clients の行が無い（空配列）: null を返す', () async {
      server.respond(_clientsPath, <Object>[]);
      final container = containerFor();

      expect(await container.read(currentClientProvider.future), isNull);
      // エラーではなく「値が null」
      expect(container.read(currentClientProvider), isA<AsyncData<Client?>>());
      // 問い合わせた上で、行が無かった
      expect(server.requests, hasLength(1));
    });

    test('サーバーエラー（503）: null にせず AsyncError にする', () async {
      server.respond(
        _clientsPath,
        {'message': 'upstream unavailable'},
        status: 503,
      );
      final container = containerFor();

      await expectLater(
        container.read(currentClientProvider.future),
        throwsA(isA<Exception>()),
      );
      final state = container.read(currentClientProvider);
      expect(state, isA<AsyncError<Client?>>());
      expect(state.hasValue, isFalse);
      expect(server.requests, hasLength(1));
    });

    test('接続できない（接続拒否）: null にせず AsyncError にする', () async {
      // 待ち受けを止めてから取得する → 接続拒否（オフラインと同じく、応答が得られない）
      await server.close();
      final container = containerFor();

      await expectLater(
        container.read(currentClientProvider.future),
        throwsA(isA<Exception>()),
      );
      final state = container.read(currentClientProvider);
      expect(state, isA<AsyncError<Client?>>());
      expect(state.hasValue, isFalse);
      expect(server.requests, isEmpty);
    });

    test('行はあるが Client に変換できない JSON: null にせず AsyncError にする', () async {
      // 必須の trainer_id が無い（スキーマの不整合）。行が無いわけではない
      server.respond(_clientsPath, [_clientRow()..remove('trainer_id')]);
      final container = containerFor();

      await expectLater(
        container.read(currentClientProvider.future),
        throwsA(isA<Exception>()),
      );
      final state = container.read(currentClientProvider);
      expect(state, isA<AsyncError<Client?>>());
      expect(state.hasValue, isFalse);
      expect(server.requests, hasLength(1));
    });

    test('未ログイン: null を返し、問い合わせない', () async {
      final container = containerFor(signedIn: false);

      expect(await container.read(currentClientProvider.future), isNull);
      expect(container.read(currentClientProvider), isA<AsyncData<Client?>>());
      expect(server.requests, isEmpty);
    });

    test('取得失敗のあと invalidate で再取得すると Client が返る（再試行の動線）', () async {
      server.respond(
        _clientsPath,
        {'message': 'upstream unavailable'},
        status: 503,
      );
      final container = containerFor();
      await expectLater(
        container.read(currentClientProvider.future),
        throwsA(isA<Exception>()),
      );

      // 回線が戻った
      server.respond(_clientsPath, [_clientRow()]);
      container.invalidate(currentClientProvider);
      final result = await container.read(currentClientProvider.future);

      expect(result?.clientId, _userId);
      expect(server.requests, hasLength(2));
    });
  });
}
