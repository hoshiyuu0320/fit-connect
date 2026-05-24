# Lessons - 過去の失敗と学び

## 記録ルール

- バグを解決したら、ここにパターンと対策を追記する
- 設計上の判断ミスや整合性の注意点も記録する
- 同じ失敗を繰り返さないための知見をまとめる

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

---

## 2026-05-24: Flutter 3.44 アップグレード後の Xcode ビルド連鎖崩壊

`flutter upgrade` 後に Xcode 直接ビルドが複数の症状で壊れた事例。**Flutter SDK のメジャー変更が、SDK / パッケージ / iOS ビルド設定の3層に同時にダメージを与えた。**

### 症状①: `lucide_icons 0.257.0` がビルド不可

- エラー: `The class 'IconData' can't be extended outside of its library because it's a final class.`
- 原因: Flutter 3.27+ で `IconData` が `final class` 化。`lucide_icons` パッケージはメンテ停止しており追従していない。
- 対策: メンテされているフォーク `lucide_icons_flutter` に乗り換え。API（`LucideIcons.xxx`）は完全互換、import パスのみ全 .dart で一括置換。
- 関連: [pubspec.yaml:12](../../pubspec.yaml#L12)

### 症状②: Swift Package Manager 自動有効化と Xcode プロジェクト未移行

- エラー: `Module 'app_links' not found`（`GeneratedPluginRegistrant.m` から）
- 原因: Flutter 3.44 で SPM が iOS デフォルト有効化。`flutter run` 経由なら project.pbxproj に SPM 参照が自動追加されるが、**Xcode から直接ビルドすると移行が走らない**。結果、Flutter は SPM プラグインを Pod として登録せず、Xcode は SPM 参照も持たない → モジュール解決不能。
- 対策: `flutter config --no-enable-swift-package-manager` で SPM を無効化し、全 plugin を Pod 経由に戻す。
- 確認方法: `.flutter-plugins-dependencies` 内 `swift_package_manager_enabled` フィールド、および `pod install` 出力の plugin 数（無効化後は 17 deps / 32 pods）。

### 症状③: `Pods/Manifest.lock` が無いまま `pod install completed` 表示

- エラー: `The sandbox is not in sync with the Podfile.lock. Manifest.lock: No such file or directory`
- 原因: 不明（pod install が「complete」表示でも Manifest.lock を書き出さないケースあり）。前回 podfile が大幅変更されており、不完全状態の Pods/ が残っていた可能性。
- 対策: `rm -rf Pods Podfile.lock && pod install` でクリーン再生成。

### メタ教訓

- **Flutter の SDK upgrade は地雷**: 安易に `flutter upgrade` を実行すると複数パッケージ・iOSビルド設定が連鎖的に壊れる。アップグレード前に必ず CHANGELOG を確認し、対応コストを見積もる。
- **メンテ停止パッケージの早期検知**: pub.dev で最終更新が1年以上経っているパッケージは要注意（特に Flutter SDK の破壊的変更に追従していない）。`flutter pub outdated` で定期的に確認する。
- **Xcode 直接ビルド vs CLI ビルドで挙動が異なる**: `flutter run` / `flutter build ios` は内部で各種設定マイグレーションを走らせる。Xcode 直接ビルドはそれを skip する → 普段 CLI で動いても Xcode で壊れることがある。リリースビルドは必ず Xcode で事前検証。
- **Dart 3.12 で三項演算子の型推論が厳格化**: `i == 5 ? 0 : 50 + i` のような両辺が int の式は全体が int に推論される。`double` が要求される箇所では `.toDouble()` を明示する必要がある。プレビュー関数のダミーデータも本番ビルドに含まれる点に注意。
