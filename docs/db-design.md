# FIT-CONNECT データベース設計書

## 1. システム概要

FIT-CONNECTは、フィットネストレーナーとクライアント間のコミュニケーションを管理するシステムです。トレーナーは複数のクライアントを担当し、メッセージのやり取りを行うことができます。LINE連携機能も提供しています。

---

## 2. ER図（テキスト表現）

```
profiles (トレーナー)
    ↓ 1:N
clients (クライアント)
    ↓ 1:N
messages (メッセージ)

line_users ──→ profiles (外部キー)
```

---

## 3. テーブル定義

### 3.1 profiles（プロフィール/トレーナーマスタ）

**概要:** トレーナーの基本情報を管理するテーブル

| カラム名 | データ型 | NULL     | キー | デフォルト値 | 説明                             |
| -------- | -------- | -------- | ---- | ------------ | -------------------------------- |
| id       | uuid     | NOT NULL | PK   | -            | トレーナーID（auth.usersと連携） |
| name     | text     | NULL     | -    | -            | トレーナー名                     |

**制約:**
- PRIMARY KEY: id
- FOREIGN KEY: id → auth.users.id
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id

**備考:**
- auth.usersテーブルと1:1の関係
- トレーナーのプロフィール情報を拡張するためのテーブル

---

### 3.2 clients（クライアントマスタ）

**概要:** トレーナーが担当するクライアントの情報を管理するテーブル

| カラム名           | データ型    | NULL     | キー   | デフォルト値      | 説明                                                         |
| ------------------ | ----------- | -------- | ------ | ----------------- | ------------------------------------------------------------ |
| client_id          | uuid        | NOT NULL | PK     | gen_random_uuid() | クライアントID                                               |
| trainer_id         | uuid        | NOT NULL | FK     | gen_random_uuid() | 担当トレーナーID                                             |
| name               | text        | NOT NULL | -      | -                 | クライアント名                                               |
| gender             | text        | NOT NULL | -      | -                 | 性別（male/female/other）                                    |
| age                | integer     | NOT NULL | -      | -                 | 年齢                                                         |
| occupation         | text        | NULL     | -      | -                 | 職業                                                         |
| height             | numeric     | NOT NULL | -      | -                 | 身長（cm）                                                   |
| target_weight      | numeric     | NOT NULL | -      | -                 | 目標体重（kg）                                               |
| purpose            | text        | NOT NULL | -      | -                 | 目的（diet/contest/body_make/health_improvement/mental_improvement/performance_improvement） |
| goal_description   | text        | NULL     | -      | -                 | 目標の詳細説明（トレーナーが記入）                           |
| profile_image_url  | text        | NULL     | -      | -                 | プロフィール画像URL（Supabase Storage）                      |
| line_user_id       | text        | NULL     | UNIQUE | -                 | LINEログインしたユーザーのID                                 |
| created_at         | timestamptz | NOT NULL | -      | now()             | 登録日時                                                     |

**制約:**
- PRIMARY KEY: client_id
- FOREIGN KEY: trainer_id → profiles.id
- UNIQUE: line_user_id
- CHECK: gender IN ('male', 'female', 'other')
- CHECK: purpose IN ('diet', 'contest', 'body_make', 'health_improvement', 'mental_improvement', 'performance_improvement')
- CHECK: age > 0 AND age < 150
- CHECK: height > 0 AND height < 300
- CHECK: target_weight > 0 AND target_weight < 500
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on client_id
- UNIQUE index on line_user_id
- INDEX on trainer_id（検索高速化）
- INDEX on gender（フィルタリング高速化）
- INDEX on purpose（フィルタリング高速化）

**リレーション:**
- trainer_id → profiles.id (1:N)

**備考:**
- 1人のトレーナーは複数のクライアントを担当可能
- LINE連携は任意（line_user_idがNULLの場合は未連携）
- 基本情報はクライアント側アプリで登録される想定
- 目標体重・目標説明はトレーナーが設定

---

### 3.3 messages（メッセージ）

**概要:** トレーナーとクライアント間のメッセージを管理するテーブル

| カラム名      | データ型    | NULL     | キー | デフォルト値      | 説明                                  |
| ------------- | ----------- | -------- | ---- | ----------------- | ------------------------------------- |
| id            | uuid        | NOT NULL | PK   | gen_random_uuid() | メッセージID                          |
| sender_id     | uuid        | NOT NULL | -    | gen_random_uuid() | 送信者ID                              |
| receiver_id   | uuid        | NOT NULL | -    | gen_random_uuid() | 受信者ID                              |
| message       | text        | NULL     | -    | -                 | メッセージ本文                        |
| sender_type   | text        | NOT NULL | -    | ''::text          | 送信者タイプ（'trainer' or 'client'） |
| receiver_type | text        | NOT NULL | -    | ''::text          | 受信者タイプ（'trainer' or 'client'） |
| timestamp     | timestamptz | NOT NULL | -    | now()             | 送信日時                              |

**制約:**
- PRIMARY KEY: id
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id
- 推奨: sender_id, receiver_id, timestampにインデックス作成

