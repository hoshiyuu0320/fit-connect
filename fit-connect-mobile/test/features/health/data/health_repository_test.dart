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

/// テスト用の睡眠の HealthDataPoint を生成するヘルパー（value は dateFrom〜dateTo の分）
HealthDataPoint _createSleepDataPoint({
  required HealthDataType type,
  required DateTime dateFrom,
  required DateTime dateTo,
  required HealthPlatformType sourcePlatform,
}) {
  return HealthDataPoint(
    uuid: '${type.name}-${dateFrom.millisecondsSinceEpoch}',
    value: NumericHealthValue(
      numericValue: dateTo.difference(dateFrom).inMinutes,
    ),
    type: type,
    unit: HealthDataUnit.MINUTE,
    dateFrom: dateFrom,
    dateTo: dateTo,
    sourcePlatform: sourcePlatform,
    sourceDeviceId: 'test-device',
    sourceId: 'test-source',
    sourceName: 'test',
    recordingMethod: RecordingMethod.unknown,
  );
}

/// Android（Health Connect）で睡眠として扱う型。SLEEP_IN_BED の代わりに SLEEP_SESSION
const _androidSleepTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_SESSION,
];

/// iOS（HealthKit）で睡眠として扱う型
const _iosSleepTypes = [
  HealthDataType.SLEEP_ASLEEP,
  HealthDataType.SLEEP_DEEP,
  HealthDataType.SLEEP_LIGHT,
  HealthDataType.SLEEP_REM,
  HealthDataType.SLEEP_AWAKE,
  HealthDataType.SLEEP_IN_BED,
];

/// health プラグインと同じく、点を型の順（ASLEEP, DEEP, LIGHT, REM, AWAKE,
/// IN_BED/SESSION）に並べる。プラグインは型ごとに取得して連結するので、
/// 返る点は時刻の順にならない。同じ型の中は元の順のまま
List<HealthDataPoint> _inPluginOrder(List<HealthDataPoint> points) => [
      for (final type in [..._iosSleepTypes, HealthDataType.SLEEP_SESSION])
        ...points.where((p) => p.type == type),
    ];

/// 夜 N のステージ: JST 2026-04-01 23:00 就寝 〜 04-02 07:00 起床（合計 480 分）。
/// 最初の LIGHT は JST 0 時より前（04-01 23:40）に終わる
List<HealthDataPoint> _nightN({
  HealthPlatformType sourcePlatform = HealthPlatformType.appleHealth,
}) =>
    [
      // LIGHT: JST 04-01 23:00〜23:40（40 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_LIGHT,
        dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
        dateTo: DateTime.utc(2026, 4, 1, 14, 40),
        sourcePlatform: sourcePlatform,
      ),
      // DEEP: JST 04-01 23:40〜04-02 00:30（50 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_DEEP,
        dateFrom: DateTime.utc(2026, 4, 1, 14, 40),
        dateTo: DateTime.utc(2026, 4, 1, 15, 30),
        sourcePlatform: sourcePlatform,
      ),
      // LIGHT: JST 04-02 00:30〜03:00（150 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_LIGHT,
        dateFrom: DateTime.utc(2026, 4, 1, 15, 30),
        dateTo: DateTime.utc(2026, 4, 1, 18, 0),
        sourcePlatform: sourcePlatform,
      ),
      // REM: JST 04-02 03:00〜04:00（60 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_REM,
        dateFrom: DateTime.utc(2026, 4, 1, 18, 0),
        dateTo: DateTime.utc(2026, 4, 1, 19, 0),
        sourcePlatform: sourcePlatform,
      ),
      // AWAKE: JST 04-02 04:00〜04:10（10 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_AWAKE,
        dateFrom: DateTime.utc(2026, 4, 1, 19, 0),
        dateTo: DateTime.utc(2026, 4, 1, 19, 10),
        sourcePlatform: sourcePlatform,
      ),
      // LIGHT: JST 04-02 04:10〜06:00（110 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_LIGHT,
        dateFrom: DateTime.utc(2026, 4, 1, 19, 10),
        dateTo: DateTime.utc(2026, 4, 1, 21, 0),
        sourcePlatform: sourcePlatform,
      ),
      // REM: JST 04-02 06:00〜07:00（60 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_REM,
        dateFrom: DateTime.utc(2026, 4, 1, 21, 0),
        dateTo: DateTime.utc(2026, 4, 1, 22, 0),
        sourcePlatform: sourcePlatform,
      ),
    ];

