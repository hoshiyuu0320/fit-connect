import 'dart:convert';
import 'dart:io';

import 'package:supabase_flutter/supabase_flutter.dart' show SupabaseClient;

/// 偽サーバーが受け取った1リクエスト
class RecordedRequest {
  RecordedRequest(this.method, this.uri, this.body);

  final String method;
  final Uri uri;

  /// JSON ボディ（GET など本文なしは null）
  final Object? body;

  String get path => uri.path;
  Map<String, String> get query => uri.queryParameters;
}

/// PostgREST を模した偽サーバー（dart:io の HttpServer。127.0.0.1 の空きポートで待ち受ける）。
///
/// Repository に本物の SupabaseClient（[client]）を渡し、組み立てられた HTTP リクエスト
/// （RPC の引数名・フィルタ・並び順・件数）と、応答に対する Repository の振る舞いを検証するために使う。
/// パス（'/rest/v1/rpc/get_my_sessions' など）ごとに応答（ステータス + JSON）を [respond] で登録する。
/// 未登録のパスには 404（関数・テーブルなし）を返す。
class FakeSupabaseRestServer {
  FakeSupabaseRestServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;

  /// 受け取った順のリクエスト
  final requests = <RecordedRequest>[];

  final _responses = <String, ({int status, Object? json})>{};

  static Future<FakeSupabaseRestServer> start() async =>
      FakeSupabaseRestServer._(
          await HttpServer.bind(InternetAddress.loopbackIPv4, 0));

  /// [path] への応答を登録する（同じパスは上書き）
  void respond(String path, Object? json, {int status = 200}) =>
      _responses[path] = (status: status, json: json);

  /// このサーバーへ向けた SupabaseClient（使い終わったら dispose すること）
  SupabaseClient client() =>
      SupabaseClient('http://127.0.0.1:${_server.port}', 'test-anon-key');

  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    final text = await utf8.decoder.bind(request).join();
    requests.add(RecordedRequest(
      request.method,
      request.uri,
      text.isEmpty ? null : jsonDecode(text),
    ));

    final response = _responses[request.uri.path] ??
        (
          status: 404,
          json: {
            'code': 'PGRST202',
            'message': 'not registered in FakeSupabaseRestServer',
          },
        );
    request.response
      ..statusCode = response.status
      ..headers.contentType = ContentType.json
      ..write(jsonEncode(response.json));
    await request.response.close();
  }
}