**備考:**
- sender_id/receiver_idは、sender_type/receiver_typeに応じてprofiles.idまたはclients.client_idを参照
- メッセージの送受信方向を識別するため、sender_type/receiver_typeを使用
- timestampで時系列にソート可能

---

### 3.4 weight_records（体重記録）

**概要:** クライアントの体重記録を管理するテーブル

| カラム名    | データ型    | NULL     | キー | デフォルト値      | 説明               |
| ----------- | ----------- | -------- | ---- | ----------------- | ------------------ |
| id          | uuid        | NOT NULL | PK   | gen_random_uuid() | 記録ID             |
| client_id   | uuid        | NOT NULL | FK   | -                 | クライアントID     |
| weight      | numeric     | NOT NULL | -    | -                 | 体重（kg）         |
| recorded_at | timestamptz | NOT NULL | -    | now()             | 記録日時           |

**制約:**
- PRIMARY KEY: id
- FOREIGN KEY: client_id → clients.client_id (ON DELETE CASCADE)
- CHECK: weight > 0 AND weight < 500
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id
- INDEX on client_id, recorded_at DESC（時系列検索高速化）

**リレーション:**
- client_id → clients.client_id (N:1)

**備考:**
- クライアントが任意のタイミングで記録
- グラフ表示用のデータソース
- 現在の体重は最新のrecorded_atのレコードから取得

---

### 3.5 meal_records（食事記録）

**概要:** クライアントの食事記録を管理するテーブル

| カラム名    | データ型    | NULL     | キー | デフォルト値      | 説明                                              |
| ----------- | ----------- | -------- | ---- | ----------------- | ------------------------------------------------- |
| id          | uuid        | NOT NULL | PK   | gen_random_uuid() | 記録ID                                            |
| client_id   | uuid        | NOT NULL | FK   | -                 | クライアントID                                    |
| meal_type   | text        | NOT NULL | -    | -                 | 食事区分（breakfast/lunch/dinner/snack）          |
| description | text        | NULL     | -    | -                 | メモ・説明                                        |
| calories    | numeric     | NULL     | -    | -                 | カロリー（kcal）※自動算出または手動入力          |
| images      | text[]      | NULL     | -    | -                 | 画像URL配列（Supabase Storage、最大10枚）        |
| recorded_at | timestamptz | NOT NULL | -    | now()             | 記録日時                                          |

**制約:**
- PRIMARY KEY: id
- FOREIGN KEY: client_id → clients.client_id (ON DELETE CASCADE)
- CHECK: meal_type IN ('breakfast', 'lunch', 'dinner', 'snack')
- CHECK: calories IS NULL OR calories >= 0
- CHECK: images IS NULL OR array_length(images, 1) <= 10
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id
- INDEX on client_id, recorded_at DESC（時系列検索高速化）
- INDEX on client_id, meal_type（カテゴリ別検索高速化）

**リレーション:**
- client_id → clients.client_id (N:1)

**備考:**
- 1日に複数回記録可能
- 画像は最大10枚まで
- カロリーは将来的に画像認識APIで自動算出する想定

---

### 3.6 exercise_records（運動記録）

**概要:** クライアントの運動記録を管理するテーブル

| カラム名      | データ型    | NULL     | キー | デフォルト値      | 説明                                                                          |
| ------------- | ----------- | -------- | ---- | ----------------- | ----------------------------------------------------------------------------- |
| id            | uuid        | NOT NULL | PK   | gen_random_uuid() | 記録ID                                                                        |
| client_id     | uuid        | NOT NULL | FK   | -                 | クライアントID                                                                |
| exercise_type | text        | NOT NULL | -    | -                 | 運動種目（walking/running/strength_training/cycling/swimming/yoga/pilates/other） |
| duration      | integer     | NULL     | -    | -                 | 運動時間（分）                                                                |
| distance      | numeric     | NULL     | -    | -                 | 距離（km）                                                                    |
| calories      | numeric     | NULL     | -    | -                 | 消費カロリー（kcal）                                                          |
| memo          | text        | NULL     | -    | -                 | メモ                                                                          |
| recorded_at   | timestamptz | NOT NULL | -    | now()             | 記録日時                                                                      |

**制約:**
- PRIMARY KEY: id
- FOREIGN KEY: client_id → clients.client_id (ON DELETE CASCADE)
- CHECK: exercise_type IN ('walking', 'running', 'strength_training', 'cycling', 'swimming', 'yoga', 'pilates', 'other')
- CHECK: duration IS NULL OR duration > 0
- CHECK: distance IS NULL OR distance > 0
- CHECK: calories IS NULL OR calories >= 0
- CHECK: duration IS NOT NULL OR distance IS NOT NULL（時間または距離の少なくとも一方は必須）
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id
- INDEX on client_id, recorded_at DESC（時系列検索高速化）
- INDEX on client_id, exercise_type（種目別検索高速化）

**リレーション:**
- client_id → clients.client_id (N:1)

