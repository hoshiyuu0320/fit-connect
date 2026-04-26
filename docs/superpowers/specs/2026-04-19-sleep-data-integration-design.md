# 睡眠データ連携 (Task 1.3) — 設計仕様書

**作成日**: 2026-04-19
**対象**: fit-connect-mobile (Flutter, iOS/Android)
**関連タスク**: `docs/tasks/IMPLEMENTATION_TASKS.md` フェーズ1 タスク1.3
**参考ブリーフ**: `fit-connect-mobile/docs/design/sleep-feature-wireframe-brief.md`
**参考hi-fi**: `fit-connect-mobile/docs/design/sleep-feature-hifi/fit-connect-mobile/project/`

---

## 1. 目的と範囲

### 目的
クライアント（一般利用者）が HealthKit / Health Connect 経由で睡眠データを自動取得し、アプリ内で「昨夜の睡眠」「週間トレンド」「履歴」を把握できるようにする。加えて、連携デバイスを持たないユーザーのために「目覚めの質」の3段階評価による簡易手動記録を提供する。

### スコープ（今回タスク = Mobile完結）
- HealthKit / Health Connect からの睡眠データ読み取り
- `sleep_records` テーブル新設（Supabase）
- 専用画面 `SleepRecordScreen`
- ホーム画面の睡眠サマリーカード
- 朝の目覚め記録ダイアログ（4:00-12:00に表示）
- 権限拒否時のガイドダイアログ
- ヘルスケア連携設定画面の拡張

### スコープ外（別タスク 1.5 で対応）
- Web（Trainer）側の型定義・UI
- トレーナー閲覧機能のWeb実装
  - ただし DBスキーマの RLS は最初からトレーナー閲覧を見越した設計にする

### 明示的に YAGNI
- 睡眠目標時間の設定機能
- 昼寝・複数セッション対応
- メッセージタグ（#睡眠）解析
- 月次・年次統計
- 設定画面の「データ再同期」「連携解除」セクション（既存の「今すぐ同期」ボタンとトグルで十分）

---

## 2. 要件決定事項

| 項目 | 決定 |
|---|---|
| データ粒度 | 総睡眠時間 + 就寝/起床時刻 + 4ステージ（深い/浅い/REM/覚醒）合計分 |
| 日付基準 | 起床日基準、メインセッションのみ（1日1レコード） |
| データソース | `healthkit`（HealthKit/Health Connect） / `manual`（手動入力） |
| 手動入力項目 | 目覚め評価（3段階）のみ。時間・ステージは入力しない |
| 目覚め評価 | すっきり / まあまあ / だるい（HealthKit連携有無に関わらず全員記録可） |
| 朝ダイアログ | 4:00-12:00 JST & 当日未記録 & 設定ON & 当日dismiss無し で起動時表示 |
| ホームカード | 時間+目覚め評価のみ。未記録時はCTA |
| 専用画面 | 縦スクロール1画面（サマリー → 週間 → 履歴） |
| ステージチャート | 案A 水平スタックバー |
| 初回同期範囲 | 30日遡り（体重連携と同じ） |
| トレーナー閲覧 | 今回スコープ外。RLSのみ先行対応 |

---

## 3. アーキテクチャ

### ディレクトリ構成

```
lib/features/
├── health/                                    # 既存（拡張）
│   ├── data/health_repository.dart            # ← getSleepData() 追加
│   ├── presentation/screens/health_settings_screen.dart  # ← 睡眠トグル有効化 + 朝ダイアログ設定追加
│   └── providers/
│       ├── health_provider.dart               # ← 設定キー追加（sleepEnabled, morningDialogEnabled）
│       └── health_sync_provider.dart          # ← syncSleep() 追加、syncManual()で睡眠も同期
│
└── sleep_records/                             # 新規
    ├── models/
    │   └── sleep_record_model.dart            # データモデル（@JsonSerializable）
    ├── providers/
    │   ├── sleep_records_provider.dart        # CRUD Provider（AsyncNotifier）
    │   └── morning_dialog_provider.dart       # 朝ダイアログ表示判定
    └── presentation/
        ├── screens/
        │   └── sleep_record_screen.dart       # 専用画面
        └── widgets/
            ├── sleep_summary_card.dart        # ホーム用サマリー
            ├── sleep_stage_bar.dart           # 水平スタックバー（案A）
            ├── sleep_week_chart.dart          # 週間折れ線（fl_chart）
            ├── sleep_history_list_item.dart   # 履歴行
            ├── morning_wakeup_dialog.dart     # 朝の記録ダイアログ
            ├── permission_denied_dialog.dart  # 権限拒否時
            └── wakeup_rating_selector.dart    # 3段階評価UI（ダイアログ+編集で再利用）

supabase/migrations/
└── YYYYMMDDHHMMSS_create_sleep_records.sql    # 新規テーブル
```

