# 睡眠データ連携 (Task 1.3) 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** fit-connect-mobile に HealthKit/Health Connect からの睡眠データ読み取り + 手動目覚め評価 + 専用画面/ホームカード/朝ダイアログを実装する。

**Architecture:** 既存体重連携(features/health, weight_records)パターンを踏襲。新規 `features/sleep_records` モジュール追加、`lib/features/health/` を拡張。Supabase `sleep_records` テーブルを新設し UPSERT 戦略で同期。

**Tech Stack:** Flutter 3.35+ / Dart / Riverpod (code-gen) / Supabase / health パッケージ v11 / fl_chart / lucide_icons

**Spec:** `docs/superpowers/specs/2026-04-19-sleep-data-integration-design.md`

**Hi-fi:** `fit-connect-mobile/docs/design/sleep-feature-hifi/fit-connect-mobile/project/`

**Agent Routing** (CLAUDE.md 準拠 — 実装は必ずサブエージェント委託):

| タスク種別 | 委託先 |
|---|---|
| DB migration / RLS | supabase |
| Model / Provider / ロジック | riverpod（または Flutter UI Agent がまとめて） |
| Widget / Screen / プレビュー | flutter-ui |
| 調査・探索 | explore |

---

## プレビュー関数テンプレート（全UIタスク共通）

CLAUDE.md 要件に従い、Widget/Screen 実装タスク（T9-T18）で**必ず**以下パターンのプレビュー関数をファイル末尾に追加。最低2状態（正常・空/loading）カバーすること。

```dart
import 'package:flutter/widget_previews.dart';

@Preview(name: 'SleepSummaryCard - HealthKit State')
Widget previewSleepSummaryCardHealthkit() {
  return MaterialApp(
    theme: AppTheme.lightTheme,
    home: Scaffold(
      backgroundColor: const Color(0xFFFAFAFA),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _PreviewSleepSummaryCardHealthkit(),  // 静的ヘルパー
        ),
      ),
    ),
  );
}

// Riverpod使用Widgetはプロバイダーオーバーライドせず、静的ヘルパーで再現
class _PreviewSleepSummaryCardHealthkit extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    // 静的データで UI を再現（実プロバイダは使わない）
    return ...;
  }
}
```

タスク別に必要なプレビュー状態:

| タスク | プレビュー関数 |
|---|---|
| T9 WakeupRatingSelector | Unselected / Selected (Refreshed) |
| T10 SleepStageBar | Normal (25/50/20/5 分配) / Edge (全深眠) |
| T11 SleepWeekChart | Full 7days / With null gap / Empty |
| T12 SleepHistoryListItem | HealthKit / Manual / NoRating |
| T13 MorningWakeupDialog | Unselected / Selected |
| T14 PermissionDeniedDialog | iOS / Android |
| T15 SleepSummaryCard | Healthkit / Manual / Empty |
| T17 SleepRecordScreen | Healthkit / Manual / Empty / Loading / PermDenied |
| T18 HealthSettingsScreen | Sleep ON / Sleep OFF |

---

## File Structure（新規・変更）

### 新規作成

```
fit-connect-mobile/supabase/migrations/
  └── 20260419210000_create_sleep_records.sql

fit-connect-mobile/lib/features/sleep_records/
  ├── models/
  │   ├── sleep_record_model.dart
  │   └── sleep_record_model.g.dart  (build_runner 生成)
  ├── providers/
  │   ├── sleep_records_provider.dart
  │   ├── sleep_records_provider.g.dart  (生成)
  │   ├── morning_dialog_provider.dart
  │   └── morning_dialog_provider.g.dart (生成)
  ├── data/
  │   └── sleep_date_utils.dart        (jstDateKey ヘルパー)
  └── presentation/
      ├── screens/
      │   └── sleep_record_screen.dart
      └── widgets/
          ├── sleep_summary_card.dart
          ├── sleep_stage_bar.dart
          ├── sleep_week_chart.dart
          ├── sleep_history_list_item.dart
          ├── morning_wakeup_dialog.dart
          ├── permission_denied_dialog.dart
          └── wakeup_rating_selector.dart

fit-connect-mobile/test/features/sleep_records/
  ├── sleep_date_utils_test.dart
  └── morning_dialog_shouldshow_test.dart
```

### 変更

| ファイル | 変更内容 |
|---|---|
| `lib/features/health/data/health_repository.dart` | `getSleepData()` メソッド追加、`requestPermission()` で SLEEP タイプも要求 |
| `lib/features/health/providers/health_provider.dart` | `HealthSettingsState` に `isSleepEnabled`, `isMorningDialogEnabled` フィールド追加 |
| `lib/features/health/providers/health_sync_provider.dart` | `syncSleep()` 実装、`_sync()` 内で体重+睡眠を独立try/catchで呼び出し |
| `lib/features/health/presentation/screens/health_settings_screen.dart` | 睡眠トグル有効化、朝ダイアログ設定追加、インフォカード更新 |
| `lib/features/home/presentation/screens/home_screen.dart` | `SleepSummaryCard` セクション追加（DailySummaryCard の下） |
| `lib/app.dart` | 起動時に `syncSleep()` 呼び出し、MorningDialog 表示判定フック追加 |
| `lib/core/theme/app_colors.dart` | `AppColorsExtension` に `sleepStageDeep/Light/Rem/Awake` の4フィールド追加 |
| `ios/Runner/Info.plist` | `NSHealthShareUsageDescription` 文言更新（睡眠を含める） |
| `android/app/src/main/AndroidManifest.xml` | Health Connect 睡眠パーミッション確認/追加 |
| `pubspec.yaml` | `app_settings: ^5.1.1` 追加 |
| `docs/tasks/IMPLEMENTATION_TASKS.md` | 1.3 のチェックマーク更新 |

---

## 実装順序と依存関係

```
Phase 1 (基盤)    : T1 DB migration → T2 Dart model → T3 sleep_date_utils
Phase 2 (データ層): T4 HealthRepository → T5 SleepRecordsProvider → T6 MorningDialogProvider
Phase 3 (同期統合): T7 HealthSettings拡張 → T8 syncSleep統合
Phase 4 (共通UI) : T9 WakeupRatingSelector → T10 SleepStageBar → T11 SleepWeekChart → T12 SleepHistoryListItem
Phase 5 (ダイアログ): T13 MorningWakeupDialog → T14 PermissionDeniedDialog
Phase 6 (カード) : T15 SleepSummaryCard → T16 Home統合
Phase 7 (画面)   : T17 SleepRecordScreen
Phase 8 (設定)   : T18 HealthSettingsScreen拡張
Phase 9 (起動統合): T19 アプリ起動時ダイアログトリガ
Phase 10 (QA)   : T20 プラットフォーム設定 → T21 統合動作確認 (ios-simulator-qa)
```

T1-T3 は並列不可（T1がベース）。T4-T6 は T2 完了後に並列可能。T9-T12 は T3 完了後に並列可能。T15 は T9 依存、T17 は T9-T12+T14 依存。

---

## Task 1: Supabase sleep_records テーブル作成

**Owner:** supabase agent

**Files:**
- Create: `fit-connect-mobile/supabase/migrations/20260419210000_create_sleep_records.sql`

**Spec reference:** §4 Supabaseスキーマ

**Pattern reference:**
- `supabase/migrations/20251230131753_remote_schema.sql`（weight_records定義部分）
- `supabase/migrations/20251230172037_add_client_policies.sql`（weight_records RLS）

**既存スキーマ前提（検証済み）:**
- `clients` PK: `client_id` UUID（`20251230131753_remote_schema.sql:611`）、`clients.client_id = auth.uid()` で auth 連携
- `clients.trainer_id` → `trainers.id`（トレーナー関連）
- `weight_records` RLS パターン（`20251230131753_remote_schema.sql:879-881, 957-959` + `20251230172037_add_client_policies.sql`）:
  - 本人SELECT/INSERT/UPDATE/DELETE: `client_id = auth.uid()`
  - トレーナーSELECT: `client_id IN (SELECT client_id FROM clients WHERE trainer_id = auth.uid())`

