import 'package:flutter/foundation.dart';
import 'package:fit_connect_mobile/services/supabase_service.dart';
import 'package:fit_connect_mobile/shared/storage/storage_value_resolver.dart';

/// Supabase Storage の署名 URL メモリキャッシュ。
///
/// - キーは `bucket/path`
/// - TTL 3600 秒で発行し、有効期限の残りが約5分を切ったら再発行する
///   （表示中に URL が失効しないようマージンを持たせる）
/// - 発行失敗時は null（呼び出し側はエラーフォールバック表示）
/// - 発行失敗は 30 秒間ネガティブキャッシュし、同一キーの再要求は即 null
///   （オフライン時等の失敗リクエスト連発を抑制。経過後は再試行可）
class SignedUrlCache {
  SignedUrlCache._();

  /// アプリ全体で共有するシングルトン
  static final SignedUrlCache instance = SignedUrlCache._();

  /// 署名 URL の有効期間（秒）
  static const int signedUrlTtlSeconds = 3600;

  /// 残り有効期間がこの値を切ったら再発行する
  static const Duration refreshMargin = Duration(minutes: 5);

  /// 発行失敗のネガティブキャッシュ期間。この間は同一キーの再発行を試みない
  static const Duration negativeCacheTtl = Duration(seconds: 30);

  final Map<String, _SignedUrlEntry> _entries = {};

  /// 同一キーの並列リクエストで createSignedUrl を多重発行しないための in-flight 共有
  final Map<String, Future<String?>> _inflight = {};

  /// 発行に失敗したキーと失敗時刻（ネガティブキャッシュ）
  final Map<String, DateTime> _failedAt = {};

  /// DB に保存された Storage 値を表示用 URL に解決する。
  /// - 外部 URL（Google 等）→ そのまま返す
  /// - バケット相対パス / レガシー Storage URL → 署名 URL（失敗時 null）
  /// - null / 空 → null
  Future<String?> resolveUrl(String? value, String bucket) {
    final resolved = resolveStorageValue(value, bucket);
    if (resolved.isExternal) return Future.value(resolved.externalUrl);
    final path = resolved.path;
    if (path == null) return Future.value(null);
    return getSignedUrl(bucket, path);
  }

  /// `bucket/path` の署名 URL を取得する（キャッシュ有効ならそれを返す）
  Future<String?> getSignedUrl(String bucket, String path) {
    final key = '$bucket/$path';
    final now = DateTime.now();
    final entry = _entries[key];
    if (entry != null && entry.expiresAt.isAfter(now.add(refreshMargin))) {
      return Future.value(entry.url);
    }

    // 直近の発行失敗から一定時間はネガティブキャッシュ: 再発行を試みず、
    // 期限内の旧 URL があればそれを、なければ null を即返す
    final failedAt = _failedAt[key];
    if (failedAt != null && now.difference(failedAt) < negativeCacheTtl) {
      if (entry != null && entry.expiresAt.isAfter(now)) {
        return Future.value(entry.url);
      }
      return Future.value(null);
    }

    final inflight = _inflight[key];
    if (inflight != null) return inflight;

    final future = _issue(bucket, path, key);
    _inflight[key] = future;
    return future;
  }

  Future<String?> _issue(String bucket, String path, String key) async {
    try {
      final url = await SupabaseService.client.storage
          .from(bucket)
          .createSignedUrl(path, signedUrlTtlSeconds);
      _entries[key] = _SignedUrlEntry(
        url,
        DateTime.now().add(const Duration(seconds: signedUrlTtlSeconds)),
      );
      _failedAt.remove(key);
      return url;
    } catch (e) {
      // 存在しないオブジェクト（Seed の架空パス等）や通信エラーでは例外を投げず null。
      // 失敗はネガティブキャッシュに記録し、一定時間は再発行を抑制する。
      // 再発行に失敗しても期限内の旧 URL が残っていればそれを返す（表示継続を優先）
      debugPrint('[SignedUrlCache] createSignedUrl failed: $key ($e)');
      _failedAt[key] = DateTime.now();
      final entry = _entries[key];
      if (entry != null && entry.expiresAt.isAfter(DateTime.now())) {
        return entry.url;
      }
      return null;
    } finally {
      _inflight.remove(key);
    }
  }

  /// キャッシュを全破棄（ログアウト時等）
  void clear() {
    _entries.clear();
    _failedAt.clear();
  }
}

class _SignedUrlEntry {
  final String url;
  final DateTime expiresAt;

  const _SignedUrlEntry(this.url, this.expiresAt);
}