### レイヤ責任

| レイヤ | 責任 |
|---|---|
| `HealthRepository.getSleepData(from, to)` | HealthKit/Health Connect から睡眠データ取得、メインセッション判定、ステージ集計、起床日キーへのグルーピング |
| `HealthSync.syncSleep()` | 30日遡りで取得 → 既存レコードと重複排除 → Supabase UPSERT（`source='healthkit'`） |
| `SleepRecordsNotifier` | Supabase CRUD、目覚め評価の記録・更新。当日レコード取得のための `todaySleepRecord` provider、`recentSleepRecords` provider（履歴用） |
| `MorningDialogNotifier` | 4:00-12:00 JST & 当日未記録 & 設定ON & 今日dismiss無し の判定。`dismissToday()` メソッドで「今日は聞かない」対応 |

---

## 4. データモデル

### Supabase スキーマ

**マイグレーションファイル命名**: 既存パターン `YYYYMMDDHHMMSS_description.sql` に従う（例: `20260419210000_create_sleep_records.sql`）。

```sql
CREATE TABLE sleep_records (
  id                   UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  client_id            UUID NOT NULL REFERENCES clients(client_id) ON DELETE CASCADE,

  recorded_date        DATE NOT NULL,               -- 起床日キー（JST基準、クライアントから"YYYY-MM-DD"文字列で送信）

  -- 客観データ（HealthKit由来、手動のみの場合はNULL）
  bed_time             TIMESTAMPTZ,
  wake_time            TIMESTAMPTZ,
  total_sleep_minutes  INTEGER,
  deep_minutes         INTEGER,
  light_minutes        INTEGER,
  rem_minutes          INTEGER,
  awake_minutes        INTEGER,

  -- 主観データ
  wakeup_rating        SMALLINT CHECK (wakeup_rating IN (1, 2, 3)),
                                                    -- 1=だるい / 2=まあまあ / 3=すっきり

  -- メタ
  source               TEXT NOT NULL CHECK (source IN ('healthkit', 'manual')),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),

  UNIQUE (client_id, recorded_date),
  CONSTRAINT sleep_has_data CHECK (
    total_sleep_minutes IS NOT NULL OR wakeup_rating IS NOT NULL
  )
);

CREATE INDEX idx_sleep_records_client_date ON sleep_records(client_id, recorded_date DESC);

-- updated_at自動更新トリガ（既存のパターンに従う）
CREATE TRIGGER set_sleep_records_updated_at
  BEFORE UPDATE ON sleep_records
  FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

注: `note` カラムは YAGNI で削除。将来必要になった時点でマイグレーション追加。

### RLS ポリシー

**実装方針**: 既存の `weight_records` の RLS ポリシーと**同一の構造**を踏襲する。
既存スキーマでは `trainers.id = auth.users.id`（直接FK、`auth_user_id` カラムは存在しない）、clients は `email` / 関連テーブル経由で本人判定する。

Supabaseサブエージェント実装時の具体指示:
1. `supabase/migrations/` 配下から既存 `weight_records` のRLS（INSERT/SELECT/UPDATE/DELETE 4ポリシー）を読み、table名のみ `sleep_records` に置き換える
2. **トレーナー閲覧（SELECT）を最初から含める**（1.5で有効になる前提、今時点では書き込み系ポリシーは本人のみで、トレーナー経路がSELECTで活きない状態でも問題なし）
3. updated_at自動更新トリガも既存パターン踏襲

### Dart モデル (`sleep_record_model.dart`)

```dart
@JsonSerializable()
class SleepRecord {
  final String id;
  final String clientId;
  final String recordedDate;          // "YYYY-MM-DD" 文字列（タイムゾーン安全）
  final DateTime? bedTime;            // UTC ISO8601（表示時toLocal）
  final DateTime? wakeTime;           // UTC ISO8601（表示時toLocal）
  final int? totalSleepMinutes;
  final int? deepMinutes;
  final int? lightMinutes;
  final int? remMinutes;
  final int? awakeMinutes;
  final WakeupRating? wakeupRating;   // enum: groggy(1), okay(2), refreshed(3)
  final SleepSource source;           // enum: healthkit, manual
  final DateTime createdAt;
  final DateTime updatedAt;