**本タスクの方針:**
- `weight_records` の RLS パターンをそのまま踏襲（本人系 + トレーナーSELECT の5ポリシー）
- トレーナーSELECT は Spec §4 方針に従い**最初から含める**（1.5で Web 実装時に即機能する）
- `note` カラムは不要（YAGNIで削除済み）

- [ ] **Step 1: Migration ファイル作成**

内容:

```sql
-- Create sleep_records table for sleep data tracking
-- Supports HealthKit/Health Connect integration + manual wakeup rating input

CREATE TABLE IF NOT EXISTS "public"."sleep_records" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "client_id" "uuid" NOT NULL,
    "recorded_date" date NOT NULL,
    "bed_time" timestamp with time zone,
    "wake_time" timestamp with time zone,
    "total_sleep_minutes" integer,
    "deep_minutes" integer,
    "light_minutes" integer,
    "rem_minutes" integer,
    "awake_minutes" integer,
    "wakeup_rating" smallint,
    "source" "text" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    CONSTRAINT "sleep_records_pkey" PRIMARY KEY ("id"),
    CONSTRAINT "sleep_records_client_date_unique" UNIQUE ("client_id", "recorded_date"),
    CONSTRAINT "sleep_records_source_check"
      CHECK ("source" = ANY (ARRAY['manual'::text, 'healthkit'::text])),
    CONSTRAINT "sleep_records_wakeup_rating_check"
      CHECK ("wakeup_rating" IS NULL OR "wakeup_rating" IN (1, 2, 3)),
    CONSTRAINT "sleep_records_has_data_check"
      CHECK ("total_sleep_minutes" IS NOT NULL OR "wakeup_rating" IS NOT NULL)
);

ALTER TABLE "public"."sleep_records"
  ADD CONSTRAINT "sleep_records_client_id_fkey"
  FOREIGN KEY ("client_id") REFERENCES "public"."clients"("client_id")
  ON DELETE CASCADE;

CREATE INDEX "idx_sleep_records_client_date"
  ON "public"."sleep_records"("client_id", "recorded_date" DESC);

-- updated_at 自動更新（既存 set_updated_at() 関数を使用）
CREATE TRIGGER "set_sleep_records_updated_at"
  BEFORE UPDATE ON "public"."sleep_records"
  FOR EACH ROW EXECUTE FUNCTION "public"."set_updated_at"();

-- Enable RLS
ALTER TABLE "public"."sleep_records" ENABLE ROW LEVEL SECURITY;

-- RLS Policies（weight_records と同一構造）
-- 1. 本人 SELECT
CREATE POLICY "Clients can view own sleep records"
  ON "public"."sleep_records" FOR SELECT
  USING ("client_id" = "auth"."uid"());

-- 2. 本人 INSERT
CREATE POLICY "Clients can insert own sleep records"
  ON "public"."sleep_records" FOR INSERT
  WITH CHECK ("client_id" = "auth"."uid"());

-- 3. 本人 UPDATE
CREATE POLICY "Clients can update own sleep records"
  ON "public"."sleep_records" FOR UPDATE
  USING ("client_id" = "auth"."uid"())
  WITH CHECK ("client_id" = "auth"."uid"());

-- 4. 本人 DELETE
CREATE POLICY "Clients can delete own sleep records"
  ON "public"."sleep_records" FOR DELETE
  USING ("client_id" = "auth"."uid"());

-- 5. 担当トレーナー SELECT（1.5で Web 実装時に即機能する。weight_records:957-959 と同パターン）
CREATE POLICY "sleep_records_trainer_select"
  ON "public"."sleep_records" FOR SELECT
  USING (
    "client_id" IN (
      SELECT "client_id" FROM "public"."clients"
      WHERE "trainer_id" = "auth"."uid"()
    )
  );
```

- [ ] **Step 2: Migration 適用確認**

Run:
```bash
cd fit-connect-mobile/supabase
supabase db reset  # ローカル確認
# または supabase migration up
```
Expected: エラーなく完了、`sleep_records` テーブルと RLS 5ポリシーが作成される

- [ ] **Step 3: RLS動作確認（手動）**

Supabase Studio で `sleep_records` テーブルを確認し:
- SELECT policy が 2件（本人 + トレーナー）
- INSERT/UPDATE/DELETE policy が各1件
- UNIQUE制約 `(client_id, recorded_date)` が存在
- CHECK制約 3件（source, wakeup_rating, has_data）が存在

- [ ] **Step 4: Commit**

```bash
cd fit-connect-mobile
git add supabase/migrations/20260419210000_create_sleep_records.sql
git commit -m "feat(db): sleep_records テーブル追加（HealthKit連携+手動評価対応）"
```

---

## Task 2: SleepRecord Dart モデル

**Owner:** riverpod agent

**Files:**
- Create: `fit-connect-mobile/lib/features/sleep_records/models/sleep_record_model.dart`
- Create (生成): `sleep_record_model.g.dart`

**Spec reference:** §4 Dart モデル

**Pattern reference:** `lib/features/weight_records/models/weight_record_model.dart`（JSONキー命名、DateTimeConverter 使用）

- [ ] **Step 1: enum 定義ファイル作成**

`lib/features/sleep_records/models/sleep_record_model.dart`:

```dart
import 'package:json_annotation/json_annotation.dart';
import '../../../shared/converters/date_time_converter.dart';

part 'sleep_record_model.g.dart';

enum WakeupRating {
  @JsonValue(1) groggy,    // だるい
  @JsonValue(2) okay,      // まあまあ
  @JsonValue(3) refreshed; // すっきり

  String get labelJa => switch (this) {
    WakeupRating.groggy   => 'だるい',
    WakeupRating.okay     => 'まあまあ',
    WakeupRating.refreshed => 'すっきり',
  };
}

enum SleepSource {
  @JsonValue('healthkit') healthkit,
  @JsonValue('manual')    manual,
}

enum SleepStage { deep, light, rem, awake }

@JsonSerializable()
class SleepRecord {
  final String id;
  @JsonKey(name: 'client_id')
  final String clientId;
  @JsonKey(name: 'recorded_date')
  final String recordedDate; // "YYYY-MM-DD"

  @DateTimeConverter()
  @JsonKey(name: 'bed_time')
  final DateTime? bedTime;

  @DateTimeConverter()
  @JsonKey(name: 'wake_time')
  final DateTime? wakeTime;

  @JsonKey(name: 'total_sleep_minutes')
  final int? totalSleepMinutes;
  @JsonKey(name: 'deep_minutes')
  final int? deepMinutes;
  @JsonKey(name: 'light_minutes')
  final int? lightMinutes;
  @JsonKey(name: 'rem_minutes')
  final int? remMinutes;
  @JsonKey(name: 'awake_minutes')
  final int? awakeMinutes;

  @JsonKey(name: 'wakeup_rating')
  final WakeupRating? wakeupRating;

  final SleepSource source;

  @DateTimeConverter()
  @JsonKey(name: 'created_at')
  final DateTime createdAt;

  @DateTimeConverter()
  @JsonKey(name: 'updated_at')
  final DateTime updatedAt;

  const SleepRecord({
    required this.id,
    required this.clientId,
    required this.recordedDate,
    this.bedTime,
    this.wakeTime,
    this.totalSleepMinutes,
    this.deepMinutes,
    this.lightMinutes,
    this.remMinutes,
    this.awakeMinutes,
    this.wakeupRating,
    required this.source,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SleepRecord.fromJson(Map<String, dynamic> json) =>
      _$SleepRecordFromJson(json);
  Map<String, dynamic> toJson() => _$SleepRecordToJson(this);

  bool get hasObjectiveData => totalSleepMinutes != null;

  Duration? get totalDuration =>
      totalSleepMinutes != null ? Duration(minutes: totalSleepMinutes!) : null;

  Map<SleepStage, int>? get stageBreakdown {
    if (!hasObjectiveData) return null;
    return {
      SleepStage.deep:  deepMinutes  ?? 0,
      SleepStage.light: lightMinutes ?? 0,
      SleepStage.rem:   remMinutes   ?? 0,
      SleepStage.awake: awakeMinutes ?? 0,
    };
  }
}
```