/// 前の夜 P（iOS）: JST 2026-03-31 23:30 就寝 〜 04-01 06:30 起床（合計 405 分）
List<HealthDataPoint> _nightP() => [
      // LIGHT: JST 03-31 23:30〜04-01 01:30（120 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_LIGHT,
        dateFrom: DateTime.utc(2026, 3, 31, 14, 30),
        dateTo: DateTime.utc(2026, 3, 31, 16, 30),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
      // DEEP: JST 04-01 01:30〜02:45（75 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_DEEP,
        dateFrom: DateTime.utc(2026, 3, 31, 16, 30),
        dateTo: DateTime.utc(2026, 3, 31, 17, 45),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
      // REM: JST 04-01 02:45〜04:00（75 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_REM,
        dateFrom: DateTime.utc(2026, 3, 31, 17, 45),
        dateTo: DateTime.utc(2026, 3, 31, 19, 0),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
      // AWAKE: JST 04-01 04:00〜04:15（15 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_AWAKE,
        dateFrom: DateTime.utc(2026, 3, 31, 19, 0),
        dateTo: DateTime.utc(2026, 3, 31, 19, 15),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
      // LIGHT: JST 04-01 04:15〜06:15（120 分）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_LIGHT,
        dateFrom: DateTime.utc(2026, 3, 31, 19, 15),
        dateTo: DateTime.utc(2026, 3, 31, 21, 15),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
      // IN_BED: JST 03-31 23:30〜04-01 06:30（就寝・起床は広げるが、分は足さない）
      _createSleepDataPoint(
        type: HealthDataType.SLEEP_IN_BED,
        dateFrom: DateTime.utc(2026, 3, 31, 14, 30),
        dateTo: DateTime.utc(2026, 3, 31, 21, 30),
        sourcePlatform: HealthPlatformType.appleHealth,
      ),
    ];

/// getSleepData が返す1晩分の値を、すべての項目で確かめる Matcher
Matcher _isSleepSession({
  required DateTime bedTime,
  required DateTime wakeTime,
  required int deepMinutes,
  required int lightMinutes,
  required int remMinutes,
  required int awakeMinutes,
  required int totalSleepMinutes,
}) =>
    isA<SleepSessionData>()
        .having((s) => s.bedTime, 'bedTime', bedTime)
        .having((s) => s.wakeTime, 'wakeTime', wakeTime)
        .having((s) => s.deepMinutes, 'deepMinutes', deepMinutes)
        .having((s) => s.lightMinutes, 'lightMinutes', lightMinutes)
        .having((s) => s.remMinutes, 'remMinutes', remMinutes)
        .having((s) => s.awakeMinutes, 'awakeMinutes', awakeMinutes)
        .having(
            (s) => s.totalSleepMinutes, 'totalSleepMinutes', totalSleepMinutes);

/// 夜 N の期待値
final _isNightN = _isSleepSession(
  bedTime: DateTime.utc(2026, 4, 1, 14, 0), // JST 04-01 23:00
  wakeTime: DateTime.utc(2026, 4, 1, 22, 0), // JST 04-02 07:00
  deepMinutes: 50,
  lightMinutes: 300, // 40 + 150 + 110
  remMinutes: 120, // 60 + 60
  awakeMinutes: 10,
  totalSleepMinutes: 480, // 50 + 300 + 120 + 10
);

