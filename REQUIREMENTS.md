# FIT-CONNECT トレーナー向けウェブアプリ 要件定義書

**バージョン**: 1.0
**作成日**: 2026年2月1日
**対象**: トレーナー向けNext.jsウェブアプリ

---

## 目次

1. [プロジェクト概要](#1-プロジェクト概要)
2. [システム構成](#2-システム構成)
3. [機能要件](#3-機能要件)
4. [非機能要件](#4-非機能要件)
5. [画面一覧・遷移](#5-画面一覧遷移)
6. [データベース設計](#6-データベース設計)
7. [API設計](#7-api設計)
8. [MVP範囲](#8-mvp範囲)
9. [開発ロードマップ](#9-開発ロードマップ)

---

## 1. プロジェクト概要

### 1.1 アプリ名・目的

**アプリ名**: FIT-CONNECT（トレーナー向けウェブアプリ）

**目的**:
フィットネストレーナーがクライアントを効率的に管理するためのウェブアプリケーション。クライアントの記録確認、メッセージング、スケジュール管理、進捗トラッキングを一元化し、トレーナーの業務効率化を支援する。

### 1.2 ターゲットユーザー

- **メインターゲット**: パーソナルトレーナー、フィットネスインストラクター
- **規模**: 個人〜小規模ジム（クライアント数: 10〜100名程度）
- **利用環境**: PC/タブレット（レスポンシブ対応）

### 1.3 コンセプト

**「クライアントの成長を一目で把握」**

- クライアントの記録（体重・食事・運動）を俯瞰的に確認
- リアルタイムメッセージで迅速なフィードバック
- スケジュール管理でセッションを効率化
- アラート機能で対応漏れを防止

### 1.4 関連アプリ

| アプリ | 対象 | プラットフォーム | 役割 |
|--------|------|------------------|------|
| **FIT-CONNECT Web** | トレーナー | Next.js (Web) | クライアント管理・メッセージ・スケジュール |
| **FIT-CONNECT Mobile** | クライアント | Flutter (iOS/Android) | 記録入力・トレーナーとのコミュニケーション |

---

## 2. システム構成

### 2.1 技術スタック

#### フロントエンド
- **フレームワーク**: Next.js 15 (App Router)
- **言語**: TypeScript
- **スタイリング**: Tailwind CSS
- **UIライブラリ**: Radix UI
- **状態管理**: Zustand (localStorage永続化)
- **フォーム**: React Hook Form + Zod

#### バックエンド
- **BaaS**: Supabase
  - Database (PostgreSQL)
  - Authentication
  - Storage
  - Realtime

#### 開発ツール
- **パッケージマネージャー**: npm
- **リンター**: ESLint
- **バージョン管理**: Git

### 2.2 アーキテクチャ

```
[トレーナー向けウェブアプリ (Next.js)]
        ↓
[Supabase]
  ├─ Authentication (メール + パスワード)
  ├─ Database (PostgreSQL + RLS)
  ├─ Storage (画像保存)
  └─ Realtime (メッセージ同期)
        ↓
[クライアント向けアプリ (Flutter)]
```

### 2.3 Supabaseクライアント構成

**デュアルクライアントパターン**:

| クライアント | ファイル | 用途 | キー |
|-------------|----------|------|------|
| **Browser Client** | `src/lib/supabase.ts` | クライアントサイド操作 | `NEXT_PUBLIC_SUPABASE_ANON_KEY` |
| **Admin Client** | `src/lib/supabaseAdmin.ts` | サーバーサイド/API操作 | `SUPABASE_SERVICE_ROLE_KEY` |

---

## 3. 機能要件

### 3.1 認証

#### 3.1.1 ログイン

**認証方式**: メールアドレス + パスワード

**処理フロー**:
1. メールアドレス・パスワード入力
2. `supabase.auth.signInWithPassword()` 実行
3. 認証成功 → `/dashboard` へリダイレクト
4. 認証失敗 → エラーメッセージ表示

**エラーハンドリング**:
- 無効なメールアドレス
- パスワード不一致
- ユーザー未登録

#### 3.1.2 サインアップ

**処理フロー**:
1. 名前・メールアドレス・パスワード入力
2. `supabase.auth.signUp()` 実行
3. `trainers` テーブルにレコード作成
4. 登録成功 → `/dashboard` へリダイレクト

**バリデーション**:
- 名前: 必須、1〜50文字
- メール: 必須、有効なメール形式
- パスワード: 必須、6文字以上

---

### 3.2 ダッシュボード

#### 3.2.1 画面構成

```
┌─────────────────────────────────────────────────┐
│ ダッシュボード                                  │
├─────────────────────────────────────────────────┤
│ ┌─────────┬─────────┬─────────┬─────────┐       │
│ │総顧客数 │アクティブ│今週の   │期限切れ │       │
│ │         │顧客数    │メッセージ│チケット│       │
│ │   10    │    8    │   24    │   2    │       │
│ └─────────┴─────────┴─────────┴─────────┘       │
│                                                 │
│ ┌─────────────────┐ ┌─────────────────┐         │
│ │ 最近のメッセージ│ │ 本日の予定       │         │
│ │                 │ │                 │         │
│ │ 佐藤さん: ...   │ │ 10:00 佐藤さん  │         │
│ │ 田中さん: ...   │ │ 14:00 田中さん  │         │
│ └─────────────────┘ └─────────────────┘         │
│                                                 │
│ ┌─────────────────────────────────────┐         │
│ │ アラート                             │         │
│ │ ⚠ 7日以上記録なし: 山田さん         │         │
│ │ ⚠ チケット残り30日: 鈴木さん        │         │
│ └─────────────────────────────────────┘         │
└─────────────────────────────────────────────────┘
```

#### 3.2.2 KPIカード

| 指標 | 説明 | 取得関数 |
|------|------|----------|
| 総顧客数 | 全クライアント数 | `getClientCount()` |
| アクティブ顧客数 | 7日以内に記録ありの顧客数 | `getActiveClientCount()` |
| 今週のメッセージ | 今週の受信メッセージ数 | `getRecentMessageCount()` |
| 期限切れチケット | 30日以内に期限切れのチケット数 | `getExpiringTickets()` |

#### 3.2.3 最近のメッセージ

- クライアントからの最新メッセージ5件を表示
- クリックでメッセージ画面へ遷移
- 取得関数: `getRecentMessages()`

#### 3.2.4 本日の予定

- 当日のセッション一覧を表示
- ステータス（予約済み/確定/完了/キャンセル）
- 取得関数: `getTodaysSessions()`

#### 3.2.5 アラート

**アラート種別**:

| 種別 | 条件 | アイコン |
|------|------|----------|
| 非アクティブ顧客 | 7日以上記録なし | ⚠️ |
| 期限切れチケット | 30日以内に有効期限終了 | 📅 |

**取得関数**:
- `getInactiveClients()` - 非アクティブ顧客リスト
- `getExpiringTickets()` - 期限切れ間近チケット

---

### 3.3 クライアント管理

#### 3.3.1 クライアント一覧

**表示内容**:
- クライアントカード（アバター、名前、年齢、性別、目的）
- 検索・フィルター機能

**検索・フィルター**:

| フィルター | オプション |
|-----------|-----------|
| 名前検索 | 部分一致 |
| 性別 | すべて / 男性 / 女性 / その他 |
| 年齢 | すべて / 〜19歳 / 20〜29歳 / 30〜39歳 / 40〜49歳 / 50歳〜 |
| 目的 | すべて / ダイエット / コンテスト / ボディメイク / 健康維持 / メンタル向上 / パフォーマンス向上 |

**取得関数**: `searchClients()`

#### 3.3.2 クライアント詳細

**画面構成**:

1. **基本情報セクション**
   - プロフィール画像
   - 名前、年齢、性別
   - 身長、目標体重
   - 目的、目標説明

2. **体重推移セクション**
   - 現在体重、開始時体重、目標体重
   - 体重記録一覧（日付、体重、変動）
   - ※グラフ表示は将来実装

3. **食事記録セクション**
   - 期間フィルター
   - 記録一覧（日時、食事区分、内容、画像）
   - ページネーション対応

4. **運動記録セクション**
   - 期間フィルター
   - 記録一覧（日時、運動種目、時間、距離、メモ）
   - ページネーション対応

5. **チケット情報セクション**
   - チケット一覧（名称、残回数/総回数、有効期限）

**取得関数**:
- `getClientDetail()` - 基本情報
- `getWeightRecords()` - 体重記録
- `getMealRecords()` - 食事記録（ページネーション）
- `getExerciseRecords()` - 運動記録（ページネーション）
- `getTickets()` - チケット情報

---

### 3.4 メッセージ機能

#### 3.4.1 画面構成

```
┌───────────────────────────────────────────────┐
│ メッセージ                                     │
├─────────────────┬─────────────────────────────┤
│                 │                             │
│ クライアント一覧│ チャット画面                 │
│                 │                             │
│ ┌─────────────┐ │ ┌─────────────────────────┐ │
│ │ 佐藤さん    │ │ │ 佐藤さん               │ │
│ │ 最新: ...   │ │ │                         │ │
│ ├─────────────┤ │ │ [クライアントメッセージ] │ │
│ │ 田中さん    │ │ │                         │ │
│ │ 最新: ...   │ │ │ [トレーナーメッセージ]   │ │
│ └─────────────┘ │ │                         │ │
│                 │ ├─────────────────────────┤ │
│                 │ │ メッセージ入力          │ │
│                 │ └─────────────────────────┘ │
└─────────────────┴─────────────────────────────┘
```

#### 3.4.2 基本仕様

**機能**:
- テキストメッセージ送受信
- 画像添付・表示（トレーナー・クライアント双方）
- メッセージ編集（送信後5分以内）
- メッセージへの返信（リプライ）
- リアルタイム更新（Supabase Realtime）
- 送信者タイプ表示（trainer/client）

**Realtime購読**:
```typescript
supabase
  .channel('message-room')
  .on('postgres_changes', {
    event: 'INSERT',
    schema: 'public',
    table: 'messages',
    filter: `receiver_id=eq.${trainerId}`,
  }, handleNewMessage)
  .subscribe()
```

#### 3.4.3 メッセージ送信

**フロー**:
1. メッセージ入力
2. POST `/api/messages/send`
3. `supabaseAdmin` でメッセージ保存
4. クライアントにリアルタイム配信

**取得・送信関数**:
- `getMessages()` - メッセージ取得
- `sendMessage()` - メッセージ送信（API経由）
- `getClients()` - サイドバー用クライアント一覧

#### 3.4.4 画像添付・表示

**画像添付**:
- トレーナーがメッセージに画像を添付可能
- 最大3枚まで添付可能
- 対応フォーマット: JPEG, PNG, GIF
- Supabase Storageに保存

**画像表示**:
- トレーナー・クライアント双方の送信画像を表示
- サムネイル表示（クリックで拡大）
- `image_urls` カラムに配列として保存

**保存先**: Supabase Storage
- バケット: `message-images`
- パス: `{trainer_id}/{message_id}/{filename}`

#### 3.4.5 メッセージ編集

**編集条件**:
- 送信後5分以内のみ編集可能
- 自分が送信したメッセージのみ編集可能

**編集フロー**:
1. メッセージを長押し/右クリック → 「編集」選択
2. 編集モーダル表示
3. 内容を修正して保存
4. `edited_at` タイムスタンプ記録
5. `is_edited` フラグを `true` に設定

**表示**:
- 編集済みメッセージには「(編集済み)」ラベル表示
- 編集日時をツールチップで表示

**関連カラム**:
- `edited_at` (TIMESTAMPTZ) - 編集日時
- `is_edited` (BOOLEAN) - 編集フラグ

#### 3.4.6 メッセージ返信（リプライ）

**目的**: 特定のメッセージに対してコメント・返信を行う

**返信フロー**:
1. メッセージを長押し/右クリック → 「返信」選択
2. 入力欄に引用表示
3. 返信メッセージを入力して送信
4. `reply_to_message_id` で元メッセージと紐付け

**表示**:
```
┌─────────────────────────────────┐
│ [クライアントメッセージ]         │
│ #食事:昼食 サラダチキン食べました │
│ [🖼️🖼️]                         │
│ 12:30                           │
│                                 │
│ ┌─────────────────────────────┐ │ ← リプライ
│ │ トレーナー                   │ │
│ │ ┌─ 返信元 ─────────────────┐│ │
│ │ │ サラダチキン食べました     ││ │
│ │ └───────────────────────────┘│ │
│ │ タンパク質しっかり取れてます │ │
│ │ ね！Good！                   │ │
│ │ 13:15                       │ │
│ └─────────────────────────────┘ │
└─────────────────────────────────┘
```

**関連カラム**:
- `reply_to_message_id` (UUID, FK) - リプライ先メッセージID

---

### 3.5 スケジュール管理

#### 3.5.1 カレンダービュー

**ビュー切り替え**:
- 日表示
- 週表示
- 月表示

**表示内容**:
- セッション予定
- ステータスによる色分け

#### 3.5.2 セッション管理

**セッションステータス**:

| ステータス | 説明 | 色 |
|-----------|------|-----|
| scheduled | 予約済み | 青 |
| confirmed | 確定 | 緑 |
| completed | 完了 | グレー |
| cancelled | キャンセル | 赤 |

**セッション情報**:
- クライアント
- 日時
- 所要時間（デフォルト: 60分）
- セッション種別
- 使用チケット（任意）
- メモ

**CRUD操作**:
- 作成: `createSession()`
- 更新: `updateSession()`
- 削除: `deleteSession()`
- 取得: `getSessions()`

#### 3.5.3 セッションモーダル

**作成/編集モーダル**:
- クライアント選択（ドロップダウン）
- 日付・時間選択
- 所要時間
- セッション種別
- チケット選択（任意）
- メモ

---

### 3.6 クライアント目標管理

#### 3.6.1 目標設定（トレーナーが設定）

**設定項目**:
- 開始時体重（initial_weight）
- 目標体重（target_weight）
- 目標期日（goal_deadline）※任意
- 目標説明（goal_description）※任意

**設定場所**: クライアント詳細画面または編集モーダル

#### 3.6.2 目標達成通知

**判定タイミング**: クライアントが体重記録を作成時

**判定条件**:
```typescript
// 減量目標
if (initialWeight > targetWeight) {
  isAchieved = currentWeight <= targetWeight;
}
// 増量目標
else {
  isAchieved = currentWeight >= targetWeight;
}
```

**達成時の処理**:
- `clients.goal_achieved_at` に日時記録
- ダッシュボードに通知表示

---

### 3.7 未実装機能（プレースホルダー）

#### 3.7.1 レポート `/report`

**計画機能**:
- クライアント進捗レポート
- 期間別統計（体重変動、記録頻度）
- エクスポート機能（PDF/CSV）

#### 3.7.2 ワークアウトプラン `/workoutplan`

**計画機能**:
- トレーニングメニュー作成
- クライアントへのプラン割り当て
- 実施記録との連携

#### 3.7.3 設定 `/settings`

**計画機能**:
- プロフィール編集
- 通知設定
- アカウント管理

---

## 4. 非機能要件

### 4.1 セキュリティ

#### 4.1.1 認証・認可

- Supabase Auth によるセッション管理
- Row Level Security (RLS) による権限制御
- API Routesでの認証検証

#### 4.1.2 RLSポリシー

**原則**: トレーナーは自分に紐づくデータのみアクセス可能

```sql
-- 例: trainersテーブル
CREATE POLICY "Trainers can view own profile"
ON trainers FOR SELECT
USING (id = auth.uid());

-- 例: clientsテーブル
CREATE POLICY "Trainers can view own clients"
ON clients FOR SELECT
USING (trainer_id = auth.uid());
```

#### 4.1.3 環境変数

| 変数名 | 用途 | 公開 |
|--------|------|------|
| `NEXT_PUBLIC_SUPABASE_URL` | Supabase URL | 公開 |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | 匿名キー | 公開 |
| `SUPABASE_SERVICE_ROLE_KEY` | 管理キー | 非公開 |

### 4.2 パフォーマンス

#### 4.2.1 データ取得最適化

- ページネーション（食事・運動記録）
- 適切なインデックス設定
- 必要なカラムのみSELECT

#### 4.2.2 リアルタイム

- メッセージのみRealtime使用
- 他データは必要時に再取得

### 4.3 レスポンシブデザイン

**対応デバイス**:
- デスクトップ (1280px以上)
- タブレット (768px〜1279px)
- モバイル (767px以下) ※将来対応

**サイドバー**:
- デフォルト: 折りたたみ（アイコンのみ）
- ホバー: 展開（テキスト表示）

### 4.4 アクセシビリティ

- Radix UIによるWAI-ARIA準拠
- キーボードナビゲーション対応
- 適切なラベル・alt属性

---

## 5. 画面一覧・遷移

### 5.1 画面一覧

#### 認証関連

| 画面 | パス | 実装状況 |
|------|------|----------|
| ログイン | `/login` | ✅ 完了 |
| サインアップ | `/signup` | ✅ 完了 |

#### メイン機能（サイドナビゲーション）

| 画面 | パス | 実装状況 |
|------|------|----------|
| ダッシュボード | `/dashboard` | ✅ 完了 |
| クライアント一覧 | `/clients` | ✅ 完了 |
| クライアント詳細 | `/clients/[client_id]` | ✅ 完了 |
| メッセージ | `/message` | ✅ 完了 |
| スケジュール | `/schedule` | ✅ 完了 |
| レポート | `/report` | 🚧 プレースホルダー |
| ワークアウトプラン | `/workoutplan` | 🚧 プレースホルダー |
| 設定 | `/settings` | 🚧 プレースホルダー |

### 5.2 画面遷移フロー

```
[未認証]
  └── /login ─────────────→ /dashboard
  └── /signup ────────────→ /dashboard

[認証済み] ─ サイドナビゲーション ─
  ├── /dashboard
  │     └── クライアントクリック → /clients/[id]
  │     └── メッセージクリック → /message
  │     └── 予定クリック → /schedule
  │
  ├── /clients
  │     └── クライアントカードクリック → /clients/[id]
  │
  ├── /clients/[id]
  │     └── 戻る → /clients
  │
  ├── /message
  │     └── クライアント選択 → チャット表示
  │
  ├── /schedule
  │     └── 予定クリック → モーダル表示
  │
  ├── /report (将来実装)
  ├── /workoutplan (将来実装)
  └── /settings (将来実装)
```

### 5.3 レイアウト構成

```
┌──────────────────────────────────────────┐
│ (user_console) Layout                    │
├────────┬─────────────────────────────────┤
│        │                                 │
│ Side   │  Page Content                   │
│ bar    │                                 │
│        │                                 │
│ ┌────┐ │                                 │
│ │ 📊 │ │                                 │
│ │ 👥 │ │                                 │
│ │ 💬 │ │                                 │
│ │ 📅 │ │                                 │
│ │ 📈 │ │                                 │
│ │ 🏋️ │ │                                 │
│ │ ⚙️ │ │                                 │
│ └────┘ │                                 │
│        │                                 │
└────────┴─────────────────────────────────┘
```

---

## 6. データベース設計

### 6.1 ER図

```
┌─────────────┐     ┌─────────────┐
│  trainers   │     │   clients   │
├─────────────┤     ├─────────────┤
│ id (PK)     │←───┤│ trainer_id  │
│ name        │     │ client_id(PK)│
│ email       │     │ name        │
│ profile_    │     │ email       │
│  image_url  │     │ gender      │
└─────────────┘     │ age         │
                    │ height      │
                    │ target_weight│
                    │ initial_    │
                    │  weight     │
                    │ purpose     │
                    │ goal_*      │
                    └──────┬──────┘
                           │
         ┌─────────────────┼─────────────────┐
         │                 │                 │
         ▼                 ▼                 ▼
┌─────────────┐   ┌─────────────┐   ┌─────────────┐
│weight_records│   │ meal_records│   │exercise_    │
├─────────────┤   ├─────────────┤   │ records     │
│ id (PK)     │   │ id (PK)     │   ├─────────────┤
│ client_id   │   │ client_id   │   │ id (PK)     │
│ weight      │   │ meal_type   │   │ client_id   │
│ recorded_at │   │ notes       │   │ exercise_   │
│ notes       │   │ calories    │   │  type       │
│ source      │   │ images      │   │ duration    │
│ message_id  │   │ recorded_at │   │ distance    │
└─────────────┘   │ source      │   │ calories    │
                  │ message_id  │   │ memo        │
                  └─────────────┘   │ images      │
                                    │ recorded_at │
                                    │ source      │
                                    │ message_id  │
                                    └─────────────┘

┌─────────────┐        ┌─────────────┐
│  messages   │        │   tickets   │
├─────────────┤        ├─────────────┤
│ id (PK)     │        │ id (PK)     │
│ sender_id   │        │ client_id   │
│ receiver_id │        │ ticket_name │
│ sender_type │        │ ticket_type │
│ receiver_   │        │ total_      │
│  type       │        │  sessions   │
│ content     │        │ remaining_  │
│ image_urls  │        │  sessions   │
│ tags        │        │ valid_from  │
│ reply_to_   │        │ valid_until │
│  message_id │        └──────┬──────┘
│ created_at  │               │
│ read_at     │               ▼
│ edited_at   │        ┌─────────────┐
│ is_edited   │        │  sessions   │
└─────────────┘        ├─────────────┤
                       │ id (PK)     │
                       │ trainer_id  │
                       │ client_id   │
                       │ ticket_id   │
                       │ session_date│
                       │ duration_   │
                       │  minutes    │
                       │ status      │
                       │ session_type│
                       │ memo        │
                       └─────────────┘
```

### 6.2 テーブル定義

#### trainers（トレーナー）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | auth.users.id と同一 |
| name | TEXT | トレーナー名 |
| email | TEXT | メールアドレス |
| profile_image_url | TEXT | プロフィール画像URL |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

#### clients（クライアント）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| client_id | UUID (PK) | クライアントID |
| trainer_id | UUID (FK) | 担当トレーナーID |
| name | TEXT | 名前 |
| email | TEXT | メールアドレス |
| gender | TEXT | 性別 (male/female/other) |
| age | INTEGER | 年齢 |
| occupation | TEXT | 職業 |
| height | NUMERIC | 身長 (cm) |
| target_weight | NUMERIC | 目標体重 (kg) |
| initial_weight | NUMERIC | 開始時体重 (kg) |
| purpose | TEXT | 目的 |
| goal_description | TEXT | 目標の詳細説明 |
| goal_deadline | DATE | 目標期日 |
| goal_set_at | TIMESTAMPTZ | 目標設定日時 |
| goal_achieved_at | TIMESTAMPTZ | 目標達成日時 |
| profile_image_url | TEXT | プロフィール画像URL |
| line_user_id | TEXT | LINE ID (非推奨) |
| created_at | TIMESTAMPTZ | 作成日時 |

#### messages（メッセージ）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | メッセージID |
| sender_id | UUID | 送信者ID |
| receiver_id | UUID | 受信者ID |
| sender_type | TEXT | 送信者タイプ (trainer/client) |
| receiver_type | TEXT | 受信者タイプ (trainer/client) |
| content | TEXT | メッセージ本文 |
| image_urls | TEXT[] | 画像URL配列 |
| tags | TEXT[] | タグ配列 |
| reply_to_message_id | UUID (FK) | リプライ先メッセージID |
| read_at | TIMESTAMPTZ | 既読日時 |
| edited_at | TIMESTAMPTZ | 編集日時 |
| is_edited | BOOLEAN | 編集フラグ |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

#### weight_records（体重記録）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | 記録ID |
| client_id | UUID (FK) | クライアントID |
| weight | NUMERIC | 体重 (kg) |
| notes | TEXT | メモ |
| recorded_at | TIMESTAMPTZ | 記録日時 |
| source | TEXT | 記録元 (manual/message) |
| message_id | UUID (FK) | 元メッセージID |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

#### meal_records（食事記録）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | 記録ID |
| client_id | UUID (FK) | クライアントID |
| meal_type | TEXT | 食事区分 (breakfast/lunch/dinner/snack) |
| notes | TEXT | メモ |
| calories | NUMERIC | カロリー (kcal) |
| images | TEXT[] | 画像URL配列 |
| recorded_at | TIMESTAMPTZ | 記録日時 |
| source | TEXT | 記録元 (manual/message) |
| message_id | UUID (FK) | 元メッセージID |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

#### exercise_records（運動記録）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | 記録ID |
| client_id | UUID (FK) | クライアントID |
| exercise_type | TEXT | 運動種目 |
| duration | INTEGER | 時間 (分) |
| distance | NUMERIC | 距離 (km) |
| calories | NUMERIC | 消費カロリー (kcal) |
| memo | TEXT | メモ |
| images | TEXT[] | 画像URL配列 |
| recorded_at | TIMESTAMPTZ | 記録日時 |
| source | TEXT | 記録元 (manual/message) |
| message_id | UUID (FK) | 元メッセージID |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

#### tickets（チケット）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | チケットID |
| client_id | UUID (FK) | クライアントID |
| ticket_name | TEXT | チケット名 |
| ticket_type | TEXT | チケット種別 |
| total_sessions | INTEGER | 総セッション数 |
| remaining_sessions | INTEGER | 残りセッション数 |
| valid_from | DATE | 有効期間開始日 |
| valid_until | DATE | 有効期間終了日 |
| created_at | TIMESTAMPTZ | 作成日時 |

#### sessions（セッション予約）

| カラム名 | 型 | 説明 |
|----------|-----|------|
| id | UUID (PK) | セッションID |
| trainer_id | UUID (FK) | トレーナーID |
| client_id | UUID (FK) | クライアントID |
| ticket_id | UUID (FK) | 使用チケットID |
| session_date | TIMESTAMPTZ | セッション日時 |
| duration_minutes | INTEGER | 所要時間 (分) |
| status | TEXT | ステータス |
| session_type | TEXT | セッション種別 |
| memo | TEXT | メモ |
| created_at | TIMESTAMPTZ | 作成日時 |
| updated_at | TIMESTAMPTZ | 更新日時 |

### 6.3 定数値

#### gender（性別）

| 値 | 表示名 |
|----|--------|
| male | 男性 |
| female | 女性 |
| other | その他 |

#### purpose（目的）

| 値 | 表示名 |
|----|--------|
| diet | ダイエット |
| contest | コンテスト |
| body_make | ボディメイク |
| health_improvement | 健康維持・生活習慣の改善 |
| mental_improvement | メンタル・自己肯定感向上 |
| performance_improvement | パフォーマンス向上 |

#### meal_type（食事区分）

| 値 | 表示名 |
|----|--------|
| breakfast | 朝食 |
| lunch | 昼食 |
| dinner | 夕食 |
| snack | 間食 |

#### exercise_type（運動種目）

| 値 | 表示名 |
|----|--------|
| walking | ウォーキング |
| running | ランニング |
| strength_training | 筋トレ |
| cardio | 有酸素運動 |
| cycling | サイクリング |
| swimming | 水泳 |
| yoga | ヨガ |
| pilates | ピラティス |
| other | その他 |

#### session status（セッションステータス）

| 値 | 表示名 |
|----|--------|
| scheduled | 予約済み |
| confirmed | 確定 |
| completed | 完了 |
| cancelled | キャンセル |

---

## 7. API設計

### 7.1 API Routes

#### POST /api/messages/send

**目的**: トレーナーからクライアントへのメッセージ送信

**リクエスト**:
```json
{
  "trainerId": "uuid",
  "clientId": "uuid",
  "content": "メッセージ本文"
}
```

**レスポンス**:
```json
{
  "status": "ok"
}
```

**処理**:
1. リクエストボディのバリデーション
2. `supabaseAdmin` でメッセージ挿入
3. sender_type: 'trainer', receiver_type: 'client' を設定

### 7.2 データベース操作関数

**ファイル規約**: `src/lib/supabase/[操作名].ts`（1操作1ファイル）

#### トレーナー関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `createTrainer` | `createTrainer.ts` | トレーナー作成 |
| `getTrainer` | `getTrainer.ts` | トレーナー情報取得 |

#### クライアント関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `getClients` | `getClients.ts` | クライアント一覧取得 |
| `getClientDetail` | `getClientDetail.ts` | クライアント詳細取得 |
| `searchClients` | `searchClients.ts` | クライアント検索 |
| `getClientCount` | `getClientCount.ts` | クライアント総数 |
| `getActiveClientCount` | `getActiveClientCount.ts` | アクティブ顧客数 |
| `getInactiveClients` | `getInactiveClients.ts` | 非アクティブ顧客リスト |

#### メッセージ関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `getMessages` | `getMessages.ts` | メッセージ取得 |
| `sendMessage` | `sendMessage.ts` | メッセージ送信 |
| `getRecentMessages` | `getRecentMessages.ts` | 最近のメッセージ |
| `getRecentMessageCount` | `getRecentMessageCount.ts` | 今週のメッセージ数 |

#### 記録関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `getWeightRecords` | `getWeightRecords.ts` | 体重記録取得 |
| `getMealRecords` | `getMealRecords.ts` | 食事記録取得 |
| `getExerciseRecords` | `getExerciseRecords.ts` | 運動記録取得 |

#### チケット関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `getTickets` | `getTickets.ts` | チケット取得 |
| `getExpiringTickets` | `getExpiringTickets.ts` | 期限切れ間近チケット |
| `updateTicket` | `updateTicket.ts` | チケット更新 |

#### セッション関連

| 関数名 | ファイル | 用途 |
|--------|----------|------|
| `getSessions` | `getSessions.ts` | セッション取得 |
| `getTodaysSessions` | `getTodaysSessions.ts` | 本日のセッション |
| `createSession` | `createSession.ts` | セッション作成 |
| `updateSession` | `updateSession.ts` | セッション更新 |
| `deleteSession` | `deleteSession.ts` | セッション削除 |

---

## 8. MVP範囲

### 8.1 実装済み機能 ✅

#### 認証
- ✅ メール/パスワードログイン
- ✅ トレーナー新規登録
- ✅ セッション管理

#### ダッシュボード
- ✅ KPIカード（顧客数、メッセージ数、チケット）
- ✅ 最近のメッセージプレビュー
- ✅ 本日の予定
- ✅ アラート（非アクティブ顧客、期限切れチケット）

#### クライアント管理
- ✅ クライアント一覧
- ✅ 検索・フィルター機能
- ✅ クライアント詳細表示
- ✅ 体重・食事・運動記録表示
- ✅ チケット情報表示

#### メッセージ
- ✅ 双方向メッセージング
- ✅ リアルタイム更新
- 🚧 画像添付・表示（トレーナー・クライアント双方）
- 🚧 メッセージ編集（送信後5分以内）
- 🚧 メッセージ返信（リプライ機能）

#### スケジュール
- ✅ カレンダービュー（日/週/月）
- ✅ セッションCRUD
- ✅ ステータス管理

### 8.2 未実装機能 🚧

#### Phase 2（次期リリース）
- 🚧 メッセージ画像添付・表示
- 🚧 メッセージ編集（5分以内）
- 🚧 メッセージ返信（リプライ）
- 🚧 体重グラフ表示
- 🚧 クライアント編集機能
- 🚧 チケット管理画面
- 🚧 プッシュ通知

#### Phase 3（将来実装）
- 🚧 レポート機能
- 🚧 ワークアウトプラン
- 🚧 設定画面
- 🚧 クライアントQRコード招待

---

## 9. 開発ロードマップ

### Phase 1: 基盤構築（完了）
- ✅ プロジェクトセットアップ
- ✅ Supabase連携
- ✅ 認証フロー
- ✅ レイアウト・ナビゲーション

### Phase 2: コア機能（完了）
- ✅ ダッシュボード
- ✅ クライアント管理
- ✅ メッセージング
- ✅ スケジュール管理

### Phase 3: 機能拡充（進行中）
- 🔄 体重グラフ表示
- 🔄 クライアント編集
- 🔄 チケット管理強化

### Phase 4: モバイル連携
- 📋 Flutter アプリ開発
- 📋 QRコード招待機能
- 📋 プッシュ通知連携

### Phase 5: 高度機能
- 📋 レポート・分析
- 📋 ワークアウトプラン
- 📋 AI機能（カロリー推定など）

---

## 付録

### A. ディレクトリ構成

```
src/
├── app/
│   ├── (auth)/                    # 認証ルート
│   │   ├── login/
│   │   └── signup/
│   ├── (user_console)/            # メインアプリルート
│   │   ├── clients/
│   │   │   └── [client_id]/
│   │   ├── dashboard/
│   │   ├── message/
│   │   ├── schedule/
│   │   ├── report/
│   │   ├── workoutplan/
│   │   ├── settings/
│   │   └── layout.tsx
│   └── api/
│       └── messages/send/
├── components/
│   ├── clients/
│   ├── dashboard/
│   ├── schedule/
│   └── ui/
├── lib/
│   ├── supabase/                  # DB操作関数
│   ├── supabase.ts                # Browserクライアント
│   └── supabaseAdmin.ts           # Adminクライアント
├── store/
│   └── userStore.ts
└── types/
    └── client.ts
```

### B. 用語集

| 用語 | 説明 |
|------|------|
| トレーナー | 本アプリのメインユーザー（パーソナルトレーナー） |
| クライアント | トレーナーの顧客（Flutterアプリ利用者） |
| セッション | トレーニング予約 |
| チケット | セッション回数券 |
| アクティブ顧客 | 7日以内に記録があるクライアント |
| RLS | Row Level Security（行レベルセキュリティ） |

### C. 関連ドキュメント

- [CLAUDE.md](CLAUDE.md) - 開発ガイドライン
- [ROADMAP.md](ROADMAP.md) - 開発ロードマップ
- Supabase公式ドキュメント: https://supabase.com/docs
- Next.js公式ドキュメント: https://nextjs.org/docs
- Radix UI公式ドキュメント: https://www.radix-ui.com/docs

---

**以上**
