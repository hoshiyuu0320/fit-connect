/// DB に保存された Storage 値の判定・パス抽出を行う純関数群。
///
/// Storage private 化に伴い、DB にはバケット相対パス
/// （例: `9d1ecf80-…/bad437a6-….jpg`）を保存する方針だが、
/// 既存行にはレガシーな公開 URL や Google アバター等の外部 URL が混在する。
/// 本ファイルの [resolveStorageValue] がその判定を一手に引き受ける。
///
/// Supabase 依存なしの純関数のみを置くこと（単体テスト対象）。
library;

/// [resolveStorageValue] の解決結果。
/// [path] と [externalUrl] は排他で、どちらも null なら「値なし」。
class ResolvedStorageValue {
  /// バケット相対パス（Storage 内を指す値の場合のみ非 null）。
  /// クエリ・フラグメントは除去済み。
  final String? path;

  /// Storage 外の URL（Google アバター等）。表示時はそのまま使う
  final String? externalUrl;

  /// 値に付いていた `#` フラグメントの生値（client-notes の元ファイル名等）。
  /// デコードは [decodedFragment] で行う
  final String? fragment;

  const ResolvedStorageValue._()
      : path = null,
        externalUrl = null,
        fragment = null;

  /// 値なし（null / 空文字）
  static const ResolvedStorageValue empty = ResolvedStorageValue._();

  /// バケット相対パスとして解決された値
  const ResolvedStorageValue.path(String this.path, {this.fragment})
      : externalUrl = null;

  /// 外部 URL として解決された値
  const ResolvedStorageValue.external(String this.externalUrl)
      : path = null,
        fragment = null;

  bool get isEmpty => path == null && externalUrl == null;
  bool get isExternal => externalUrl != null;

  /// percent デコード済みのフラグメント（元ファイル名）。デコード失敗時は生値を返す
  String? get decodedFragment {
    final raw = fragment;
    if (raw == null || raw.isEmpty) return raw;
    try {
      return Uri.decodeComponent(raw);
    } catch (_) {
      return raw;
    }
  }
}

/// 値が Storage 外の URL（Google アバター等）かどうか。
/// `http(s)` で始まり、かつ [bucket] の公開/署名 URL パターンを含まない場合に true。
bool isExternalUrl(String value, String bucket) {
  final trimmed = value.trim();
  if (!_isHttpUrl(trimmed)) return false;
  return _findBucketMarker(trimmed, bucket) == null;
}

/// 値を `#` フラグメントで分離する。戻り値は (フラグメント除去済みの本体, フラグメント)。
/// フラグメントが無い場合は (value, null)。
(String, String?) splitFragment(String value) {
  final hashIndex = value.indexOf('#');
  if (hashIndex < 0) return (value, null);
  return (value.substring(0, hashIndex), value.substring(hashIndex + 1));
}

/// DB に保存された Storage 値（バケット相対パス / レガシー公開URL / 署名URL / 外部URL）を解決する。
///
/// - null / 空文字 → [ResolvedStorageValue.empty]
/// - `http(s)` 始まりで `/storage/v1/object/(public|sign)/<bucket>/` を含む
///   → パス抽出（クエリ・フラグメント除去、percent デコード）
/// - それ以外の `http(s)` 始まり（Google 等） → 外部 URL としてそのまま返す
/// - それ以外 → バケット相対パス（`#` フラグメントは分離して保持）
ResolvedStorageValue resolveStorageValue(String? value, String bucket) {
  if (value == null) return ResolvedStorageValue.empty;
  final trimmed = value.trim();
  if (trimmed.isEmpty) return ResolvedStorageValue.empty;

  // `#` フラグメント（client-notes の元ファイル名等）を先に分離する
  final (base, fragment) = splitFragment(trimmed);

  if (_isHttpUrl(base)) {
    final marker = _findBucketMarker(base, bucket);
    if (marker == null) {
      // Storage 外の URL（Google アバター等）はそのまま返す
      return ResolvedStorageValue.external(trimmed);
    }
    // マーカー以降がバケット相対パス。クエリ（?token= / ?t= 等）を除去する
    var path = base.substring(marker.$1 + marker.$2.length);
    final queryIndex = path.indexOf('?');
    if (queryIndex >= 0) path = path.substring(0, queryIndex);
    path = _tryDecode(path);
    if (path.isEmpty) return ResolvedStorageValue.empty;
    return ResolvedStorageValue.path(path, fragment: fragment);
  }

  // `#name` のみ等、パス本体が無い値は「値なし」扱い
  if (base.isEmpty) return ResolvedStorageValue.empty;
  return ResolvedStorageValue.path(base, fragment: fragment);
}

bool _isHttpUrl(String value) {
  return value.startsWith('http://') || value.startsWith('https://');
}

/// [bucket] の公開/署名 URL マーカーを探す。戻り値は (開始位置, マーカー文字列)、無ければ null
(int, String)? _findBucketMarker(String url, String bucket) {
  for (final marker in [
    '/storage/v1/object/public/$bucket/',
    '/storage/v1/object/sign/$bucket/',
  ]) {
    final index = url.indexOf(marker);
    if (index >= 0) return (index, marker);
  }
  return null;
}

/// percent エンコードをデコードする（getPublicUrl はパスをエンコードして返すため）。
/// 不正なエンコードの場合は生値をそのまま返す
String _tryDecode(String path) {
  try {
    return Uri.decodeFull(path);
  } catch (_) {
    return path;
  }
}