  // ヘルパー:
  bool get hasObjectiveData => totalSleepMinutes != null;
  Duration? get totalDuration => totalSleepMinutes != null ? Duration(minutes: totalSleepMinutes!) : null;
  Map<SleepStage, int>? get stageBreakdown;  // null if no objective data
}

enum WakeupRating { groggy, okay, refreshed }       // DB: 1, 2, 3
enum SleepSource { healthkit, manual }
enum SleepStage { deep, light, rem, awake }
```

### タイムゾーン方針（必読: `docs/tasks/lessons.md` の日付比較問題の再発防止）

1. **`recorded_date` は `String` で扱う**（`DateTime` 型は使わない）。フォーマットは `"YYYY-MM-DD"` 固定。日付比較は文字列比較（`<`, `==`, `>=`）で行う
2. **JST起床日への変換式**:
   ```dart
   String jstDateKey(DateTime utcWakeTime) {
     final jst = utcWakeTime.toUtc().add(const Duration(hours: 9));
     return '${jst.year.toString().padLeft(4, '0')}-'
            '${jst.month.toString().padLeft(2, '0')}-'
            '${jst.day.toString().padLeft(2, '0')}';
   }
   ```
3. **「今日」の定義**: `jstDateKey(DateTime.now())`。JST 0:00 切替（深夜 0:00-3:59 のアプリ起動は「前日」扱い、朝ダイアログは表示しない条件に合致）
4. **HealthKit取得時**: `bed_time`, `wake_time` は UTC で保存し、表示時のみ `toLocal()`。recorded_date は `jstDateKey(wakeTime)` で決定
5. **Supabaseクエリ**: 日付範囲フィルタは文字列比較で安全。例: `.gte('recorded_date', '2026-03-20').lte('recorded_date', '2026-04-19')`

### source フィールドの意味論（厳密定義）

`source` はレコードの**客観データの出所**を表す（主観評価 `wakeup_rating` の出所ではない）:

| source値 | 条件 | 意味 |
|---|---|---|
| `'healthkit'` | `total_sleep_minutes IS NOT NULL` | 客観データが HealthKit/Health Connect から取得された |
| `'manual'` | `total_sleep_minutes IS NULL AND wakeup_rating IS NOT NULL` | 客観データ無し、手動の目覚め評価のみ |

`wakeup_rating` は source に関係なく独立に存在可能（HealthKitレコードにも手動で付与できる）。

### UPSERT 戦略（体重連携との相違点）

**体重連携（1.2）は INSERT のみ**（`health_sync_provider.dart:30-60` の `filterHealthData()` で重複排除後 INSERT）。**睡眠は UPSERT が必要**。理由: 手動で wakeup_rating 付与 → 後日HealthKit同期で客観データが追加される、というフローが存在するため。

```
syncSleep() フロー:
  1. lastSyncAt（SharedPreferences）から30日前までの範囲を決定
  2. HealthRepository.getSleepData(from, to) で取得（wake_timeをJST起床日にマップ）
  3. 各取得データについて Supabase .upsert():
       .upsert(
         {client_id, recorded_date, bed_time, wake_time, total_sleep_minutes, ...},
         onConflict: 'client_id,recorded_date',
       )
     - 既存レコードなし → INSERT（source='healthkit'、wakeup_rating=null）
     - 既存 source='manual' → 客観フィールド追加 + source='healthkit'に昇格、wakeup_rating保持
     - 既存 source='healthkit' → 客観フィールドのみ更新、wakeup_rating保持
     **wakeup_rating は UPSERT ペイロードに含めない**（保持のため）
  4. lastSyncAt 更新
