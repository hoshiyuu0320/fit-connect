// Firebase の初期化オプション定義。
//
// FlutterFire CLI（`flutterfire configure`）が生成するものと同じ構造・同じ値を、
// 既存の `ios/Runner/GoogleService-Info.plist` および
// `android/app/google-services.json` から手動で書き起こしたもの。
//
// これにより `Firebase.initializeApp()` がバンドル内の設定ファイルに依存しなくなる。
// （GoogleService-Info.plist が Xcode プロジェクトに未登録で
//  `[core/not-initialized]` になっていた問題への対処）
//
// Firebase プロジェクトの設定を変更した場合は、上記2ファイルと本ファイルを
// 揃えて更新すること。
//
// ignore_for_file: type=lint

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

/// 実行中のプラットフォームに対応する [FirebaseOptions] を返す。
///
/// ```dart
/// await Firebase.initializeApp(
///   options: DefaultFirebaseOptions.currentPlatform,
/// );
/// ```
class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'DefaultFirebaseOptions は Web 用に設定されていません。'
        'Firebase コンソールで Web アプリを追加のうえ、本ファイルを更新してください。',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        throw UnsupportedError(
          'DefaultFirebaseOptions は macOS 用に設定されていません。'
          'Firebase コンソールで macOS アプリを追加のうえ、本ファイルを更新してください。',
        );
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions は Windows 用に設定されていません。',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions は Linux 用に設定されていません。',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions は現在のプラットフォームに対応していません。',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyARPnTA0MjUG3kshUGP1GBShLafMpT2us8',
    appId: '1:59445891214:android:fec867bd49c933ba0079df',
    messagingSenderId: '59445891214',
    projectId: 'fit-connect-540f4',
    storageBucket: 'fit-connect-540f4.firebasestorage.app',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCWdDkbbQzWcfgAlvC_q5UW_Nuy-y5dgG0',
    appId: '1:59445891214:ios:1274673c36d1d2e10079df',
    messagingSenderId: '59445891214',
    projectId: 'fit-connect-540f4',
    storageBucket: 'fit-connect-540f4.firebasestorage.app',
    iosClientId:
        '59445891214-82pfrrjbq0vbc285navh87nabmn7l1hk.apps.googleusercontent.com',
    iosBundleId: 'com.fitconnect.fitConnectMobile',
  );
}
