# Lessons - 過去の失敗と学び

## 記録ルール

- バグを解決したら、ここにパターンと対策を追記する
- 設計上の判断ミスや整合性の注意点も記録する
- 同じ失敗を繰り返さないための知見をまとめる

---

## 2026-07-05: 共通化リファクタで移植元の防御コードを落とした

睡眠記録の記録タブ統合（feature/move-sleep-to-records-tab）で、寝起き記録ボトムシートを2つの既存実装（`sleep_record_screen.dart` の `_showRatingSheet` / `sleep_summary_card.dart` の `_RecordSheet`）から共通関数 `showWakeupRecordSheet` に統合した際の事例。

- 症状: `_RecordSheet` 側に**だけ**あった連打ガード（`_saving` フラグ）が共通版に入らず、評価ボタン連打で `upsertWakeupRating` が並走し得る状態になった（タスク単位レビューは通過し、**ブランチ全体の最終レビューで検出**）。
- 原因: 複数の移植元から「片方をベース」に共通化すると、もう片方にしかないガード・エラー処理が黙って消える。片方だけ読んで「同じUIだ」と判断するのは危険。
- 対策: 共通化では移植元**全部**を突き合わせ、ガード・エラー処理・edge case 対応の**和集合**を取ってから統合する。今回の修正では旧実装の欠陥（保存失敗時にガードが解除されず再試行不能）も同時に是正した（catch 先頭で `saving = false`）。
- メタ: タスク単位レビュー（brief準拠チェック）はこの種の「計画自体の抜け」を検出できない。**ブランチ全体レビューを別視点で必ず行う**運用が機能した。

---

## 2026-04-18: HealthKit 体重連携の4段構えバグ

feature/healthkit-weight-sync でユーザー画面に HealthKit 由来レコードが1件も反映されず、修正後も別の症状が順次露呈した事例。**ひとつの機能追加に対して、DB / プラットフォーム仕様 / TZ / データ仕様 の4種類のバグが重なっていた。**

### バグ①: Supabase CHECK 制約に新しい source 値を追加し忘れ

- 症状: `source='healthkit'` の INSERT が全件失敗。しかし try/catch で握り潰されており UI は無反応。
- 原因: `weight_records_source_check` が `ARRAY['manual', 'message']` のみを許可。マイグレーション未追加。
- 対策: 新しい `source` 値を追加する機能では、**必ず対応する CHECK 制約更新マイグレーションをセットで作る**。
- 注意: `meal_records` / `exercise_records` にも同じ形の `source_check` が存在する。HealthKit 連携を食事/運動に拡張する際は同じ罠。

### バグ②: iOS では `hasPermissions()` が READ 権限で常に nil を返す

- 症状: iOS 実機で sync が権限チェックで早期リターンし、INSERT が一切発火しない。
- 原因: `health` パッケージ v11 の iOS 実装は Apple のプライバシー方針に従い READ 権限状態を返さない（`return nil`）。`granted ?? false` だと常に false 扱いになる。
- 対策: iOS のみ `granted ?? true` で扱う。`requestAuthorization` 時点で権限ダイアログは出ているので妥当。
- 関連: `lib/features/health/data/health_repository.dart` の `hasPermission()` にコメント記載。

### バグ③: DateTime の UTC 変換漏れで 9 時間ズレ

- 症状: Apple Health の `4/17 23:59 JST` 記録がアプリで `4/18 08:59` として表示。
- 原因: `recordedAt.toIso8601String()` をローカル時刻の DateTime に対して直接呼ぶと、TZ サフィックスなし文字列（`"2026-04-17T23:59:59.000"`）になる。Supabase の `timestamptz` はそれを UTC として解釈 → 二重ズレ（= TZ offset 分未来にシフト）。
- 対策: **Supabase へ DateTime を渡す全箇所で `.toUtc().toIso8601String()` を使う**。`shared/utils/date_time_converter.dart` の `DateTimeConverter.toJson` は正しく実装されているので、それと挙動を揃える。
- 注意: Repository 層の直書き insert が要注意。`json_serializable` 経由なら `DateTimeConverter` が効くが、手書き Map ではコンバータが効かない。

### バグ④: Apple Health の end-of-day timestamp 取りこぼし

- 症状: 当日 (4/18) 分の HealthKit 記録がアプリに反映されない。翌日以降の古いデータは反映される。
- 原因: 多くの体組成計アプリは「その日の記録」に `23:59:59` の timestamp を付ける。sync の `endTime = DateTime.now()`（例: 12:00）が `23:59` 未来のレコードを除外してしまう。
- 対策: `getHealthDataFromTypes` の `endTime` は **`DateTime.now().add(Duration(days: 1))`** まで広げる。日付単位で dedup しているので二重インポートの心配はない。

### メタ教訓

- **silent try/catch は禁物**: `debugPrint` だけで握り潰すと UI が無反応になりデバッグ困難。早期リターン各箇所にログ、INSERT は個別 try/catch で継続しつつ件数集計、最終件数と状態遷移を出力する。
- **sync 成功時に provider invalidate を忘れない**: `ref.invalidate(weightRecordsProvider)` 等を呼ばないと、DB に入っても画面が古いキャッシュのまま。
- **DB × デバイス × プラットフォーム SDK × データ提供側仕様** の4層すべてにバグがあり得る。1つ直して終わりと思わず、段階的に検証する。