```

`upsertWakeupRating(date, rating)` フロー:
```
  1. .upsert(
       {client_id, recorded_date, wakeup_rating},
       onConflict: 'client_id,recorded_date',
       ignoreDuplicates: false,
     )
     - 既存無し → INSERT（source='manual'、他客観フィールドはNULL）
     - 既存有り → wakeup_rating のみ UPDATE、source と客観フィールドは保持
  2. INSERT時にsource明示、UPDATE時はsource未指定で保持
```

**保証**:
- 手動入力の `wakeup_rating` は HealthKit 同期で上書きされない
- HealthKit で記録済みの日に手動評価を追加可能（source='healthkit'のまま、rating追加）
- 客観データが後から来た日は source='manual' → 'healthkit' に昇格（rating保持）

---

## 5. UI設計（hi-fi準拠）

デザイン詳細は `sleep-feature-hifi/` 配下の JSX を正とする。以下は Flutter 実装時の対応表。

### 5-A. SleepSummaryCard（ホーム用 3状態）

| 状態 | トリガ | 表示 |
|---|---|---|
| `healthkit` | 当日レコードあり & `totalSleepMinutes != null` | 時間（大）+ 就寝→起床時刻（小）+ 目覚め評価（右下） + heartPulseアイコン（右上） |
| `manual` | 当日レコードあり & `totalSleepMinutes == null` & `wakeupRating != null` | 目覚め評価のみ大きく + 「タップして詳細を記録」 + penLineアイコン（右上） |
| `empty` | 当日レコード無し | 「目覚めを記録する」CTAボタン（primary50背景） |

- 高さ: 動的（約96-120px）
- タップ → `SleepRecordScreen` 遷移
- `empty` 時のCTAタップ → `WakeupRatingSelector` ボトムシート

### 5-B. SleepRecordScreen（専用画面 縦スクロール）

**AppBar**:
- Title: `睡眠記録`
- 右上アクション: `RefreshIcon`（同期ON時のみ）→ 手動同期実行

**セクション順序**:

1. **サマリーカード**（状態別に差し替え）
   - HealthKit連携データあり: 時間大 → 就寝/起床のグリッド（slate100背景） → ステージ水平バー + 凡例（4項目グリッド） → 目覚め行 + 編集ボタン
   - 手動のみ: 目覚め評価（大）→ info行「詳細データを取得するには...」 → 目覚め行 + 編集ボタン
   - 空（今日）: `今日の記録はまだありません` + `目覚めを記録する` ボタン

2. **週間トレンド**（`直近7日間` セクション）
   - `WeekChart`: 折れ線（area fill付き）、null日はdashedライン + 中空ノード、下部に日付+目覚めアイコン

3. **履歴**（`履歴` セクション、`{件数}件` 右端）
   - リスト行（高さ56px）: 日付+曜日 / 時間 or `--` / 目覚めアイコン or 点線プレースホルダ / ソースアイコン / chevron
   - 30件ページング（無限スクロール）

**追加状態**:
- Loading: Shimmer アニメーション
- Empty（全履歴空）: 中央大きめの月アイコン + メッセージ + CTA
- Permission denied: `PermissionDeniedDialog` を上に重ねる

### 5-C. MorningWakeupDialog

**「今日」の定義**: JST 0:00 切替の `jstDateKey(DateTime.now())`。深夜 0:00-3:59 の起動は条件2で除外される（4時前）。

**表示条件（AND）**:
  1. トリガ: アプリ初回起動 OR `AppLifecycleState.resumed`（フォアグラウンド復帰時）
  2. 現在時刻（JST）が 4:00-12:00
  3. 当日の `sleep_records.wakeup_rating` が NULL（HealthKit同期で客観データのみ入っている場合も「未評価」扱いで表示対象）
  4. 設定 `morningDialogEnabled == true`
  5. SharedPreferences `morningDialogDismissedDate != jstDateKey(DateTime.now())`
  6. **既にダイアログ表示中でないこと**（多重表示防止ガード: グローバルフラグ or ナビゲーションスタック検査）

**レースコンディション対策**: アプリ起動時は HealthKit同期（`syncSleep()`）を先に完走させ、完了後に表示判定する。同期中はダイアログ判定を保留。

- 構成: sun icon + 「おはようございます」 / 「今朝の目覚めは？」 / 3オプション（すっきり/まあまあ/だるい）/ 「あとで」「今日は聞かない」
- 背景: `BackdropFilter(ImageFilter.blur(sigmaX: 6, sigmaY: 6))` + 半透明オーバーレイ（`Colors.black.withOpacity(0.42)`）
- 動作:
  - 評価選択 → `SleepRecordsNotifier.upsertWakeupRating(today, rating)` → 閉じる → スナックバー「記録しました」
  - 「あとで」 → 閉じる（次回 resumed で再判定）
  - 「今日は聞かない」 → `morningDialogDismissedDate = jstDateKey(today)` 保存 → 閉じる

### 5-D. PermissionDeniedDialog

- HealthKit / Health Connect 権限を拒否された時に表示
- 構成: lock icon（赤系） + タイトル + 説明 + 「あとで」「設定を開く」
- タイトル: 「ヘルスケアへのアクセスが許可されていません」
- 説明文（プラットフォーム別に分岐）:
  - iOS: 「設定アプリの『ヘルスケア』→『データアクセスとデバイス』から FIT-CONNECT に睡眠データの読み取りを許可してください。」
  - Android: 「Health Connect アプリから FIT-CONNECT に睡眠データの読み取りを許可してください。」
- 「設定を開く」→ `app_settings` パッケージで設定アプリへ遷移（Android は Health Connect 設定画面をintentで優先、不可ならアプリ設定）

### 5-E. HealthSettingsScreen 拡張

既存 `health_settings_screen.dart` を以下の構成へ:

```
[インフォカード: 「有効にすると、お使いの端末のヘルスケアデータ（iOS: ヘルスケア / Android: Health Connect）から体重と睡眠のデータを自動で取得します。データは端末内で処理されます。」]
  - 実装方針: 端末依存しない汎用文言で固定（プラットフォーム分岐させない。ユーザーが両OS同時利用する想定で統一表現が自然）