- [ ] **Step 2: build_runner 実行**

Run:
```bash
cd fit-connect-mobile
dart run build_runner build --delete-conflicting-outputs
```
Expected: `sleep_record_model.g.dart` 生成、コンパイルエラーなし

- [ ] **Step 3: コンパイル確認**

Run: `flutter analyze lib/features/sleep_records/`
Expected: エラー0、warning も0

- [ ] **Step 4: Commit**

```bash
git add lib/features/sleep_records/models/
git commit -m "feat(models): SleepRecord + enums (WakeupRating, SleepSource, SleepStage)"
```

---

## Task 3: タイムゾーンユーティリティ + ユニットテスト

**Owner:** riverpod agent（純粋ロジックのためテスト先行で）

**Files:**
- Create: `lib/features/sleep_records/data/sleep_date_utils.dart`
- Create: `test/features/sleep_records/sleep_date_utils_test.dart`

**Spec reference:** §4 タイムゾーン方針、§11 lessons.md 参照

- [ ] **Step 1: 失敗テストを書く**

`test/features/sleep_records/sleep_date_utils_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sleep_records/data/sleep_date_utils.dart';

void main() {
  group('jstDateKey', () {
    test('UTC 14:00 → JST 23:00 (same day)', () {
      final utc = DateTime.utc(2026, 4, 19, 14, 0);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('UTC 15:00 → JST 00:00 (next day) — day boundary', () {
      final utc = DateTime.utc(2026, 4, 19, 15, 0);
      expect(jstDateKey(utc), '2026-04-20');
    });

    test('UTC 22:00 4/18 → JST 07:00 4/19 (typical morning wake)', () {
      final utc = DateTime.utc(2026, 4, 18, 22, 0);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('UTC 14:59:59 → JST 23:59:59 same day', () {
      final utc = DateTime.utc(2026, 4, 19, 14, 59, 59);
      expect(jstDateKey(utc), '2026-04-19');
    });

    test('zero-pads month and day', () {
      final utc = DateTime.utc(2026, 1, 5, 2, 0);
      expect(jstDateKey(utc), '2026-01-05');
    });
  });

  group('todayJstDateKey', () {
    test('returns valid YYYY-MM-DD format', () {
      final result = todayJstDateKey();
      expect(result, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    });
  });
}
```

- [ ] **Step 2: テストを実行して失敗を確認**

Run: `flutter test test/features/sleep_records/sleep_date_utils_test.dart`
Expected: FAIL（未実装エラー）

- [ ] **Step 3: 最小実装**

`lib/features/sleep_records/data/sleep_date_utils.dart`:

```dart
/// JST (UTC+9) の起床日を 'YYYY-MM-DD' 文字列で返す。
/// docs/tasks/lessons.md 参照: DateTime比較は文字列化で行う。
String jstDateKey(DateTime dateTime) {
  final jst = dateTime.toUtc().add(const Duration(hours: 9));
  return '${jst.year.toString().padLeft(4, '0')}-'
         '${jst.month.toString().padLeft(2, '0')}-'
         '${jst.day.toString().padLeft(2, '0')}';
}

/// 今日の JST 日付キー
String todayJstDateKey() => jstDateKey(DateTime.now());

/// 指定日から過去 [daysBack] 日前の日付キー
String jstDateKeyDaysAgo(int daysBack) =>
    jstDateKey(DateTime.now().subtract(Duration(days: daysBack)));
```

- [ ] **Step 4: テスト再実行で合格確認**

Run: `flutter test test/features/sleep_records/sleep_date_utils_test.dart`
Expected: All tests PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/sleep_records/data/sleep_date_utils.dart test/features/sleep_records/
git commit -m "feat(sleep): JST日付キーユーティリティ + テスト"
```

---

## Task 4: HealthRepository に getSleepData() 追加

**Owner:** riverpod agent

**Files:**
- Modify: `lib/features/health/data/health_repository.dart`

**Spec reference:** §3 レイヤ責任、§4 同期ロジック

**パッケージ**: `health: ^11.0.0`（既導入）は iOS HealthKit + Android Health Connect の睡眠タイプを抽象化している。

- [ ] **Step 1: requestPermission を睡眠対応に拡張**

既存の `requestPermission()` メソッドに `HealthDataType.SLEEP_ASLEEP`, `HealthDataType.SLEEP_DEEP`, `HealthDataType.SLEEP_LIGHT`, `HealthDataType.SLEEP_REM`, `HealthDataType.SLEEP_AWAKE` を追加して要求する。

体重連携との互換性: 引数 `{bool includeSleep = false}` を追加し、デフォルト動作は既存通り（体重のみ）。

```dart
Future<bool> requestPermission({bool includeSleep = false}) async {
  final types = <HealthDataType>[HealthDataType.WEIGHT];
  if (includeSleep) {
    types.addAll([
      HealthDataType.SLEEP_ASLEEP,
      HealthDataType.SLEEP_DEEP,
      HealthDataType.SLEEP_LIGHT,
      HealthDataType.SLEEP_REM,
      HealthDataType.SLEEP_AWAKE,
      HealthDataType.SLEEP_IN_BED,
    ]);
  }
  return await _health.requestAuthorization(types);
}
```

- [ ] **Step 2: hasPermission を拡張**

睡眠タイプの権限確認も可能にする（`{bool forSleep = false}` 引数）。

- [ ] **Step 3: getSleepData() 実装**

```dart
import '../../sleep_records/data/sleep_date_utils.dart';

/// 起床日ごとにメインセッション1件を返す。
/// 返却: Map<recordedDate(YYYY-MM-DD), SleepSessionData>
Future<Map<String, SleepSessionData>> getSleepData({
  required DateTime startDate,
  DateTime? endDate,
}) async {
  final end = endDate ?? DateTime.now().add(const Duration(days: 1));

  final sleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_IN_BED,
  ];

  final data = await _health.getHealthDataFromTypes(
    startTime: startDate,
    endTime: end,
    types: sleepTypes,
  );

  // 起床日キー別にセグメントをグループ化
  final byDate = <String, List<HealthDataPoint>>{};
  for (final p in data) {
    final key = jstDateKey(p.dateTo); // 終了時刻=起床側を日付の基準に
    byDate.putIfAbsent(key, () => []).add(p);
  }

  final result = <String, SleepSessionData>{};
  byDate.forEach((date, points) {
    final session = _aggregateMainSession(points);
    if (session != null) result[date] = session;
  });
  return result;
}

/// メインセッション判定: その日最も長いまとまりを採用。
/// 各ステージの合計を分で集計。bed/wake は最早開始・最遅終了。
SleepSessionData? _aggregateMainSession(List<HealthDataPoint> points) {
  if (points.isEmpty) return null;

  // ASLEEP/IN_BED 含む全セグメントからメイン期間を判定
  // （簡略化: 全点のmin(dateFrom) 〜 max(dateTo)をメインセッションとみなす）
  points.sort((a, b) => a.dateFrom.compareTo(b.dateFrom));
  final bed = points.first.dateFrom;
  final wake = points
      .map((p) => p.dateTo)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  int deep = 0, light = 0, rem = 0, awake = 0, asleep = 0;
  for (final p in points) {
    final mins = p.dateTo.difference(p.dateFrom).inMinutes;
    switch (p.type) {
      case HealthDataType.SLEEP_DEEP:  deep  += mins; break;
      case HealthDataType.SLEEP_LIGHT: light += mins; break;
      case HealthDataType.SLEEP_REM:   rem   += mins; break;
      case HealthDataType.SLEEP_AWAKE: awake += mins; break;
      case HealthDataType.SLEEP_ASLEEP: asleep += mins; break;
      case HealthDataType.SLEEP_IN_BED: /* ignored for total */ break;
      default: break;
    }
  }

  // ステージ明細が無く ASLEEP のみの場合は total に寄せる
  final total = (deep + light + rem) > 0 ? (deep + light + rem + awake) : (asleep + awake);
  if (total <= 0) return null;

  return SleepSessionData(
    bedTime: bed,
    wakeTime: wake,
    totalSleepMinutes: total,
    deepMinutes: deep,
    lightMinutes: light,
    remMinutes: rem,
    awakeMinutes: awake,
  );
}

