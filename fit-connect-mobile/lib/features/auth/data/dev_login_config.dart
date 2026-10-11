import 'package:flutter/foundation.dart';

/// 開発用テストログインの設定。
///
/// 認証情報は `assets/.env`（リリースビルドにもアセットとして同梱される）ではなく、
/// コンパイル時定義（`--dart-define-from-file=dev_login.json`）でのみ渡す。
/// 定義が無いビルドでは空文字となり、テストログインは無効になる。
class DevLoginConfig {
  DevLoginConfig._();

  static const String email = String.fromEnvironment('DEV_LOGIN_EMAIL');
  static const String password = String.fromEnvironment('DEV_LOGIN_PASSWORD');

  /// デバッグビルドかつ認証情報が定義されている場合のみ利用可能
  static bool get isDevLoginAvailable =>
      kDebugMode && email.isNotEmpty && password.isNotEmpty;
}
