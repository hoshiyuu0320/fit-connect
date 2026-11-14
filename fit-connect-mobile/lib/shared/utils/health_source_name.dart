import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;

/// ヘルスケア連携元の表示名（全画面で共通）。
///
/// 連携元は OS で違う（iOS は HealthKit、Android は Health Connect）。画面ごとに
/// ばらつかないよう、連携元の名前の出し分けはこの関数1箇所にだけ置く。
///
/// - iOS → 「HealthKit」
/// - Android → 「Health Connect」
/// - それ以外（プレビューの macOS など）→ 「HealthKit」
///
/// 変えるのは画面に出す文字だけ。DB の `source = 'healthkit'` の値や、
/// debugPrint の文言には使わない。
///
/// テストでは `debugDefaultTargetPlatformOverride` で OS を切り替える
/// （`flutter test` の既定は Android）。
String healthSourceName() => defaultTargetPlatform == TargetPlatform.android
    ? 'Health Connect'
    : 'HealthKit';