class SleepSessionData {
  final DateTime bedTime;
  final DateTime wakeTime;
  final int totalSleepMinutes;
  final int deepMinutes;
  final int lightMinutes;
  final int remMinutes;
  final int awakeMinutes;

  const SleepSessionData({
    required this.bedTime,
    required this.wakeTime,
    required this.totalSleepMinutes,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
  });
}
```

- [ ] **Step 4: コンパイル確認**

Run: `flutter analyze lib/features/health/`
Expected: エラー0

- [ ] **Step 5: Commit**

```bash
git add lib/features/health/data/health_repository.dart
git commit -m "feat(health): getSleepData() 追加、権限リクエストを睡眠対応に拡張"
```

---

## Task 5: SleepRecordsProvider 実装

**Owner:** riverpod agent

**Files:**
- Create: `lib/features/sleep_records/providers/sleep_records_provider.dart`

**Spec reference:** §3 レイヤ責任、§4 UPSERT戦略

**Pattern reference:** `lib/features/weight_records/providers/weight_records_provider.dart`

**Pre-task: 既存パターン確認（必須）**

実装着手前に以下を読み、既存の認証状態・クライアントID取得パターンを特定すること:
- `lib/features/weight_records/providers/weight_records_provider.dart` 全体
- `lib/features/auth/providers/auth_provider.dart` 全体
- `lib/services/supabase_service.dart` の client ID取得ヘルパー

weight_records で「現在ログイン中のclientId」を取得している方法（例: `ref.read(authStateProvider).client?.clientId` か `SupabaseService.client.auth.currentUser?.id` か）を特定し、**同じパターンを使用**する。`currentClientIdProvider` が既存に無ければ新規作成せず、既存の取得方法にインラインで合わせる。

- [ ] **Step 1: Provider 定義**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import '../../../services/supabase_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../data/sleep_date_utils.dart';
import '../models/sleep_record_model.dart';

part 'sleep_records_provider.g.dart';

@riverpod
class SleepRecords extends _$SleepRecords {
  @override
  Future<List<SleepRecord>> build({int limit = 30}) async {
    final clientId = ref.watch(currentClientIdProvider);
    if (clientId == null) return [];

    final res = await SupabaseService.client
      .from('sleep_records')
      .select()
      .eq('client_id', clientId)
      .order('recorded_date', ascending: false)
      .limit(limit);

    return (res as List).map((e) => SleepRecord.fromJson(e)).toList();
  }

  /// HealthKit同期時 - 客観データを UPSERT、wakeup_rating は保持
  Future<void> upsertObjectiveData({
    required String recordedDate,
    required DateTime bedTime,
    required DateTime wakeTime,
    required int totalSleepMinutes,
    required int deepMinutes,
    required int lightMinutes,
    required int remMinutes,
    required int awakeMinutes,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) return;

    // wakeup_rating を含めない → 既存値保持
    await SupabaseService.client
      .from('sleep_records')
      .upsert({
        'client_id': clientId,
        'recorded_date': recordedDate,
        'bed_time': bedTime.toUtc().toIso8601String(),
        'wake_time': wakeTime.toUtc().toIso8601String(),
        'total_sleep_minutes': totalSleepMinutes,
        'deep_minutes': deepMinutes,
        'light_minutes': lightMinutes,
        'rem_minutes': remMinutes,
        'awake_minutes': awakeMinutes,
        'source': 'healthkit',
      }, onConflict: 'client_id,recorded_date');

    ref.invalidateSelf();
    ref.invalidate(todaySleepRecordProvider);
  }

  /// 手動評価 UPSERT - 既存レコードあれば rating のみ更新、無ければ manual で新規作成
  Future<void> upsertWakeupRating({
    required String recordedDate,
    required WakeupRating rating,
  }) async {
    final clientId = ref.read(currentClientIdProvider);
    if (clientId == null) throw StateError('No client id');

    // 既存確認
    final existing = await SupabaseService.client
      .from('sleep_records')
      .select('id, source')
      .eq('client_id', clientId)
      .eq('recorded_date', recordedDate)
      .maybeSingle();

    if (existing == null) {
      await SupabaseService.client.from('sleep_records').insert({
        'client_id': clientId,
        'recorded_date': recordedDate,
        'wakeup_rating': rating.index + 1, // 1,2,3
        'source': 'manual',
      });
    } else {
      await SupabaseService.client
        .from('sleep_records')
        .update({'wakeup_rating': rating.index + 1})
        .eq('id', existing['id']);
    }

    ref.invalidateSelf();
    ref.invalidate(todaySleepRecordProvider);
  }
}

@riverpod
Future<SleepRecord?> todaySleepRecord(TodaySleepRecordRef ref) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return null;

  final today = todayJstDateKey();
  final res = await SupabaseService.client
    .from('sleep_records')
    .select()
    .eq('client_id', clientId)
    .eq('recorded_date', today)
    .maybeSingle();

  return res == null ? null : SleepRecord.fromJson(res);
}

@riverpod
Future<List<SleepRecord>> recentSleepRecords(
  RecentSleepRecordsRef ref, {
  int days = 7,
}) async {
  final clientId = ref.watch(currentClientIdProvider);
  if (clientId == null) return [];

  final from = jstDateKeyDaysAgo(days);
  final res = await SupabaseService.client
    .from('sleep_records')
    .select()
    .eq('client_id', clientId)
    .gte('recorded_date', from)
    .order('recorded_date', ascending: false);

  return (res as List).map((e) => SleepRecord.fromJson(e)).toList();
}
```

**注**: `currentClientIdProvider` が既存auth providerに存在するか要確認。無ければ `auth_provider.dart` の `authStateProvider` から取得する形に変更。

- [ ] **Step 2: enum ↔ DB値マッピング確認**

`WakeupRating.groggy.index == 0` なので `.index + 1` で 1,2,3 に。逆変換は `WakeupRating.values[value - 1]`。既存 @JsonValue アノテーションが正しく動くかも確認。

- [ ] **Step 3: build_runner**

```bash
dart run build_runner build --delete-conflicting-outputs
```

- [ ] **Step 4: コンパイル確認**

```bash
flutter analyze lib/features/sleep_records/
```

- [ ] **Step 5: Commit**

```bash
git add lib/features/sleep_records/providers/sleep_records_provider.dart lib/features/sleep_records/providers/sleep_records_provider.g.dart
git commit -m "feat(sleep): SleepRecords provider (UPSERT戦略、rating保持)"
```

---

## Task 6: MorningDialogProvider + テスト

**Owner:** riverpod agent

**Files:**
- Create: `lib/features/sleep_records/providers/morning_dialog_provider.dart`
- Create: `test/features/sleep_records/morning_dialog_shouldshow_test.dart`

**Spec reference:** §5-C 表示条件

- [ ] **Step 1: テスト先行**

