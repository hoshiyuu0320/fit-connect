# HealthKit 体重データ連携 — 設計仕様書

**作成日**: 2026-04-05
**対象**: fit-connect-mobile (Flutter)
**フェーズ**: 1（ヘルスケア連携 — 体重のみ）

---

## 概要

Apple HealthKit / Google Health Connect から体重データを読み取り、既存の `weight_records` と統合する。

## スコープ

### 含む

- `health` パッケージ導入・権限設定
- HealthKit / Health Connect からの体重データ読み取り（単方向）
- アプリ起動時 + 手動同期ボタンによるデータ取り込み
- メッセージ記録優先の重複排除
- ヘルスケア連携専用設定画面
- 体重記録リストへのソースアイコン表示

### 含まない

- 睡眠データ連携（後続フェーズ）
- 双方向同期（アプリ → HealthKit への書き込み）
- バックグラウンド同期
- Supabase 側へのヘルスケア設定保存

---

## アーキテクチャ

### 新規ディレクトリ構造

```
lib/features/health/
├── data/
│   └── health_repository.dart        # health パッケージのラッパー
├── providers/
│   ├── health_provider.dart           # 権限・連携状態管理
│   └── health_sync_provider.dart      # 同期ロジック（取り込み・重複排除）
└── presentation/
    └── screens/
        └── health_settings_screen.dart # ヘルスケア連携設定画面
```

### 変更が必要な既存ファイル

| ファイル | 変更内容 |
|----------|----------|
| `weight_record_model.dart` | `source` に `'healthkit'` 値を追加 |
| `weight_record_screen.dart` | リスト内にソースアイコン（左側、控えめ）を表示 |
| `settings_screen.dart` | 「ヘルスケア連携」メニュー項目追加 |
| `app.dart` or `main.dart` | アプリ起動時の同期トリガー追加 |

---

## データフロー

```
アプリ起動
  → HealthSyncProvider.syncOnLaunch()
  → SharedPreferences で連携ON確認 → OFFなら終了
  → HealthRepository.hasPermission() → なければ終了
  → HealthRepository.getWeightData(since: lastSyncDate)
  → 各レコードについて:
     → 同日に source='message' のレコードがあるか確認
     → あればスキップ / なければ createWeightRecord(source: 'healthkit')
  → lastSyncDate 更新
```

---

## データモデル

### WeightRecord（既存・変更最小）

`source` フィールドの値に `'healthkit'` を追加。モデル構造の変更は不要。

```
source: 'message' | 'healthkit'
```

### 設定の永続化（SharedPreferences）

| キー | 型 | 説明 |
|------|----|------|
| `health_enabled` | bool | マスター連携ON/OFF |
| `health_weight_enabled` | bool | 体重データのON/OFF |
| `health_last_sync` | String (ISO8601) | 最終同期日時 |

Supabase DB には保存しない（端末ローカルの設定）。

---

## 同期ロジック詳細

### 重複排除ルール

- **メッセージ記録優先**: 同日に `source='message'` のレコードが存在する場合、HealthKit からの取り込みをスキップ
- **日単位で判定**: `recorded_at` の日付部分（YYYY-MM-DD）で比較
- **同日複数データ**: HealthKit に同日複数の体重記録がある場合、最新の1件を採用
- **初回同期**: lastSyncDate が未設定の場合、過去30日分を取得

### 同期タイミング

- アプリ起動時に自動実行
- 設定画面の「今すぐ同期」ボタン押下時

---

## UI 設計

### ヘルスケア連携設定画面（B1: リスト型 + 行内トグル）

**遷移**: 設定画面 → 「ヘルスケア連携」タップ → 専用画面

**レイアウト**:
1. マスタートグル — 「ヘルスケア連携」ON/OFF + サブテキスト「Apple Health からデータを取得」
2. データソースセクション
   - 体重: 行内トグルで個別ON/OFF、サブテキスト「読み取りのみ」
   - 睡眠: グレーアウト + 「Coming Soon」ラベル（将来用プレースホルダ）
3. 同期セクション
   - 最終同期日時の表示
   - 「今すぐ同期」ボタン（アウトラインスタイル）
4. 注意書き — 「手動入力の体重記録がある日はHealthKitからの取り込みをスキップします」

### 体重記録リストのソース表示（B: 控えめアイコン）

- リスト各行の左側に小さなアイコン（opacity: 0.5）
  - Lucide `message-circle` アイコン = メッセージ由来
  - Lucide `heart-pulse` アイコン = HealthKit 由来
  - ※ 既存プロジェクトで使用中の `lucide_icons` パッケージを使用（絵文字は使わない）

---

## 権限フロー

```
設定画面でマスタートグルON
  → HealthRepository.requestAuthorization([HealthDataType.WEIGHT])
  → OS権限ダイアログ表示
  → 許可: トグルON確定、初回同期実行
  → 拒否: トグルOFFに戻す、Snackbar「設定アプリから許可してください」
```

---

## エラーハンドリング

| ケース | 対応 |
|--------|------|
| 権限拒否 | トグルOFFに戻す + 設定アプリへの誘導メッセージ |
| HealthKit データ0件 | 正常扱い（何もしない） |
| Supabase書き込みエラー | リトライせず、次回起動時に再取得 |
| health パッケージ未対応端末 | 設定画面でヘルスケア連携セクション自体を非表示 |

### Android 対応

- Health Connect（Android 14+）対応
- Android 13以下: Health Connect アプリ未インストール時はストアへの誘導を表示

---

## テスト方針

### ユニットテスト

- **HealthRepository**: `health` パッケージのモック化、権限リクエスト・データ取得の正常/異常系
- **HealthSyncProvider**: 重複排除ロジック（同日にメッセージ記録ありならスキップ）、lastSyncDate更新

### 手動テスト（iOS シミュレータ）

- 設定画面 → ヘルスケア連携画面への遷移
- トグルON → 権限ダイアログ → 許可/拒否の動作
- 同期ボタン押下 → 体重記録リストへの反映
- ソースアイコンの表示確認

### テストしないもの

- HealthKit/Health Connect のネイティブAPI自体（パッケージの責任範囲）
- バックグラウンド同期（スコープ外）

---

## 技術選定

| 項目 | 選定 | 理由 |
|------|------|------|
| HealthKit ライブラリ | `health` パッケージ | iOS/Android 両対応、活発なメンテナンス、体重読み取りに十分 |
| 設定永続化 | SharedPreferences | 端末ローカル設定、既にプロジェクトで使用中 |
| 状態管理 | Riverpod（コード生成） | 既存パターン踏襲 |
