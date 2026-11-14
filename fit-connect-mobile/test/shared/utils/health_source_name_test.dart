import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fit_connect_mobile/shared/utils/health_source_name.dart';

void main() {
  group('healthSourceName', () {
    test('iOS は「HealthKit」', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(healthSourceName(), 'HealthKit');
    });

    test('Android は「Health Connect」', () {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      expect(healthSourceName(), 'Health Connect');
    });

    test('iOS・Android 以外（macOS など）は「HealthKit」', () {
      addTearDown(() => debugDefaultTargetPlatformOverride = null);

      for (final platform in [
        TargetPlatform.macOS,
        TargetPlatform.windows,
        TargetPlatform.linux,
        TargetPlatform.fuchsia,
      ]) {
        debugDefaultTargetPlatformOverride = platform;
        expect(healthSourceName(), 'HealthKit', reason: '$platform');
      }
    });
  });
}