```dart
// shouldShowMorningDialog の純粋関数をテスト
import 'package:flutter_test/flutter_test.dart';
import 'package:fit_connect_mobile/features/sleep_records/providers/morning_dialog_provider.dart';

void main() {
  group('shouldShowMorningDialog', () {
    final now_0359 = DateTime(2026, 4, 19, 3, 59);
    final now_0400 = DateTime(2026, 4, 19, 4, 0);
    final now_1159 = DateTime(2026, 4, 19, 11, 59);
    final now_1200 = DateTime(2026, 4, 19, 12, 0);

    test('時間外(3:59)は表示しない', () {
      expect(shouldShowMorningDialog(
        now: now_0359,
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('4:00ちょうどは表示する', () {
      expect(shouldShowMorningDialog(
        now: now_0400,
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), true);
    });

    test('11:59は表示する', () {
      expect(shouldShowMorningDialog(
        now: now_1159,
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), true);
    });

    test('12:00ちょうどは表示しない', () {
      expect(shouldShowMorningDialog(
        now: now_1200,
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('設定OFFなら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: false,
        hasWakeupRatingToday: false,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('当日評価済みなら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: true,
        dismissedDate: null,
        todayKey: '2026-04-19',
      ), false);
    });

    test('今日dismissしてたら表示しない', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: '2026-04-19',
        todayKey: '2026-04-19',
      ), false);
    });

    test('昨日dismissしてたら今日は表示する', () {
      expect(shouldShowMorningDialog(
        now: DateTime(2026, 4, 19, 8, 0),
        morningDialogEnabled: true,
        hasWakeupRatingToday: false,
        dismissedDate: '2026-04-18',
        todayKey: '2026-04-19',
      ), true);
    });
  });
}
```

- [ ] **Step 2: テスト実行して失敗確認**

Run: `flutter test test/features/sleep_records/morning_dialog_shouldshow_test.dart`
Expected: FAIL

- [ ] **Step 3: 実装**

```dart
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../health/providers/health_provider.dart';
import '../data/sleep_date_utils.dart';
import 'sleep_records_provider.dart';

part 'morning_dialog_provider.g.dart';

const _kDismissedDateKey = 'morning_dialog_dismissed_date';

/// 純粋関数（テスト容易性のため）
bool shouldShowMorningDialog({
  required DateTime now,
  required bool morningDialogEnabled,
  required bool hasWakeupRatingToday,
  required String? dismissedDate,
  required String todayKey,
}) {
  if (!morningDialogEnabled) return false;
  if (hasWakeupRatingToday) return false;
  if (dismissedDate == todayKey) return false;
  if (now.hour < 4 || now.hour >= 12) return false;
  return true;
}

@riverpod
class MorningDialog extends _$MorningDialog {
  @override
  Future<bool> build() async {
    final settings = await ref.watch(healthSettingsProvider.future);
    if (!settings.isMorningDialogEnabled) return false;

    final today = await ref.watch(todaySleepRecordProvider.future);
    final hasRating = today?.wakeupRating != null;

    final prefs = await SharedPreferences.getInstance();
    final dismissed = prefs.getString(_kDismissedDateKey);

    return shouldShowMorningDialog(
      now: DateTime.now(),
      morningDialogEnabled: true,
      hasWakeupRatingToday: hasRating,
      dismissedDate: dismissed,
      todayKey: todayJstDateKey(),
    );
  }

  Future<void> dismissToday() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kDismissedDateKey, todayJstDateKey());
    ref.invalidateSelf();
  }
}
```

- [ ] **Step 4: build_runner + テスト再実行**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter test test/features/sleep_records/morning_dialog_shouldshow_test.dart
```
Expected: PASS

- [ ] **Step 5: Commit**

```bash
git add lib/features/sleep_records/providers/morning_dialog_provider.dart lib/features/sleep_records/providers/morning_dialog_provider.g.dart test/features/sleep_records/morning_dialog_shouldshow_test.dart
git commit -m "feat(sleep): MorningDialog provider + shouldShow 判定テスト"
```

---

## Task 7: HealthSettings 拡張（睡眠+朝ダイアログ設定）

**Owner:** riverpod agent

**Files:**
- Modify: `lib/features/health/providers/health_provider.dart`

**Spec reference:** §9 既存コードへの影響

- [ ] **Step 1: HealthSettingsState に2フィールド追加**

`health_provider.dart` の `HealthSettingsState` クラスに:

```dart
class HealthSettingsState {
  final bool isEnabled;
  final bool isWeightEnabled;
  final bool isSleepEnabled;          // 追加
  final bool isMorningDialogEnabled;  // 追加
  final DateTime? lastSyncAt;
  // ... copyWith, コンストラクタも更新
}
```

- [ ] **Step 2: Notifier に対応メソッド追加**

```dart
static const _keySleepEnabled = 'health_sleep_enabled';
static const _keyMorningDialogEnabled = 'health_morning_dialog_enabled';

// build() 内で SharedPreferences から読込（デフォルト false/true を spec で決定）
// デフォルト: sleepEnabled=false, morningDialogEnabled=true（spec §5-C 推奨）

Future<void> toggleSleepEnabled(bool value) async {
  // sleep ON 時は HealthRepository.requestPermission(includeSleep: true) を呼ぶ
  final repo = ref.read(healthRepositoryProvider);
  if (value) {
    final granted = await repo.requestPermission(includeSleep: true);
    if (!granted) return; // 拒否された場合は状態変更しない
  }
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keySleepEnabled, value);
  state = AsyncData(state.value!.copyWith(isSleepEnabled: value));
}

Future<void> toggleMorningDialogEnabled(bool value) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_keyMorningDialogEnabled, value);
  state = AsyncData(state.value!.copyWith(isMorningDialogEnabled: value));
}
```

- [ ] **Step 3: build_runner + 分析**

```bash
dart run build_runner build --delete-conflicting-outputs
flutter analyze lib/features/health/providers/
```

- [ ] **Step 4: Commit**

```bash
git add lib/features/health/providers/health_provider.dart lib/features/health/providers/health_provider.g.dart
git commit -m "feat(health): HealthSettings に isSleepEnabled, isMorningDialogEnabled 追加"
```

---

## Task 8: syncSleep() + 体重/睡眠独立エラーハンドリング

**Owner:** riverpod agent

**Files:**
- Modify: `lib/features/health/providers/health_sync_provider.dart`

**Spec reference:** §4 UPSERT戦略、§11 エラーハンドリング

- [ ] **Step 1: _syncSleep() プライベートメソッド実装**

```dart
Future<void> _syncSleep(String clientId, DateTime lastSyncAt) async {
  final repo = ref.read(healthRepositoryProvider);
  final settings = await ref.read(healthSettingsProvider.future);
  if (!settings.isSleepEnabled) return;

  final startDate = DateTime.now().subtract(const Duration(days: 30));
  final from = lastSyncAt.isAfter(startDate) ? lastSyncAt : startDate;

  final sleepData = await repo.getSleepData(startDate: from);

  final sleepRecordsNotifier = ref.read(sleepRecordsProvider().notifier);
  for (final entry in sleepData.entries) {
    final date = entry.key;
    final s = entry.value;
    await sleepRecordsNotifier.upsertObjectiveData(
      recordedDate: date,
      bedTime: s.bedTime,
      wakeTime: s.wakeTime,
      totalSleepMinutes: s.totalSleepMinutes,
      deepMinutes: s.deepMinutes,
      lightMinutes: s.lightMinutes,
      remMinutes: s.remMinutes,
      awakeMinutes: s.awakeMinutes,
    );
  }

  ref.invalidate(todaySleepRecordProvider);
  ref.invalidate(recentSleepRecordsProvider);
}
```

- [ ] **Step 2: 既存 _sync() を _syncWeight() に切り出す（リファクタ）**

既存の `lib/features/health/providers/health_sync_provider.dart` の `_sync()` メソッド（L82-173想定）内で体重処理を行っている部分（`filterHealthData()` 呼び出し〜`weightRepo.createWeightRecordWithSource()` のループまで）を、**ロジックを変えずに** `Future<void> _syncWeight(String clientId, DateTime lastSyncAt)` というプライベートメソッドに抽出。

ポイント:
- 抽出時に引数を明示化（clientId, lastSyncAt, settings）することで `_syncSleep` との対称性を保つ
- `ref.invalidate(weightRecordsProvider)` 等の provider invalidation は `_syncWeight` 内に残す
- `updateLastSyncAt` の呼び出しは `_sync()` の最後に残す（体重+睡眠が完了した後）

Diff を小さくするコツ: 体重処理のコードブロックをそのままメソッド化し、元の位置は `await _syncWeight(clientId, lastSyncAt);` に置換のみ。振る舞いを変えない（既存テスト・動作が退行しないことを確認）。

- [ ] **Step 3: _sync() を体重+睡眠独立呼び出しに改修**

切り出し後の `_sync()` メソッドを以下に書き換え:

```dart
Future<void> _sync() async {
  final settings = await ref.read(healthSettingsProvider.future);
  if (!settings.isEnabled) return;
  final clientId = /* existing */;
  final lastSyncAt = settings.lastSyncAt ?? DateTime.now().subtract(const Duration(days: 30));

  bool weightOk = false, sleepOk = false;
  try {
    if (settings.isWeightEnabled) {
      await _syncWeight(clientId, lastSyncAt);  // 既存ロジックを関数化
      weightOk = true;
    } else {
      weightOk = true; // 無効化されているので成功扱い
    }
  } catch (e) {
    debugPrint('[HealthSync] 体重同期エラー: $e');
  }

  try {
    if (settings.isSleepEnabled) {
      await _syncSleep(clientId, lastSyncAt);
      sleepOk = true;
    } else {
      sleepOk = true;
    }
  } catch (e) {
    debugPrint('[HealthSync] 睡眠同期エラー: $e');
  }

  // 最終同期時刻は両方成功した時だけ更新（次回再試行余地）
  if (weightOk && sleepOk) {
    await ref.read(healthSettingsProvider.notifier).updateLastSyncAt(DateTime.now());
  }
}
```

- [ ] **Step 4: import 追加**

```dart
import '../../sleep_records/providers/sleep_records_provider.dart';
import '../../sleep_records/data/sleep_date_utils.dart';
```

- [ ] **Step 5: 分析**

```bash
flutter analyze lib/features/health/providers/
```

- [ ] **Step 6: 既存体重同期の動作確認**

切り出しでリグレッションが起きていないことを確認:
- アプリ起動、設定画面で体重連携 ON
- 手動同期実行 → 体重記録が weight_records に入ることを確認

- [ ] **Step 7: Commit**

```bash
git add lib/features/health/providers/health_sync_provider.dart
git commit -m "feat(health): syncSleep() 追加、体重/睡眠を独立エラーハンドリング"
```

---

## Task 9: WakeupRatingSelector Widget

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart`

