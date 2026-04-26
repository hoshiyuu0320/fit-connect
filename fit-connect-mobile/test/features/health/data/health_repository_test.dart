import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:health/health.dart';
import 'package:fit_connect_mobile/features/health/data/health_repository.dart';

@GenerateMocks([Health])
import 'health_repository_test.mocks.dart';

/// テスト用の HealthDataPoint を生成するヘルパー
HealthDataPoint _createWeightDataPoint({
  required double weight,
  required DateTime dateFrom,
}) {
  return HealthDataPoint(
    uuid: '${dateFrom.millisecondsSinceEpoch}',
    value: NumericHealthValue(numericValue: weight),
    type: HealthDataType.WEIGHT,
    unit: HealthDataUnit.KILOGRAM,
    dateFrom: dateFrom,
    dateTo: dateFrom,
    sourcePlatform: HealthPlatformType.appleHealth,
    sourceDeviceId: 'test-device',
    sourceId: 'test-source',
    sourceName: 'test',
    recordingMethod: RecordingMethod.unknown,
  );
}

void main() {
  late MockHealth mockHealth;
  late HealthRepository repository;

  setUp(() {
    mockHealth = MockHealth();
    repository = HealthRepository(health: mockHealth);
  });

  group('HealthRepository', () {
    group('requestPermission', () {
      test('returns true when authorization is granted', () async {
        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.requestPermission();

        expect(result, true);
        verify(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).called(1);
      });

      test('returns false when authorization is denied', () async {
        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => false);

        final result = await repository.requestPermission();

        expect(result, false);
      });

      test('returns false when an exception is thrown', () async {
        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenThrow(Exception('Platform error'));

        final result = await repository.requestPermission();

        expect(result, false);
      });
    });

    group('hasPermission', () {
      test('returns true when permissions are granted', () async {
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.hasPermission();

        expect(result, true);
      });

      test('returns true on iOS when hasPermissions returns null (Apple privacy policy)',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => null);

        final result = await repository.hasPermission();

        expect(result, true);
      });

      test('returns false on Android when hasPermissions returns null', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => null);

        final result = await repository.hasPermission();

        expect(result, false);
      });

      test('returns false when an exception is thrown', () async {
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenThrow(Exception('error'));

        final result = await repository.hasPermission();

        expect(result, false);
      });
    });

    group('getWeightData', () {
      test('returns empty list when no data', () async {
        when(mockHealth.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        )).thenAnswer((_) async => []);

        final result = await repository.getWeightData(
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2026, 4, 4),
        );

        expect(result, isEmpty);
      });

      test('returns data points sorted by date descending', () async {
        final points = [
          _createWeightDataPoint(
            weight: 70.0,
            dateFrom: DateTime(2026, 4, 1, 8, 0),
          ),
          _createWeightDataPoint(
            weight: 69.5,
            dateFrom: DateTime(2026, 4, 3, 8, 0),
          ),
          _createWeightDataPoint(
            weight: 70.2,
            dateFrom: DateTime(2026, 4, 2, 8, 0),
          ),
        ];

        when(mockHealth.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        )).thenAnswer((_) async => points);

        final result = await repository.getWeightData(
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2026, 4, 4),
        );

        expect(result.length, 3);
        // Most recent date first
        expect(result[0].dateFrom, DateTime(2026, 4, 3, 8, 0));
        expect(result[1].dateFrom, DateTime(2026, 4, 2, 8, 0));
        expect(result[2].dateFrom, DateTime(2026, 4, 1, 8, 0));
      });

      test('picks latest record per day when multiple exist', () async {
        final points = [
          _createWeightDataPoint(
            weight: 70.0,
            dateFrom: DateTime(2026, 4, 1, 7, 0), // morning
          ),
          _createWeightDataPoint(
            weight: 70.5,
            dateFrom: DateTime(2026, 4, 1, 12, 0), // noon
          ),
          _createWeightDataPoint(
            weight: 71.0,
            dateFrom: DateTime(2026, 4, 1, 20, 0), // evening - latest
          ),
          _createWeightDataPoint(
            weight: 69.0,
            dateFrom: DateTime(2026, 4, 2, 9, 0), // next day
          ),
        ];

        when(mockHealth.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        )).thenAnswer((_) async => points);

        final result = await repository.getWeightData(
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2026, 4, 3),
        );

        // Should have 2 entries: one per day
        expect(result.length, 2);
        // April 2 first (descending)
        expect(result[0].dateFrom, DateTime(2026, 4, 2, 9, 0));
        // April 1 - should be the 20:00 entry (latest)
        expect(result[1].dateFrom, DateTime(2026, 4, 1, 20, 0));
        expect(
          (result[1].value as NumericHealthValue).numericValue,
          71.0,
        );
      });

      test('returns empty list when an exception is thrown', () async {
        when(mockHealth.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        )).thenThrow(Exception('Failed'));

        final result = await repository.getWeightData(
          startDate: DateTime(2026, 4, 1),
        );

        expect(result, isEmpty);
      });
    });
  });
}