/// 前の夜 P の期待値
final _isNightP = _isSleepSession(
  bedTime: DateTime.utc(2026, 3, 31, 14, 30), // JST 03-31 23:30
  wakeTime: DateTime.utc(2026, 3, 31, 21, 30), // JST 04-01 06:30（IN_BED の終わり）
  deepMinutes: 75,
  lightMinutes: 240, // 120 + 120
  remMinutes: 75,
  awakeMinutes: 15,
  totalSleepMinutes: 405, // 75 + 240 + 75 + 15。IN_BED は足さない
);

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
        // flutter test の既定は Android なので、許可のあと hasPermissions で確かめ直す
        when(mockHealth.hasPermissions(
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

      test('requests only WEIGHT when includeSleep is not specified', () async {
        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        await repository.requestPermission();

        final captured = verify(mockHealth.requestAuthorization(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        expect(captured[0], equals([HealthDataType.WEIGHT]));
        expect(captured[1], equals([HealthDataAccess.READ]));
      });

      test(
          'on Android, includeSleep requests SLEEP_SESSION instead of SLEEP_IN_BED',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, true);
        final captured = verify(mockHealth.requestAuthorization(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        final types = captured[0] as List<HealthDataType>;
        final permissions = captured[1] as List<HealthDataAccess>;
        expect(types, equals([HealthDataType.WEIGHT, ..._androidSleepTypes]));
        expect(types, contains(HealthDataType.SLEEP_SESSION));
        expect(types, isNot(contains(HealthDataType.SLEEP_IN_BED)));
        expect(permissions, hasLength(types.length));
        expect(permissions, everyElement(HealthDataAccess.READ));
      });

      test(
          'on iOS, includeSleep still requests SLEEP_IN_BED (no SLEEP_SESSION)',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, true);
        final captured = verify(mockHealth.requestAuthorization(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        final types = captured[0] as List<HealthDataType>;
        final permissions = captured[1] as List<HealthDataAccess>;
        expect(types, equals([HealthDataType.WEIGHT, ..._iosSleepTypes]));
        expect(types, contains(HealthDataType.SLEEP_IN_BED));
        expect(types, isNot(contains(HealthDataType.SLEEP_SESSION)));
        expect(permissions, hasLength(types.length));
        expect(permissions, everyElement(HealthDataAccess.READ));
      });

      test(
          'on Android, returns false when sleep is denied but weight was already '
          'granted (requestAuthorization true, hasPermissions false)',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        // Health Connect は許可済みの体重だけでも true を返す
        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);
        // 睡眠は拒否されたので、要求したもの全部は許可されていない
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => false);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, false);
      });

      test(
          'on Android, returns true when hasPermissions confirms all of them, '
          'checking the same types and permissions as requested', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, true);
        final requested = verify(mockHealth.requestAuthorization(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        final checked = verify(mockHealth.hasPermissions(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        // 体重だけでなく睡眠も含めて、要求したものと同じ型・権限を確かめる
        expect(
          checked[0],
          equals([HealthDataType.WEIGHT, ..._androidSleepTypes]),
        );
        expect(checked[0], equals(requested[0]));
        expect(checked[1], equals(requested[1]));
      });

      test('on Android, returns false when hasPermissions returns null',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);
        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => null);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, false);
      });

      test(
          'on Android, returns false without calling hasPermissions '
          'when authorization is denied', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => false);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, false);
        verifyNever(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        ));
      });

      test(
          'on iOS, returns true without calling hasPermissions '
          'when authorization is granted', () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.requestAuthorization(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.requestPermission(includeSleep: true);

        expect(result, true);
        // HealthKit は読み取り権限の状態を教えないため、確かめ直さない
        verifyNever(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        ));
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

      test(
          'returns true on iOS when hasPermissions returns null (Apple privacy policy)',
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

      test('returns false on Android when hasPermissions returns null',
          () async {
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

      test('on Android, forSleep checks SLEEP_SESSION instead of SLEEP_IN_BED',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.hasPermission(forSleep: true);

        expect(result, true);
        final captured = verify(mockHealth.hasPermissions(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        final types = captured[0] as List<HealthDataType>;
        final permissions = captured[1] as List<HealthDataAccess>;
        expect(types, equals(_androidSleepTypes));
        expect(types, contains(HealthDataType.SLEEP_SESSION));
        expect(types, isNot(contains(HealthDataType.SLEEP_IN_BED)));
        expect(permissions, hasLength(types.length));
        expect(permissions, everyElement(HealthDataAccess.READ));
      });

      test('on iOS, forSleep still checks SLEEP_IN_BED (no SLEEP_SESSION)',
          () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);

        when(mockHealth.hasPermissions(
          any,
          permissions: anyNamed('permissions'),
        )).thenAnswer((_) async => true);

        final result = await repository.hasPermission(forSleep: true);

        expect(result, true);
        final captured = verify(mockHealth.hasPermissions(
          captureAny,
          permissions: captureAnyNamed('permissions'),
        )).captured;
        final types = captured[0] as List<HealthDataType>;
        final permissions = captured[1] as List<HealthDataAccess>;
        expect(types, equals(_iosSleepTypes));
        expect(types, contains(HealthDataType.SLEEP_IN_BED));
        expect(types, isNot(contains(HealthDataType.SLEEP_SESSION)));
        expect(permissions, hasLength(types.length));
        expect(permissions, everyElement(HealthDataAccess.READ));
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

    group('getSleepData', () {
      // 日時はすべて UTC で作る（JST = UTC + 9h。実行マシンのタイムゾーンに左右されない）
      // health プラグインは型ごとに取得して連結するため、テストの点も型の順に並べる

      group('on Android', () {
        setUp(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
        });

        test('requests SLEEP_SESSION and not SLEEP_IN_BED', () async {
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => []);

          await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          final types = verify(mockHealth.getHealthDataFromTypes(
            types: captureAnyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).captured.single as List<HealthDataType>;
          expect(types, contains(HealthDataType.SLEEP_SESSION));
          expect(types, isNot(contains(HealthDataType.SLEEP_IN_BED)));
          // 権限をリクエストする型と同じ型を読む
          expect(types, equals(_androidSleepTypes));
        });

        test(
            'with a session and stages, bed/wake are the session range, '
            'stages are summed per type, total excludes the session, '
            'and the key is the JST wake date', () async {
          // JST 2026-04-01 23:30 就寝 〜 04-02 07:00 起床（セッション 450 分）
          final points = [
            // DEEP: JST 01:15〜02:45（90 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_DEEP,
              dateFrom: DateTime.utc(2026, 4, 1, 16, 15),
              dateTo: DateTime.utc(2026, 4, 1, 17, 45),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // LIGHT: JST 23:45〜01:15（90 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 45),
              dateTo: DateTime.utc(2026, 4, 1, 16, 15),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // LIGHT: JST 03:40〜05:40（120 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 40),
              dateTo: DateTime.utc(2026, 4, 1, 20, 40),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // REM: JST 02:45〜03:30（45 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_REM,
              dateFrom: DateTime.utc(2026, 4, 1, 17, 45),
              dateTo: DateTime.utc(2026, 4, 1, 18, 30),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // REM: JST 05:40〜06:50（70 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_REM,
              dateFrom: DateTime.utc(2026, 4, 1, 20, 40),
              dateTo: DateTime.utc(2026, 4, 1, 21, 50),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // AWAKE: JST 03:30〜03:40（10 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_AWAKE,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 30),
              dateTo: DateTime.utc(2026, 4, 1, 18, 40),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // SESSION: JST 23:30〜07:00（450 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_SESSION,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 30),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
          ];
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          // 起床は UTC では 04-01 だが、キーは JST の起床日
          expect(result.keys, ['2026-04-02']);
          final sleep = result['2026-04-02']!;
          expect(sleep.bedTime, DateTime.utc(2026, 4, 1, 14, 30));
          expect(sleep.wakeTime, DateTime.utc(2026, 4, 1, 22, 0));
          expect(sleep.deepMinutes, 90);
          expect(sleep.lightMinutes, 210);
          expect(sleep.remMinutes, 115);
          expect(sleep.awakeMinutes, 10);
          // 90 + 210 + 115 + 10。セッションの 450 分は足さない
          expect(sleep.totalSleepMinutes, 425);
        });

        test('with only a session (no stages), total is the session length',
            () async {
          // SESSION: JST 2026-04-01 23:00〜04-02 06:00（420 分）
          final points = [
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_SESSION,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
              dateTo: DateTime.utc(2026, 4, 1, 21, 0),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
          ];
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          expect(result.keys, ['2026-04-02']);
          final sleep = result['2026-04-02']!;
          expect(sleep.totalSleepMinutes, 420);
          expect(sleep.deepMinutes, 0);
          expect(sleep.lightMinutes, 0);
          expect(sleep.remMinutes, 0);
          expect(sleep.awakeMinutes, 0);
          expect(sleep.bedTime, DateTime.utc(2026, 4, 1, 14, 0));
          expect(sleep.wakeTime, DateTime.utc(2026, 4, 1, 21, 0));
        });

        test(
            'a session crossing JST midnight is one night keyed by its wake '
            'date, and the session is not added to the total', () async {
          final points = _inPluginOrder([
            // 夜 N のステージ（最初の LIGHT は JST 04-01 23:40 に終わる）
            ..._nightN(sourcePlatform: HealthPlatformType.googleHealthConnect),
            // SESSION: JST 04-01 23:00〜04-02 07:00（480 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_SESSION,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          // 就寝した JST 04-01 にはキーを作らない
          expect(result.keys, ['2026-04-02']);
          // 就寝・起床はセッションの範囲（夜 N と同じ）。
          // 合計はステージの 480 分で、セッションの 480 分は足さない
          expect(result['2026-04-02'], _isNightN);
        });

        test(
            'a previous night with only a session keeps its range and session '
            'length when the next night has a stage ending before JST midnight',
            () async {
          final points = _inPluginOrder([
            // 前の夜はステージの無いセッションだけ
            // SESSION: JST 03-31 23:30〜04-01 06:30（420 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_SESSION,
              dateFrom: DateTime.utc(2026, 3, 31, 14, 30),
              dateTo: DateTime.utc(2026, 3, 31, 21, 30),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
            // 夜 N のステージ（最初の LIGHT は JST 04-01 23:40 に終わる）
            ..._nightN(sourcePlatform: HealthPlatformType.googleHealthConnect),
            // 夜 N の SESSION: JST 04-01 23:00〜04-02 07:00（480 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_SESSION,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.googleHealthConnect,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, unorderedEquals(['2026-04-01', '2026-04-02']));
          // 夜 N の最初の LIGHT（JST 04-01 23:00〜23:40）は前の夜に入らない。
          // 前の夜はステージが無いままなので、合計はセッションの長さ
          expect(
            result['2026-04-01'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 3, 31, 14, 30), // JST 03-31 23:30
              wakeTime: DateTime.utc(2026, 3, 31, 21, 30), // JST 04-01 06:30
              deepMinutes: 0,
              lightMinutes: 0,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 420,
            ),
          );
          expect(result['2026-04-02'], _isNightN);
        });
      });

      group('on iOS', () {
        setUp(() {
          debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
          addTearDown(() => debugDefaultTargetPlatformOverride = null);
        });

        test('requests SLEEP_IN_BED', () async {
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => []);

          await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          final types = verify(mockHealth.getHealthDataFromTypes(
            types: captureAnyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).captured.single as List<HealthDataType>;
          expect(types, contains(HealthDataType.SLEEP_IN_BED));
          expect(types, isNot(contains(HealthDataType.SLEEP_SESSION)));
          // 権限をリクエストする型と同じ型を読む
          expect(types, equals(_iosSleepTypes));
        });

        test('IN_BED widens bed/wake but is not counted in stages or total',
            () async {
          // JST 2026-04-01 23:00 在床開始 〜 04-02 07:30 在床終了（510 分）
          final points = [
            // DEEP: JST 01:00〜02:00（60 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_DEEP,
              dateFrom: DateTime.utc(2026, 4, 1, 16, 0),
              dateTo: DateTime.utc(2026, 4, 1, 17, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // LIGHT: JST 23:30〜01:00（90 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 30),
              dateTo: DateTime.utc(2026, 4, 1, 16, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // LIGHT: JST 03:30〜07:00（210 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 30),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // REM: JST 02:00〜03:15（75 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_REM,
              dateFrom: DateTime.utc(2026, 4, 1, 17, 0),
              dateTo: DateTime.utc(2026, 4, 1, 18, 15),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // AWAKE: JST 03:15〜03:30（15 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_AWAKE,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 15),
              dateTo: DateTime.utc(2026, 4, 1, 18, 30),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // IN_BED: JST 23:00〜07:30（510 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_IN_BED,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
              dateTo: DateTime.utc(2026, 4, 1, 22, 30),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ];
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          expect(result.keys, ['2026-04-02']);
          final sleep = result['2026-04-02']!;
          // 就寝・起床は IN_BED の範囲まで広がる
          expect(sleep.bedTime, DateTime.utc(2026, 4, 1, 14, 0));
          expect(sleep.wakeTime, DateTime.utc(2026, 4, 1, 22, 30));
          expect(sleep.deepMinutes, 60);
          expect(sleep.lightMinutes, 300);
          expect(sleep.remMinutes, 75);
          expect(sleep.awakeMinutes, 15);
          // 60 + 300 + 75 + 15。IN_BED の 510 分は足さない
          expect(sleep.totalSleepMinutes, 450);
        });

        test('without stage details, total is ASLEEP + AWAKE', () async {
          final points = [
            // ASLEEP: JST 2026-04-01 23:40〜04-02 03:00（200 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_ASLEEP,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 40),
              dateTo: DateTime.utc(2026, 4, 1, 18, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // ASLEEP: JST 03:20〜06:50（210 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_ASLEEP,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 20),
              dateTo: DateTime.utc(2026, 4, 1, 21, 50),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // AWAKE: JST 03:00〜03:20（20 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_AWAKE,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 0),
              dateTo: DateTime.utc(2026, 4, 1, 18, 20),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ];
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 3),
          );

          expect(result.keys, ['2026-04-02']);
          final sleep = result['2026-04-02']!;
          expect(sleep.deepMinutes, 0);
          expect(sleep.lightMinutes, 0);
          expect(sleep.remMinutes, 0);
          expect(sleep.awakeMinutes, 20);
          // 200 + 210 + 20
          expect(sleep.totalSleepMinutes, 430);
        });

        test('a day with only IN_BED is not included', () async {
          final points = [
            // 04-02 起床の夜: ASLEEP JST 04-02 00:00〜06:00（360 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_ASLEEP,
              dateFrom: DateTime.utc(2026, 4, 1, 15, 0),
              dateTo: DateTime.utc(2026, 4, 1, 21, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // 04-03 起床の夜は IN_BED だけ: JST 04-02 23:00〜04-03 07:00
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_IN_BED,
              dateFrom: DateTime.utc(2026, 4, 2, 14, 0),
              dateTo: DateTime.utc(2026, 4, 2, 22, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ];
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 4, 1),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, ['2026-04-02']);
          expect(result.containsKey('2026-04-03'), isFalse);
          expect(result['2026-04-02']!.totalSleepMinutes, 360);
        });

        test('a night crossing JST midnight is keyed by its wake date only',
            () async {
          // 夜 N だけ。最初の LIGHT は JST 04-01 23:40 に終わる
          final points = _inPluginOrder(_nightN());
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          // 就寝した JST 04-01 にはキーを作らない
          expect(result.keys, ['2026-04-02']);
          expect(result['2026-04-02'], _isNightN);
        });

        test(
            'a stage ending before JST midnight stays in its own night '
            'and does not change the previous night', () async {
          // 前の夜 P（JST 04-01 起床）と夜 N（JST 04-02 起床）
          final points = _inPluginOrder([..._nightP(), ..._nightN()]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, unorderedEquals(['2026-04-01', '2026-04-02']));
          // 夜 N の最初の LIGHT（JST 04-01 23:00〜23:40）は P に入らない。
          // P の起床は JST 23:40 にずれず、合計も 445 分にならない
          expect(result['2026-04-01'], _isNightP);
          expect(result['2026-04-02'], _isNightN);
        });

        test('a nap is not added to the night that wakes on the same day',
            () async {
          final points = _inPluginOrder([
            ..._nightN(),
            // 昼寝 LIGHT: JST 04-02 14:00〜15:00（60 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 2, 5, 0),
              dateTo: DateTime.utc(2026, 4, 2, 6, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          // 昼寝も起床は JST 04-02 だが、合計の長い夜 N を1件だけ返す。昼寝の分は足さない
          expect(result.keys, ['2026-04-02']);
          expect(result['2026-04-02'], _isNightN);
        });

        test('a nap is recorded on a day without any other night', () async {
          final points = _inPluginOrder([
            ..._nightN(),
            // 昼寝 LIGHT: JST 04-03 14:00〜15:00（60 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 3, 5, 0),
              dateTo: DateTime.utc(2026, 4, 3, 6, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, unorderedEquals(['2026-04-02', '2026-04-03']));
          expect(result['2026-04-02'], _isNightN);
          expect(
            result['2026-04-03'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 4, 3, 5, 0), // JST 04-03 14:00
              wakeTime: DateTime.utc(2026, 4, 3, 6, 0), // JST 04-03 15:00
              deepMinutes: 0,
              lightMinutes: 60,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 60,
            ),
          );
        });

        test(
            'syncing in the middle of a night does not overwrite '
            'the previous night with the same wake date', () async {
          final points = _inPluginOrder([
            ..._nightN(),
            // 次の夜の最初のステージだけ（同期したときは寝ている途中）。
            // LIGHT: JST 04-02 23:00〜23:40（40 分）。いまの起床は夜 N と同じ JST 04-02
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 2, 14, 0),
              dateTo: DateTime.utc(2026, 4, 2, 14, 40),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          // 40 分の晩は夜 N より短いので選ばれない
          expect(result.keys, ['2026-04-02']);
          expect(result['2026-04-02'], _isNightN);
        });

        test('points with a gap of less than 3 hours are the same night',
            () async {
          final points = _inPluginOrder([
            // LIGHT: JST 04-01 23:00〜04-02 01:00（120 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 14, 0),
              dateTo: DateTime.utc(2026, 4, 1, 16, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // 2 時間 30 分あけて LIGHT: JST 04-02 03:30〜07:00（210 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 18, 30),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, ['2026-04-02']);
          expect(
            result['2026-04-02'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 4, 1, 14, 0), // JST 04-01 23:00
              wakeTime: DateTime.utc(2026, 4, 1, 22, 0), // JST 04-02 07:00
              deepMinutes: 0,
              lightMinutes: 330,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 330, // 120 + 210
            ),
          );
        });

        test('points with a gap of exactly 3 hours are separate nights',
            () async {
          final points = _inPluginOrder([
            // LIGHT: JST 04-01 21:00〜23:30（150 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 12, 0),
              dateTo: DateTime.utc(2026, 4, 1, 14, 30),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // ちょうど 3 時間あけて LIGHT: JST 04-02 02:30〜07:00（270 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 17, 30),
              dateTo: DateTime.utc(2026, 4, 1, 22, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          expect(result.keys, unorderedEquals(['2026-04-01', '2026-04-02']));
          expect(
            result['2026-04-01'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 4, 1, 12, 0), // JST 04-01 21:00
              wakeTime: DateTime.utc(2026, 4, 1, 14, 30), // JST 04-01 23:30
              deepMinutes: 0,
              lightMinutes: 150,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 150,
            ),
          );
          expect(
            result['2026-04-02'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 4, 1, 17, 30), // JST 04-02 02:30
              wakeTime: DateTime.utc(2026, 4, 1, 22, 0), // JST 04-02 07:00
              deepMinutes: 0,
              lightMinutes: 270,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 270,
            ),
          );
        });

        test(
            'fetches from 2 days before startDate to read a night from its '
            'start, and drops nights waking before the JST date of startDate',
            () async {
          // 前の夜 P（JST 04-01 起床）と夜 N（JST 04-02 起床）
          final points = _inPluginOrder([..._nightP(), ..._nightN()]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            // JST 04-02 03:00（夜 N の途中）
            startDate: DateTime.utc(2026, 4, 1, 18, 0),
            // JST 04-03 09:00
            endDate: DateTime.utc(2026, 4, 3),
          );

          final captured = verify(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: captureAnyNamed('startTime'),
            endTime: captureAnyNamed('endTime'),
          )).captured;
          final startTime = captured[0] as DateTime;
          final endTime = captured[1] as DateTime;
          // 読み始めは startDate の 2 日前（JST 03-31 03:00）。endTime は endDate のまま
          expect(startTime, DateTime.utc(2026, 3, 30, 18, 0));
          expect(endTime, DateTime.utc(2026, 4, 3));
          // P は起床が JST 04-01 で、startDate の JST 日付（04-02）より前なので返さない
          expect(result.keys, ['2026-04-02']);
          // 就寝は startDate より前（UTC 04-01 14:00）だが、夜 N を最初から数える
          expect(result['2026-04-02'], _isNightN);
        });

        test(
            'when nights with the same wake date have the same total, '
            'the one waking later is returned', () async {
          final points = _inPluginOrder([
            // LIGHT: JST 04-02 00:00〜01:00（60 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 15, 0),
              dateTo: DateTime.utc(2026, 4, 1, 16, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
            // 4 時間あけて（別の晩）LIGHT: JST 04-02 05:00〜06:00（60 分）
            _createSleepDataPoint(
              type: HealthDataType.SLEEP_LIGHT,
              dateFrom: DateTime.utc(2026, 4, 1, 20, 0),
              dateTo: DateTime.utc(2026, 4, 1, 21, 0),
              sourcePlatform: HealthPlatformType.appleHealth,
            ),
          ]);
          when(mockHealth.getHealthDataFromTypes(
            types: anyNamed('types'),
            startTime: anyNamed('startTime'),
            endTime: anyNamed('endTime'),
          )).thenAnswer((_) async => points);

          final result = await repository.getSleepData(
            startDate: DateTime.utc(2026, 3, 31),
            endDate: DateTime.utc(2026, 4, 4),
          );

          // どちらも起床は JST 04-02 で、合計は同じ 60 分。起床が遅い方を1件だけ返す
          expect(result.keys, ['2026-04-02']);
          expect(
            result['2026-04-02'],
            _isSleepSession(
              bedTime: DateTime.utc(2026, 4, 1, 20, 0), // JST 04-02 05:00
              wakeTime: DateTime.utc(2026, 4, 1, 21, 0), // JST 04-02 06:00
              deepMinutes: 0,
              lightMinutes: 60,
              remMinutes: 0,
              awakeMinutes: 0,
              totalSleepMinutes: 60,
            ),
          );
        });
      });

      test('returns empty map when an exception is thrown', () async {
        when(mockHealth.getHealthDataFromTypes(
          types: anyNamed('types'),
          startTime: anyNamed('startTime'),
          endTime: anyNamed('endTime'),
        )).thenThrow(Exception('Failed'));

        final result = await repository.getSleepData(
          startDate: DateTime.utc(2026, 4, 1),
        );

        expect(result, isEmpty);
      });
    });
  });
}