**Spec reference:** §5-C, §5-D, hi-fi: `hifi-dialogs.jsx:37-58`（3オプションボタン部分）

**Hi-fi参照**: 絵文字 + ラベル、選択時は primary50 背景 + primary ボーダー + primary テキスト、非選択時は slate100 背景。

- [ ] **Step 1: Widget 実装**

```dart
class WakeupRatingSelector extends StatelessWidget {
  final WakeupRating? selected;
  final ValueChanged<WakeupRating> onSelect;

  const WakeupRatingSelector({
    super.key,
    this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _option(context, WakeupRating.refreshed, '😊', 'すっきり'),
        const SizedBox(height: 8),
        _option(context, WakeupRating.okay, '😐', 'まあまあ'),
        const SizedBox(height: 8),
        _option(context, WakeupRating.groggy, '😫', 'だるい'),
      ],
    );
  }

  Widget _option(BuildContext context, WakeupRating value, String emoji, String label) {
    final isSelected = selected == value;
    final colors = AppColorsExtension.of(context);

    return Material(
      color: isSelected ? colors.accentIndigo : colors.surfaceDim,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => onSelect(value),
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? AppColors.primary : Colors.transparent,
              width: 2,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(emoji, style: const TextStyle(fontSize: 24)),
              const SizedBox(width: 14),
              Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                  color: isSelected ? AppColors.primary : colors.textPrimary,
                  letterSpacing: -0.01,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

- [ ] **Step 2: プレビュー関数追加**

CLAUDE.md ルールに従い、ファイル末尾に:

```dart
@Preview(name: 'WakeupRatingSelector - Unselected')
Widget previewWakeupRatingSelectorUnselected() { ... }

@Preview(name: 'WakeupRatingSelector - Selected Refreshed')
Widget previewWakeupRatingSelectorRefreshed() { ... }
```

- [ ] **Step 3: 分析 + プレビュー確認**

```bash
flutter analyze lib/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart
```
手動: `flutter widget-preview start` で表示確認

- [ ] **Step 4: Commit**

```bash
git add lib/features/sleep_records/presentation/widgets/wakeup_rating_selector.dart
git commit -m "feat(sleep): WakeupRatingSelector widget + プレビュー"
```

---

## Task 10: SleepStageBar Widget（案A水平スタックバー）

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/sleep_stage_bar.dart`
- Modify: `lib/core/theme/app_colors.dart`（sleepStage* フィールド追加）

**Spec reference:** §5-F、hi-fi: `hifi-charts.jsx:31-48`

- [ ] **Step 1: AppColorsExtension に sleepStage フィールド追加**

`lib/core/theme/app_colors.dart`:

```dart
class AppColorsExtension extends ThemeExtension<AppColorsExtension> {
  // ... 既存フィールド
  final Color sleepStageDeep;
  final Color sleepStageLight;
  final Color sleepStageRem;
  final Color sleepStageAwake;

  // light preset:
  sleepStageDeep:  Color(0xFF4338CA),
  sleepStageLight: Color(0xFF818CF8),
  sleepStageRem:   Color(0xFF60A5FA),
  sleepStageAwake: Color(0xFFE2E8F0),

  // dark preset:
  sleepStageDeep:  Color(0xFF6366F1),
  sleepStageLight: Color(0xFF818CF8),
  sleepStageRem:   Color(0xFF60A5FA),
  sleepStageAwake: Color(0xFF475569),
```

copyWith, lerp にも追加。

- [ ] **Step 2: SleepStageBar 実装**

```dart
class SleepStageBar extends StatelessWidget {
  final int deepMinutes, lightMinutes, remMinutes, awakeMinutes;
  final double height;

  const SleepStageBar({
    super.key,
    required this.deepMinutes,
    required this.lightMinutes,
    required this.remMinutes,
    required this.awakeMinutes,
    this.height = 28,
  });

  @override
  Widget build(BuildContext context) {
    final colors = AppColorsExtension.of(context);
    final total = deepMinutes + lightMinutes + remMinutes + awakeMinutes;
    if (total == 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            height: height,
            child: Row(
              children: [
                Expanded(flex: deepMinutes,  child: Container(color: colors.sleepStageDeep)),
                Expanded(flex: lightMinutes, child: Container(color: colors.sleepStageLight)),
                Expanded(flex: remMinutes,   child: Container(color: colors.sleepStageRem)),
                Expanded(flex: awakeMinutes, child: Container(color: colors.sleepStageAwake)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        _legend(context, total),
      ],
    );
  }

  Widget _legend(BuildContext context, int total) {
    final colors = AppColorsExtension.of(context);
    final items = [
      ('深い', colors.sleepStageDeep, deepMinutes),
      ('浅い', colors.sleepStageLight, lightMinutes),
      ('REM',  colors.sleepStageRem, remMinutes),
      ('覚醒', colors.sleepStageAwake, awakeMinutes),
    ];
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 6,
      mainAxisSpacing: 6,
      crossAxisSpacing: 12,
      children: items.map((it) => _legendItem(context, it.$1, it.$2, it.$3, total)).toList(),
    );
  }

  Widget _legendItem(BuildContext context, String label, Color color, int mins, int total) {
    final pct = ((mins / total) * 100).round();
    final h = mins ~/ 60;
    final m = mins % 60;
    final colors = AppColorsExtension.of(context);
    return Row(
      children: [
        Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 7),
        Text(label, style: TextStyle(fontSize: 12, color: colors.textSecondary, fontWeight: FontWeight.w500)),
        const SizedBox(width: 6),
        Text('$pct%', style: TextStyle(fontSize: 12, color: colors.textPrimary, fontWeight: FontWeight.w600)),
        const SizedBox(width: 4),
        Text('(${h}h${m}m)', style: TextStyle(fontSize: 11, color: colors.textHint)),
      ],
    );
  }
}
```