[セクション: データ連携]
  - 体重データ（既存、アクセントbg: slate100、icon: ScaleIcon）
  - 区切り線（marginLeft 60px）
  - 睡眠データ（新規、アクセントbg: indigo50、icon: MoonIcon、NEWバッジ）
[セクション: 通知]
  - 朝の目覚めダイアログ（新規、アクセントbg: warning薄色、icon: SunIcon、NEWバッジ）
```

「今すぐ同期」ボタンは既存通り、画面下部に残す。

### 5-F. デザイントークン対応

既存の `AppColorsExtension`（ThemeExtension、`lib/core/theme/app_colors.dart:80-201`）に睡眠ステージ色を追加し、ライト/ダーク切替を既存パターンと統一する。

```dart
// lib/core/theme/app_colors.dart AppColorsExtension に追加するフィールド:
final Color sleepStageDeep;
final Color sleepStageLight;
final Color sleepStageRem;
final Color sleepStageAwake;

// light preset:
sleepStageDeep:  Color(0xFF4338CA),  // indigo-700
sleepStageLight: Color(0xFF818CF8),  // indigo-400
sleepStageRem:   Color(0xFF60A5FA),  // primary-400
sleepStageAwake: Color(0xFFE2E8F0),  // slate-200

// dark preset:
sleepStageDeep:  Color(0xFF6366F1),
sleepStageLight: Color(0xFF818CF8),
sleepStageRem:   Color(0xFF60A5FA),
sleepStageAwake: Color(0xFF475569),  // slate-700
```

**使用例**: `AppColorsExtension.of(context).sleepStageDeep`（既存の `colors.surface` 等のパターンに揃える）

---

## 6. データフローと統合

### 6-A. アプリ起動時フロー

```
アプリ起動
  ↓