**備考:**
- duration（時間）またはdistance（距離）のいずれか、または両方を記録
- カロリーは任意入力（デバイスから取得できる場合）

---

### 3.7 tickets（チケット）

**概要:** クライアントが保有するセッション回数券を管理するテーブル

| カラム名            | データ型    | NULL     | キー | デフォルト値      | 説明               |
| ------------------- | ----------- | -------- | ---- | ----------------- | ------------------ |
| id                  | uuid        | NOT NULL | PK   | gen_random_uuid() | チケットID         |
| client_id           | uuid        | NOT NULL | FK   | -                 | クライアントID     |
| ticket_name         | text        | NOT NULL | -    | -                 | チケット名         |
| ticket_type         | text        | NOT NULL | -    | -                 | チケット種別       |
| total_sessions      | integer     | NOT NULL | -    | -                 | 総セッション数     |
| remaining_sessions  | integer     | NOT NULL | -    | -                 | 残りセッション数   |
| valid_from          | date        | NOT NULL | -    | -                 | 有効期限開始日     |
| valid_until         | date        | NOT NULL | -    | -                 | 有効期限終了日     |
| created_at          | timestamptz | NOT NULL | -    | now()             | 購入日時           |

**制約:**
- PRIMARY KEY: id
- FOREIGN KEY: client_id → clients.client_id (ON DELETE CASCADE)
- CHECK: total_sessions > 0
- CHECK: remaining_sessions >= 0 AND remaining_sessions <= total_sessions
- CHECK: valid_from <= valid_until
- RLS: 有効

**インデックス:**
- PRIMARY KEY index on id
- INDEX on client_id（検索高速化）
- INDEX on valid_until（有効期限チェック高速化）

**リレーション:**
- client_id → clients.client_id (N:1)

**備考:**
- チケット消費は別機能（予約機能）で実施
- 有効期限切れのチケットも削除せず履歴として保持
- 残りセッション数が0になっても削除しない

---

## 4. データフロー

### 4.1 ユーザー登録フロー
1. トレーナーがauth.usersに登録される
2. profilesテーブルにトレーナー情報が作成される
3. トレーナーがクライアントをclientsテーブルに登録

### 4.2 メッセージ送信フロー
1. トレーナーまたはクライアントがメッセージを作成
2. messagesテーブルに送信者・受信者情報とともに保存
3. sender_type/receiver_typeで送信者・受信者の種別を識別

### 4.3 LINE連携フロー
1. クライアントがLINEログインを実行
2. clients.line_user_idにLINE IDが登録される
3. LINE経由でのメッセージ送受信が可能になる

---

## 5. 改善提案

### 5.1 設計上の課題
1. **line_usersテーブルの用途不明確**
   - clientsテーブルにもline_user_idがあり、役割が重複
   - どちらを使用するか統一すべき

2. **messagesテーブルの参照整合性**
   - sender_id/receiver_idが外部キー制約なし
   - データ整合性を保証するため、CHECK制約またはトリガーの追加を推奨

3. **インデックスの不足**
   - messagesテーブルにsender_id, receiver_id, timestampのインデックスがない
   - メッセージ検索のパフォーマンス向上のため追加を推奨

### 5.2 推奨する改善策

#### messagesテーブルにインデックス追加
```sql
CREATE INDEX idx_messages_sender ON messages(sender_id, timestamp DESC);
CREATE INDEX idx_messages_receiver ON messages(receiver_id, timestamp DESC);
CREATE INDEX idx_messages_conversation ON messages(sender_id, receiver_id, timestamp DESC);
```

#### sender_type/receiver_typeのCHECK制約追加
```sql
ALTER TABLE messages 
ADD CONSTRAINT check_sender_type 
CHECK (sender_type IN ('trainer', 'client'));

ALTER TABLE messages 
ADD CONSTRAINT check_receiver_type 
CHECK (receiver_type IN ('trainer', 'client'));
```

---

## 6. セキュリティ考慮事項

### 6.1 Row Level Security (RLS)
- profiles: 有効 - トレーナーは自分の情報のみアクセス可能
- clients: 有効 - トレーナーは自分のクライアントのみアクセス可能
- messages: 有効 - 送信者・受信者のみメッセージを閲覧可能
- line_users: 無効 - 必要に応じて有効化を検討

### 6.2 認証
- Supabase Authを使用
- profiles.idがauth.users.idと連携

---

## 7. 使用状況サマリー（2025年10月12日時点）

- **トレーナー数:** 1名
- **クライアント数:** 4名
- **メッセージ総数:** 32件
- **LINE連携済みクライアント:** 2名
- **システム稼働期間:** 2025年7月6日〜現在

---

## 8. 今後の拡張案

1. **添付ファイル機能**
   - message_attachmentsテーブルの追加
   - 画像・動画の共有機能

2. **トレーニング記録機能**
   - training_sessionsテーブル
   - workout_logsテーブル

3. **通知機能**
   - notificationsテーブル
   - メッセージ受信時のプッシュ通知

4. **レポート機能**
   - クライアントの進捗管理
   - トレーニング履歴の可視化