- [ ] **Step 3: プレビュー関数追加**

- [ ] **Step 4: 分析 + Commit**

```bash
flutter analyze lib/core/theme/app_colors.dart lib/features/sleep_records/presentation/widgets/sleep_stage_bar.dart
git add lib/core/theme/app_colors.dart lib/features/sleep_records/presentation/widgets/sleep_stage_bar.dart
git commit -m "feat(sleep): SleepStageBar(案A) + AppColorsExtension に stage 色追加"
```

---

## Task 11: SleepWeekChart Widget

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/sleep_week_chart.dart`

**Spec reference:** §5-B、hi-fi: `hifi-charts.jsx:104-196`

**要件**:
- `fl_chart` LineChart 使用
- 7日分、null値（データ無し）は点線ギャップ + 中空ノード
- area fill（primary色を透明→不透明）
- X軸ラベル下に目覚めアイコン併記

- [ ] **Step 1: Widget 実装（fl_chart）**

入力: `List<DailySleepEntry>` where `DailySleepEntry { String dateLabel; double? hours; WakeupRating? rating; }`

- [ ] **Step 2: プレビュー関数**

- [ ] **Step 3: 分析 + Commit**

```bash
flutter analyze lib/features/sleep_records/presentation/widgets/sleep_week_chart.dart
git add lib/features/sleep_records/presentation/widgets/sleep_week_chart.dart
git commit -m "feat(sleep): SleepWeekChart (fl_chart LineChart + null日処理)"
```

---

## Task 12: SleepHistoryListItem Widget

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/sleep_history_list_item.dart`

**Spec reference:** §5-B 履歴、hi-fi: `hifi-sleep-screen.jsx:142-167`

- [ ] **Step 1: 実装**

高さ56px、日付(54px) / 時間(flex) / 目覚めアイコン(22px) / ソースアイコン(14px) / chevron の構成。`onTap` コールバック対応。

- [ ] **Step 2: プレビュー関数（HealthKit行 / Manual行 / Rating無し行）**

- [ ] **Step 3: Commit**

---

## Task 13: MorningWakeupDialog Widget

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/morning_wakeup_dialog.dart`

**Spec reference:** §5-C、hi-fi: `hifi-dialogs.jsx:3-80`

**要件**:
- `showDialog` で呼び出されるStatefulWidget
- 背景ブラー: `BackdropFilter(filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6))`
- WakeupRatingSelector（T9）を再利用
- 「あとで」「今日は聞かない」ボタン
- 選択時: `ref.read(sleepRecordsProvider().notifier).upsertWakeupRating(...)` → pop → スナックバー

- [ ] **Step 1: Widget 実装**

- [ ] **Step 2: 呼び出しヘルパー追加**

```dart
Future<void> showMorningWakeupDialog(BuildContext context) async {
  // 多重表示ガード: 既に同ダイアログが開いてたらスキップ
  await showDialog(
    context: context,
    barrierDismissible: false,
    builder: (_) => const MorningWakeupDialog(),
  );
}
```

- [ ] **Step 3: プレビュー関数**

- [ ] **Step 4: Commit**

---

## Task 14: PermissionDeniedDialog Widget

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/permission_denied_dialog.dart`
- Modify: `pubspec.yaml`（app_settings追加）

**Spec reference:** §5-D、hi-fi: `hifi-dialogs.jsx:103-148`

- [ ] **Step 1: pubspec.yaml に app_settings 追加**

```yaml
dependencies:
  app_settings: ^5.1.1
```

Run: `flutter pub get`

- [ ] **Step 2: Widget 実装**

プラットフォーム分岐テキスト:
```dart
String get _platformMessage {
  if (Platform.isIOS) {
    return '設定アプリの「ヘルスケア」→「データアクセスとデバイス」から FIT-CONNECT に睡眠データの読み取りを許可してください。';
  }
  return 'Health Connect アプリから FIT-CONNECT に睡眠データの読み取りを許可してください。';
}
```

「設定を開く」ボタン:

```dart
// app_settings: ^5.1.1 API 確認前提
// v5.x では AppSettingsType.healthConnect が存在しない場合があるため fallback
try {
  if (Platform.isAndroid) {
    // Android は Health Connect アプリ直接が理想、未対応なら一般設定
    await AppSettings.openAppSettings();
  } else {
    // iOS は一般設定（ユーザーがヘルスケア→データアクセスへ辿る）
    await AppSettings.openAppSettings();
  }
} catch (_) {
  // fallback: 何もしない
}
```

実装着手前に `app_settings` v5.1.1 の API を pub.dev で確認し、`AppSettingsType.healthConnect` が使えるバージョンなら差し替えを検討。

- [ ] **Step 3: プレビュー関数**

- [ ] **Step 4: Commit**

---

## Task 15: SleepSummaryCard Widget（ホーム用、3状態）

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart`

**Spec reference:** §5-A、hi-fi: `hifi-summary-card.jsx`

**3状態ロジック**:

```dart
enum SleepCardState { healthkit, manual, empty }

SleepCardState _resolve(SleepRecord? today) {
  if (today == null) return SleepCardState.empty;
  if (today.hasObjectiveData) return SleepCardState.healthkit;
  return SleepCardState.manual; // rating はあるが客観データ無し
}
```

- [ ] **Step 1: Widget 実装**

`ConsumerWidget` で `ref.watch(todaySleepRecordProvider)` → AsyncValue 処理 → 3状態分岐で表示。

empty状態のCTAタップで、 `WakeupRatingSelector` を `showModalBottomSheet` 表示。

- [ ] **Step 2: プレビュー関数（3状態 + loading + error）**

- [ ] **Step 3: 分析 + Commit**

```bash
flutter analyze lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart
git add lib/features/sleep_records/presentation/widgets/sleep_summary_card.dart
git commit -m "feat(sleep): SleepSummaryCard (3状態 + empty時ボトムシート)"
```

---

## Task 16: ホーム画面への統合

**Owner:** flutter-ui agent

**Files:**
- Modify: `lib/features/home/presentation/screens/home_screen.dart`

- [ ] **Step 1: DailySummaryCard の下に SleepSummaryCard セクション追加**

```dart
// home_screen.dart の既存カード配置の後
const SizedBox(height: 16),
SleepSummaryCard(
  onTap: () => Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => const SleepRecordScreen()),
  ),
),
```

- [ ] **Step 2: import 追加**

- [ ] **Step 3: 手動動作確認**

iOSシミュレータでホーム表示。`SleepSummaryCard` が見える。

- [ ] **Step 4: Commit**

---

## Task 17: SleepRecordScreen（専用画面）

**Owner:** flutter-ui agent

**Files:**
- Create: `lib/features/sleep_records/presentation/screens/sleep_record_screen.dart`

**Spec reference:** §5-B、hi-fi: `hifi-sleep-screen.jsx`

**構成**: AppBar + 縦スクロール1画面（サマリー→週間→履歴）。状態ごとに UI 分岐（healthkit/manual/empty/loading/permission-denied）。

- [ ] **Step 1: 画面本体実装**

`ConsumerStatefulWidget` で `todaySleepRecord`, `recentSleepRecords`, `sleepRecords`（履歴）を watch。

右上 refresh ボタン: `healthSyncProvider.notifier.syncManual()` を呼ぶ。同期中は loading 表示。

permission-denied 時は PermissionDeniedDialog を表示。

- [ ] **Step 2: 各状態のプレビュー関数**

- [ ] **Step 3: Commit**

---

## Task 18: HealthSettingsScreen 拡張

**Owner:** flutter-ui agent

**Files:**
- Modify: `lib/features/health/presentation/screens/health_settings_screen.dart`

**Spec reference:** §5-E、hi-fi: `hifi-settings.jsx`

- [ ] **Step 1: 「Coming Soon」睡眠トグル部分（L214-265）を実装に差し替え**

- `SwitchListTile` または既存パターンのToggle使用
- ON時: `toggleSleepEnabled(true)` 呼び出し、権限拒否なら PermissionDeniedDialog 表示
- NEWバッジ付与（spec §5-E）
- アクセントアイコン: `LucideIcons.moon` / `indigo50` 背景

- [ ] **Step 2: 「通知」セクション追加 → 朝の目覚めダイアログトグル**

- アイコン: `LucideIcons.sun` / warning薄色背景
- ON/OFF は `toggleMorningDialogEnabled`

- [ ] **Step 3: インフォカード文言を汎用化**

iPhone限定 → `お使いの端末のヘルスケアデータ（iOS: ヘルスケア / Android: Health Connect）`

- [ ] **Step 4: プレビュー関数更新**

- [ ] **Step 5: Commit**

---

## Task 19: アプリ起動時 MorningDialog トリガ

**Owner:** riverpod agent（app.dart 修正）

**Files:**
- Modify: `lib/app.dart`

**Spec reference:** §5-C レースコンディション対策

- [ ] **Step 1: `_AuthLoadingScreen._syncHealthDataIfNeeded()` を拡張**

既存フローは:
```dart
ref.read(healthSyncProvider.notifier).syncOnLaunch().then((_) {
  debugPrint('[App] HealthKit同期完了');
});
```

拡張後（同期完了後にダイアログ判定、多重表示ガードはグローバルフラグで）:

```dart
class _AuthLoadingScreenState extends ConsumerState<_AuthLoadingScreen>
    with WidgetsBindingObserver {
  bool _healthSynced = false;
  bool _isMorningDialogOpen = false;  // グローバル多重表示ガード

  void _syncHealthDataAndShowDialog() async {
    if (_healthSynced) return;
    _healthSynced = true;

    try {
      await ref.read(healthSyncProvider.notifier).syncOnLaunch();
    } catch (e) {
      debugPrint('[App] 同期エラー: $e');
    }

    await _maybeShowMorningDialog();
  }

  Future<void> _maybeShowMorningDialog() async {
    if (_isMorningDialogOpen) return;           // 多重表示防止
    if (!mounted) return;

    final shouldShow = await ref.read(morningDialogProvider.future);
    if (!shouldShow || !mounted || _isMorningDialogOpen) return;

    _isMorningDialogOpen = true;
    try {
      await showMorningWakeupDialog(context);
    } finally {
      _isMorningDialogOpen = false;
    }
  }
}
```

- [ ] **Step 2: AppLifecycleState.resumed 時にも再判定**

`WidgetsBindingObserver` を混入し `didChangeAppLifecycleState()` を実装:

```dart
@override
void initState() {
  super.initState();
  WidgetsBinding.instance.addObserver(this);
}