AuthNotifier でユーザー確認
  ↓
[並列]
  ├─ healthSettings 読込（sleepEnabled, morningDialogEnabled）
  ├─ SleepRecordsNotifier 初期化（今日のレコード取得）
  └─ MorningDialogNotifier.shouldShow 判定
  ↓
shouldShow == true → MorningWakeupDialog 表示
  ↓
sleepEnabled == true → HealthSync.syncSleep() をバックグラウンド実行
```

### 6-B. 手動記録フロー

```
[ホーム empty状態カード] or [sleep_record_screen empty]
  → CTA タップ
  → WakeupRatingSelector（ボトムシート）表示
  → 評価選択
  → SleepRecordsNotifier.upsertWakeupRating(today, rating)
    → 既存レコード無 → INSERT（source='manual'）
    → 既存レコード有 → UPDATE wakeup_rating（source保持）
  → スナックバー「記録しました」
```

### 6-C. 編集フロー

```
SleepRecordScreen サマリーカード「編集」ボタン
  → WakeupRatingSelector（ボトムシート、現在値強調表示）
  → 選択 → upsertWakeupRating 更新
  → 閉じる
```

---

## 7. エッジケース対応

| ケース | 対応 |
|---|---|
| HealthKit権限拒否 | `PermissionDeniedDialog` 表示、「設定を開く」導線 |
| HealthKit同期失敗 | スナックバーでエラー通知、再試行ボタン |
| 当日ダイアログで「あとで」 | 閉じるだけ。次回起動時に再表示判定 |
| 当日ダイアログで「今日は聞かない」 | `morningDialogDismissedDate = today` 保存、当日再表示しない |
| HealthKit連携前に手動記録した日にHealthKit同期が走る | UPDATE でオブジェクトデータ追加、`wakeup_rating` 保持、source='healthkit'に変更 |
| 手動入力後のHealthKit同期 | 上記と同じ挙動（rating保持） |
| ネットワーク不通 | Supabaseエラー時はトースト。次回同期でリカバリー |
| データソース混在の履歴行 | `totalSleepMinutes == null` の行は時間列に `--`、ソースアイコンに `penLineIcon` |
| タイムゾーン境界 | `recorded_date` はJSTの起床日。HealthKitから取得した時刻は `toLocal()` してから日付計算 |
| 日付またぎの同期 | `recorded_date` 基準で UPSERT するため、UTCズレで別レコードにならない |

---

## 8. テスト方針

- **Unit**:
  - `SleepRecord` model の JSON シリアライズ
  - `HealthRepository.getSleepData()` の集計ロジック（モック health data）
  - `jstDateKey()` のタイムゾーン境界テスト（23:55就寝→翌7:00起床のJST変換、UTC→JST+9 の境界値）
  - `MorningDialogNotifier.shouldShow` の判定ロジック（時刻・設定・dismiss状態の各組み合わせ、3:59/4:00/11:59/12:00 境界）
- **Integration**:
  - Supabase UPSERT の挙動確認（手動→HealthKit、HealthKit→手動評価追加）
- **Widget**:
  - `SleepSummaryCard` の3状態プレビュー
  - `SleepRecordScreen` の静的プレビュー（@Preview関数必須）
  - `MorningWakeupDialog` プレビュー
  - `SleepStageBar` プレビュー
- **Manual QA**（`ios-simulator-qa` スキル実行）:
  - 実機HealthKitから同期できること
  - 朝ダイアログが時刻条件で正しく出ること
  - 手動記録がSupabaseに保存されること

---

## 9. 既存コードへの影響

| 変更対象 | 内容 |
|---|---|
| `lib/features/health/data/health_repository.dart` | `getSleepData()` メソッド追加（HealthDataType.SLEEP_*を取得、メインセッション判定） |
| `lib/features/health/providers/health_provider.dart` | `HealthSettings` に `sleepEnabled`, `morningDialogEnabled` フィールド追加 |
| `lib/features/health/providers/health_sync_provider.dart` | `syncSleep()` 追加、`syncManual()` で体重+睡眠両方を同期 |
| `lib/features/health/presentation/screens/health_settings_screen.dart` | 「Coming Soon」プレースホルダを実装に差し替え、セクション構成変更 |
| `ios/Runner/Info.plist` | `NSHealthShareUsageDescription` のメッセージ更新（睡眠も含む旨） |
| `android/app/src/main/AndroidManifest.xml` | Health Connect の睡眠パーミッション追加（必要に応じて） |
| `lib/core/theme/app_colors.dart` | `AppColorsExtension` に `sleepStageDeep / sleepStageLight / sleepStageRem / sleepStageAwake` の4フィールド追加（light/dark両preset） |
| ホーム画面（`lib/features/home/presentation/screens/home_screen.dart`） | `SleepSummaryCard` を既存の体重カードの下に配置 |

既存機能の **破壊的変更なし**。睡眠機能OFFなら何も見えない。

---

## 10. 実装サブタスク分解（概要）

writing-plans で詳細化するが、大枠は以下:

1. Supabase マイグレーション（sleep_records テーブル + RLS）
2. `SleepRecord` モデル + JsonSerializable コード生成
3. `HealthRepository.getSleepData()` 実装
4. `SleepRecordsNotifier` / `todaySleepRecord` / `recentSleepRecords` provider
5. `MorningDialogNotifier` 実装
6. `SleepSummaryCard` Widget（3状態）+ プレビュー
7. `SleepStageBar` Widget + プレビュー
8. `SleepWeekChart` Widget（fl_chart使用）+ プレビュー
9. `SleepHistoryListItem` Widget + プレビュー
10. `WakeupRatingSelector` Widget + プレビュー
11. `MorningWakeupDialog` Widget + プレビュー
12. `PermissionDeniedDialog` Widget + プレビュー
13. `SleepRecordScreen` 構築 + プレビュー
14. `HealthSettingsScreen` 拡張
15. `health_sync_provider.syncSleep()` 追加
16. アプリ起動時 MorningDialog 表示ロジック（`app.dart` or ルーター層）
17. ホーム画面への SleepSummaryCard 配置
18. iOS Info.plist / Android Manifest 更新
19. `ios-simulator-qa` による動作検証

---

## 11. リスクと緩和策

| リスク | 緩和策 |
|---|---|
| Health Connect の睡眠データが Android デバイスによって取得できない | Android は MVP として「対応してれば動く」レベル、詳細は1.4で。iOS 優先 |
| HealthKit のステージ区分がデバイスで異なる（Apple Watch vs Third-party） | Light/Deep/REM/Awake に正規化、マッピング不可な値は awake に寄せる |
| UPSERT競合（同時起動で同期と手動入力が衝突） | Supabase `.upsert()` は単体でアトミック。アプリ側は `onConflict: 'client_id,recorded_date'` を必ず指定。wakeup_rating 更新と客観データ更新は別クエリで発行し、各クエリの影響フィールドを限定することで衝突時も破壊的上書きを避ける |
| タイムゾーン問題（lessons.md 参照） | `recorded_date` は `String` (YYYY-MM-DD) で扱い、JST固定で日付計算。`jstDateKey()` ヘルパー関数を共有 |
| Riverpod コード生成忘れ | 実装後に `dart run build_runner build --delete-conflicting-outputs` の実行を ios-simulator-qa の前工程に組み込み |
| 体重同期失敗が睡眠同期を巻き添えにする | `syncManual()` 内で体重同期と睡眠同期を独立 try-catch し、どちらか失敗しても他方は実行。結果は個別にユーザーに通知 |

---

## 12. 参考

- ブリーフ: `fit-connect-mobile/docs/design/sleep-feature-wireframe-brief.md`
- hi-fi: `fit-connect-mobile/docs/design/sleep-feature-hifi/`
- 参考実装（体重連携）: `lib/features/weight_records/`, `lib/features/health/`
- 既存マイグレーション: `supabase/migrations/20260417140638_allow_healthkit_source_for_weight_records.sql`
- Lessons: `docs/tasks/lessons.md`（特にタイムゾーン問題）