@override
void dispose() {
  WidgetsBinding.instance.removeObserver(this);
  super.dispose();
}

@override
void didChangeAppLifecycleState(AppLifecycleState state) {
  if (state == AppLifecycleState.resumed) {
    // resumed 時は即時に再判定（同期は既に最新なので待機不要）
    ref.invalidate(morningDialogProvider);
    _maybeShowMorningDialog();
  }
}
```

- [ ] **Step 3: 分析 + Commit**

---

## Task 20: プラットフォーム設定ファイル更新

**Owner:** flutter-ui agent（プラットフォーム設定編集）

**Files:**
- Modify: `ios/Runner/Info.plist`
- Modify: `android/app/src/main/AndroidManifest.xml`

- [ ] **Step 1: iOS Info.plist 更新**

`NSHealthShareUsageDescription` の文言を更新:
```xml
<key>NSHealthShareUsageDescription</key>
<string>体重と睡眠のデータを取得して、記録と連携するために使用します。</string>
```

- [ ] **Step 2: Android マニフェスト確認**

`android/app/src/main/AndroidManifest.xml` に以下があるか確認、無ければ追加:
```xml
<uses-permission android:name="android.permission.health.READ_SLEEP"/>
```
（health パッケージが自動処理してればスキップ。package docs で要確認）

- [ ] **Step 3: Commit**

---

## Task 21: 動作検証（ios-simulator-qa）

**Owner:** メインエージェント（ios-simulator-qa skill 実行）

**Goal:** spec §8 テスト方針の Manual QA を実施

- [ ] **Step 1: ios-simulator-qa skill を実行**

以下の観点で検証:
1. 設定画面で睡眠トグルON → 権限ダイアログ → 許可 → 同期実行 → スナップ確認
2. ホーム画面で SleepSummaryCard の3状態が正しく表示される
3. SleepRecordScreen の全セクションが表示される
4. 朝ダイアログが4:00-12:00 の範囲内で表示される（シミュレータ時刻変更で検証）
5. 4:00-12:00 外では出ない
6. 「今日は聞かない」選択後、同日再起動で出ない
7. 翌日（日付変更）に再び出る
8. 手動目覚め評価が Supabase に保存される（Supabase Studio で確認）
9. HealthKitデモデータから体重+睡眠が取得できる（Health アプリに事前投入）
10. 権限拒否時に PermissionDeniedDialog が出る
11. ダークモード表示確認

- [ ] **Step 2: 見つかった不具合を対応タスクに追加**

---

## Task 22: ドキュメント更新 + 最終コミット

**Files:**
- Modify: `docs/tasks/IMPLEMENTATION_TASKS.md`
- Modify: `docs/tasks/lessons.md`（必要に応じて学び追加）

- [ ] **Step 1: IMPLEMENTATION_TASKS.md 更新**

1.3 の各チェックボックスを `[x]` に変更。進捗サマリも更新。

- [ ] **Step 2: lessons.md 追記（必要に応じて）**

タイムゾーン対応や health パッケージの癖など、実装中に発見した学びを記録。

- [ ] **Step 3: Commit**

```bash
git add docs/tasks/IMPLEMENTATION_TASKS.md docs/tasks/lessons.md
git commit -m "docs: 睡眠データ連携 (1.3) 完了を反映"
```

---

## 完了条件

全タスクが完了し、以下が満たされていること:

- [ ] `sleep_records` テーブルが Supabase に存在し RLS 5ポリシーが適用
- [ ] HealthKit/Health Connect から睡眠データが取得・同期される
- [ ] ホーム画面に SleepSummaryCard が3状態で正しく表示
- [ ] SleepRecordScreen が縦スクロール1画面で全セクション表示
- [ ] 朝ダイアログが時間条件で正しく表示/非表示
- [ ] 手動目覚め評価が保存・編集できる
- [ ] 設定画面で睡眠・朝ダイアログの各トグルが動作
- [ ] HealthKit権限拒否時に PermissionDeniedDialog
- [ ] タイムゾーン境界テスト・朝ダイアログ判定テストが全 PASS
- [ ] `flutter analyze` エラー0
- [ ] `ios-simulator-qa` での動作検証完了
- [ ] `IMPLEMENTATION_TASKS.md` 1.3 の全項目が `[x]`

---

## 注意事項

### CLAUDE.md 遵守
- **実装は必ずサブエージェント委託**。メインエージェントはコードを書かない
- Widget/Screen作成時はプレビュー関数必須
- `AppColors` / `AppColorsExtension` 使用（直接 Color リテラル禁止）
- 日本語対応

### タイムゾーン
- `recorded_date` は常に String（`"YYYY-MM-DD"`）で扱う
- `DateTime` の直接比較は禁止（lessons.md 参照）
- `jstDateKey()` ヘルパーを使う

### エラーハンドリング
- 体重同期失敗が睡眠同期を巻き添えにしない（独立try/catch）
- ネットワークエラー時はスナックバー通知のみ、次回同期でリカバリー

### 依存関係
- Task 1 → Task 2, 3 はこの順番で
- Task 4-6 は Task 2 完了後に並列可能
- Task 9-12 は Task 3 完了後に並列可能
- Task 13, 14 は Task 9 依存
- Task 17 は Task 9-12, 14 依存
- Task 19 は Task 6, 8, 13 依存
