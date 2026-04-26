# FIT-CONNECT クライアントアプリ 要件定義書

**バージョン**: 1.0  
**作成日**: 2025年12月20日  
**対象**: クライアント向けFlutterアプリ

---

## 目次

1. [プロジェクト概要](#1-プロジェクト概要)
2. [システム構成](#2-システム構成)
3. [機能要件](#3-機能要件)
4. [非機能要件](#4-非機能要件)
5. [画面一覧・遷移](#5-画面一覧遷移)
6. [データベース設計](#6-データベース設計)
7. [タグ機能仕様](#7-タグ機能仕様)
8. [MVP範囲](#8-mvp範囲)
9. [開発スケジュール（概算）](#9-開発スケジュール概算)

---

## 1. プロジェクト概要

### 1.1 アプリ名・目的

**アプリ名**: FIT-CONNECT（クライアント向けアプリ）

**目的**: 
フィットネストレーナーとクライアントをつなぐ、メッセージベースの記録管理アプリ。従来の複雑なフォーム入力ではなく、メッセージでタグを付けるだけで記録が完了する革新的なUXを提供する。

### 1.2 ターゲットユーザー

- **メインターゲット**: パーソナルトレーニングを受けているクライアント
- **年齢層**: 若年層〜中年層
- **ITリテラシー**: 比較的高め

### 1.3 コンセプト

**「メッセージで記録が完結する」**

- トレーナーに報告 = 記録作成
- 記録のハードルを極限まで下げる
- トレーナーとのコミュニケーションを促進
- モチベーション維持をサポート

---

## 2. システム構成

### 2.1 技術スタック

#### クライアントアプリ（本アプリ）
- **フレームワーク**: Flutter
- **プラットフォーム**: iOS / Android
- **状態管理**: Riverpod
- **主要ライブラリ**:
  - `supabase_flutter`: バックエンド連携
  - `fl_chart`: グラフ表示
  - `image_picker`: 画像選択
  - `confetti`: アニメーション（目標達成時）
  - `intl`: 日付フォーマット

#### バックエンド
- **BaaS**: Supabase
  - Database (PostgreSQL)
  - Authentication
  - Storage
  - Realtime
  - Edge Functions

#### トレーナー向けアプリ（既存）
- **フレームワーク**: Next.js
- **連携**: 同一Supabaseプロジェクト

### 2.2 アーキテクチャ

```
[クライアントアプリ (Flutter)]
        ↓
[Supabase]
  ├─ Authentication (メール + マジックリンク)
  ├─ Database (PostgreSQL + RLS)
  ├─ Storage (画像保存)
  ├─ Realtime (メッセージ同期)
  └─ Edge Functions (タグ解析・記録作成)
        ↓
[トレーナー向けアプリ (Next.js)]
```

### 2.3 バックエンド構成

- **プロジェクト**: 既存のFIT-CONNECTプロジェクトを共有
- **認証**: Supabase Auth（トレーナーとクライアントで役割分離）
- **データベース**: RLSで権限管理
- **ストレージ**: バケット単位で管理
  - `meal-photos`: 食事写真
  - `exercise-photos`: 運動写真

---

## 3. 機能要件

### 3.1 ログイン・認証

#### 3.1.1 初回登録フロー

1. **QRコード読み取り**
   - トレーナーがWeb管理画面でQRコード表示
   - クライアントがアプリでQRコードスキャン
   - QRコードに含まれる情報: `trainer_id`

2. **メールアドレス入力**
   - QRコード読み取り後、メールアドレス入力画面
   - トレーナー情報（名前・アイコン）を表示

3. **マジックリンク認証**
   - 入力したメールアドレスに認証リンク送信
   - リンクタップでアプリ起動（ディープリンク）
   - 認証完了

4. **登録完了演出**
   - 紙吹雪アニメーション
   - トレーナー情報表示
   - 「トレーナーに報告」ボタン

#### 3.1.2 認証方式

- **メールアドレス + マジックリンク** (パスワードレス)
- セッション保持期間: **6ヶ月**
- 自動トークンリフレッシュ: 有効

#### 3.1.3 データベース連携

```sql
-- 認証完了後の処理
1. clients テーブルに trainer_id と紐付けて作成
2. ホーム画面へ遷移
```

---

### 3.2 メッセージ機能

#### 3.2.1 基本仕様

**役割**: 
- トレーナーとのコミュニケーション
- **記録作成のメイン手段**（タグ付きメッセージ）

**機能**:
- テキストメッセージ送受信
- 画像添付（最大3枚）
- タグ付きメッセージ（自動記録作成）
- リプライ機能（トレーナーからのコメント）
- リアルタイム更新（Supabase Realtime）
- プッシュ通知
- メッセージ編集（5分以内）

#### 3.2.2 タグ機能

**タグの階層構造**:
```
#食事:朝食
#食事:昼食
#食事:夕食
#食事:間食
#運動:筋トレ
#運動:有酸素
#体重
```

**入力補助**:
- `#` 入力時にタグ候補を表示
- 入力中にリアルタイムフィルタ
  - 例: `#食` → 食事関連タグのみ表示
  - 例: `#運` → 運動関連タグのみ表示

**制約**:
- 1メッセージにつき1タグまで
- 複数タグはエラー表示

#### 3.2.3 タグ付きメッセージの処理フロー

```
1. クライアントがタグ付きメッセージ送信
   例: 「#食事:昼食 サラダチキン食べました」+ 📷📷
   ↓
2. messages テーブルに保存
   ↓
3. Database Webhook → Edge Function 起動
   ↓
4. タグ解析
   - タグ種類: 食事
   - 詳細: 昼食
   - メモ: 「サラダチキン食べました」
   - 画像: 2枚
   ↓
5. 対応するテーブルに記録作成
   - meal_records に挿入
     - meal_type: 'lunch'
     - notes: 「サラダチキン食べました」
     - images: [url1, url2]
     - source: 'message'
     - message_id: 紐付け
```

#### 3.2.4 リプライ機能

**目的**: トレーナーが記録に対してコメント

**仕様**:
- タグ付きメッセージを右クリック（長押し）→「返信」
- 引用表示付きの入力欄
- `reply_to_message_id` で紐付け

**表示**:
```
┌─────────────────────────┐
│ [#食事:昼食] 📝記録済み  │
│ サラダチキン食べました   │
│ [🖼️🖼️]                 │
│ 12:30                   │
│                         │
│ ┌─────────────────────┐ │ ← リプライ
│ │ トレーナー           │ │
│ │ タンパク質しっかり   │ │
│ │ 取れてますね! Good!  │ │
│ │ 13:15               │ │
│ └─────────────────────┘ │
└─────────────────────────┘
```

#### 3.2.5 メッセージ編集

- **編集可能期間**: 送信後5分以内
- **挙動**: 
  - メッセージ内容を編集
  - タグが変更された場合、対応する記録も更新
  - `edited_at` タイムスタンプ記録

---

### 3.3 食事記録

#### 3.3.1 記録方法

**メッセージからのみ記録** (専用入力画面なし)

```
例:
#食事:朝食 オートミール 📷
#食事:昼食 サラダチキン 📷📷
#食事:夕食 鶏胸肉とブロッコリー 📷
#食事:間食 プロテインバー
```

#### 3.3.2 記録される情報

```sql
meal_records (
  id UUID,
  client_id UUID,
  meal_type TEXT, -- 'breakfast' | 'lunch' | 'dinner' | 'snack'
  notes TEXT, -- タグを除いたメモ
  images TEXT[], -- 最大3枚（DBは10枚対応）
  calories NUMERIC, -- 将来AI算出
  recorded_at TIMESTAMPTZ, -- メッセージ送信時刻
  source TEXT, -- 'message'
  message_id UUID, -- 元メッセージ
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
```

#### 3.3.3 食事記録画面（閲覧専用）

**画面構成**:
1. 期間選択タブ（今日/今週/今月/全期間）
2. カレンダー（GitHub草スタイル）
3. 記録一覧（時系列）

**カレンダー仕様**:
- 記録数に応じて緑の濃淡
  - 3食: 濃い緑 `#26A641`
  - 2食: 中くらいの緑 `#39D353`
  - 1食: 薄い緑 `#9BE9A8`
  - なし: グレー `#EBEDF0`
- 各日に記録数を数字で表示（③②①）

---

### 3.4 体重記録

#### 3.4.1 記録方法

**メッセージからのみ記録**

```
例:
#体重 65.2kg
#体重 65.2kg 順調です!
#体重 65.2  ← kg省略可
```

**解析ロジック**:
```typescript
parseWeightTag('#体重 65.2kg 順調です!')
// → { weight: 65.2, unit: 'kg', notes: '順調です!' }
```

#### 3.4.2 記録される情報

```sql
weight_records (
  id UUID,
  client_id UUID,
  weight NUMERIC, -- 体重（kg）
  notes TEXT, -- メモ
  recorded_at TIMESTAMPTZ, -- メッセージ送信時刻
  source TEXT, -- 'message'
  message_id UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
```

#### 3.4.3 体重記録画面（閲覧専用）

**画面構成**:
1. 統計カード
   - 現在 / 目標 / 残り / 前回比 / 開始時比
2. 折れ線グラフ
   - 縦軸: 自動調整
   - 目標体重: 点線表示
   - データ補間: 線で補間
3. 詳細統計
   - 期間平均 / 最高 / 最低 / 変動幅
4. 記録一覧

**グラフ仕様**:
- 期間フィルタ: 今週/今月/3ヶ月/全期間
- データポイントタップで詳細表示

---

### 3.5 運動記録

#### 3.5.1 記録方法

**メッセージからのみ記録**

```
例:
#運動:筋トレ 今日のメニュー完了! 📷📷
#運動:有酸素 ランニング 5km
```

#### 3.5.2 記録される情報

```sql
exercise_records (
  id UUID,
  client_id UUID,
  exercise_type TEXT, -- 'strength_training' | 'cardio'
  memo TEXT, -- 自由記述
  images TEXT[], -- 最大3枚
  duration INTEGER, -- 将来実装
  calories NUMERIC, -- 将来実装
  recorded_at TIMESTAMPTZ,
  source TEXT, -- 'message'
  message_id UUID,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
```

#### 3.5.3 運動記録画面（閲覧専用）

**画面構成**:
1. タイプフィルタ（すべて/筋トレ/有酸素）
2. 統計サマリー（総回数/タイプ別回数）
3. 週間カレンダー（アイコン表示）
4. 期間フィルタ（今週/今月/全期間）
5. 記録一覧

**カレンダー仕様**:
- 💪 筋トレのアイコン
- 🏃 有酸素のアイコン

---

### 3.6 目標管理

#### 3.6.1 目標設定

**設定者**: トレーナー（Web管理画面から）

**設定項目**:
- 開始時体重（必須）
- 目標体重（必須）
- 目標期日（任意）
- 目標の詳細説明（任意）

**保存先**:
```sql
clients テーブル:
- initial_weight NUMERIC
- target_weight NUMERIC
- goal_deadline DATE
- goal_description TEXT
- goal_set_at TIMESTAMPTZ
- goal_achieved_at TIMESTAMPTZ
```

#### 3.6.2 達成率計算

```
達成率 = (開始時体重 - 現在の体重) / (開始時体重 - 目標体重) × 100

例:
開始時: 67.5kg
現在: 65.2kg
目標: 60.0kg

達成率 = (67.5 - 65.2) / (67.5 - 60.0) × 100
       = 2.3 / 7.5 × 100
       = 30.7%
```

#### 3.6.3 目標達成時の処理

**判定タイミング**: 体重記録作成時に自動判定

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

**達成時の演出**:
1. 紙吹雪アニメーション（5秒間）
2. プッシュ通知（クライアント + トレーナー）
3. 達成画面表示
   - トロフィーアイコン
   - 「おめでとう!」メッセージ
   - 開始時〜現在の変化表示
   - 「トレーナーに報告」ボタン

#### 3.6.4 目標の更新

- **方式**: 上書き更新（履歴なし）
- **達成後**: `goal_achieved_at` に日時記録
- **再設定時**: 達成フラグをクリア

---

### 3.7 記録確認（統計・グラフ）

#### 3.7.1 ホーム画面「本日のサマリー」

**表示内容**:

1. **🍽️ 食事**
   - 本日の記録数 / 3食
   - プログレスバー
   - 達成率（%）

2. **💪 運動（今週）**
   - 今週の運動回数 / 7日

3. **⚖️ 体重**
   - **本日測定済み**:
     ```
     65.2kg (07:00測定)
     前日比: -0.6kg ↓
     ```
   - **本日未測定**:
     ```
     65.8kg (12/19測定)
     本日未測定
     ```

#### 3.7.2 期間フィルタ（共通）

全記録画面で共通の期間選択:
- 今週（月曜〜日曜）
- 今月
- 3ヶ月
- 全期間

---

## 4. 非機能要件

### 4.1 セキュリティ

#### 4.1.1 認証・認可
- Supabase Auth による認証
- RLS (Row Level Security) による権限管理
- セッション管理: 自動トークンリフレッシュ

#### 4.1.2 データアクセス制御

**基本原則**: クライアントは自分のデータのみアクセス可能

```sql
-- 例: 体重記録のRLS
CREATE POLICY "Clients can view own weight records"
ON weight_records FOR SELECT
USING (client_id = auth.uid());

CREATE POLICY "Clients can insert own weight records"
ON weight_records FOR INSERT
WITH CHECK (client_id = auth.uid());
```

### 4.2 パフォーマンス

#### 4.2.1 画像処理
- アップロード前にクライアント側でリサイズ・圧縮
  - 最大サイズ: 1920x1080
  - 品質: 80%
  - フォーマット: JPEG

#### 4.2.2 データ取得
- 適切なインデックス設定
- ページネーション（記録一覧）
- リアルタイム更新はメッセージのみ

### 4.3 ユーザビリティ

#### 4.3.1 オフライン対応
- MVP段階では非対応
- 将来的にローカルキャッシュ + 同期を検討

#### 4.3.2 エラーハンドリング
- ネットワークエラー: 再試行機能
- バリデーションエラー: 分かりやすいメッセージ
- システムエラー: ログ記録 + ユーザーへの通知

---

## 5. 画面一覧・遷移

### 5.1 画面一覧

#### 認証関連
1. スプラッシュ画面
2. オンボーディング画面（初回のみ）
3. QRコードスキャン画面
4. メールアドレス入力画面
5. 認証メール送信完了画面
6. 登録完了画面（紙吹雪）

#### メインアプリ（ボトムナビゲーション）
7. **ホーム画面**
   - 目標進捗カード
   - 本日のサマリー
   
8. **メッセージ画面**
   - メッセージ一覧
   - タグ入力補助
   
9. **記録画面（タブ切り替え）**
   - 食事記録画面
   - 体重記録画面
   - 運動記録画面

#### その他
10. 目標達成画面
11. 食事記録詳細画面
12. 設定画面（将来実装）

### 5.2 画面遷移フロー

```
[初回登録]
スプラッシュ → オンボーディング → QRスキャン → メール入力 
→ 認証メール送信完了 → [メールリンクタップ] → 登録完了 → ホーム

[2回目以降]
スプラッシュ → ホーム

[メイン画面]
ホーム ⇄ メッセージ ⇄ 記録
  ↓
目標タップ → （タップ不可）
食事タップ → 記録タブ（食事）
運動タップ → 記録タブ（運動）
体重タップ → 記録タブ（体重）

[目標達成]
体重記録作成 → [達成判定] → 目標達成画面 → メッセージ
```

---

## 6. データベース設計

### 6.1 既存テーブル

#### trainers
```sql
trainers (
  id UUID PRIMARY KEY,
  name TEXT NOT NULL,
  email TEXT,
  profile_image_url TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ
)
```

#### clients
```sql
clients (
  client_id UUID PRIMARY KEY,
  name TEXT,
  email TEXT, -- クライアントのメールアドレス
  trainer_id UUID REFERENCES trainers(id),
  gender TEXT,
  age INTEGER,
  height NUMERIC,
  target_weight NUMERIC, -- 既存
  purpose TEXT,
  goal_description TEXT, -- 既存
  profile_image_url TEXT,
  created_at TIMESTAMPTZ
)
```

### 6.2 追加・変更が必要なカラム

#### clients テーブル
```sql
ALTER TABLE clients
ADD COLUMN initial_weight NUMERIC CHECK (initial_weight > 0 AND initial_weight < 500),
ADD COLUMN goal_deadline DATE,
ADD COLUMN goal_set_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN goal_achieved_at TIMESTAMPTZ;
```

#### messages テーブル
```sql
-- カラム名変更
ALTER TABLE messages
RENAME COLUMN message TO content;

ALTER TABLE messages
RENAME COLUMN timestamp TO created_at;

-- 新規カラム追加
ALTER TABLE messages
ADD COLUMN image_urls TEXT[] DEFAULT '{}',
ADD COLUMN tags TEXT[] DEFAULT '{}',
ADD COLUMN reply_to_message_id UUID REFERENCES messages(id),
ADD COLUMN read_at TIMESTAMPTZ,
ADD COLUMN edited_at TIMESTAMPTZ,
ADD COLUMN is_edited BOOLEAN DEFAULT false,
ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス
CREATE INDEX idx_messages_sender_created ON messages(sender_id, created_at DESC);
CREATE INDEX idx_messages_receiver_created ON messages(receiver_id, created_at DESC);
CREATE INDEX idx_messages_reply_to ON messages(reply_to_message_id);
CREATE INDEX idx_messages_tags ON messages USING GIN(tags);
```

#### meal_records テーブル
```sql
-- カラム名変更
ALTER TABLE meal_records
RENAME COLUMN description TO notes;

-- 新規カラム追加
ALTER TABLE meal_records
ADD COLUMN source TEXT DEFAULT 'manual',
ADD COLUMN message_id UUID REFERENCES messages(id),
ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス
CREATE INDEX idx_meal_records_message ON meal_records(message_id);
CREATE INDEX idx_meal_records_client_date ON meal_records(client_id, recorded_at DESC);
```

#### weight_records テーブル
```sql
ALTER TABLE weight_records
ADD COLUMN notes TEXT,
ADD COLUMN source TEXT DEFAULT 'manual',
ADD COLUMN message_id UUID REFERENCES messages(id),
ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス
CREATE INDEX idx_weight_records_message ON weight_records(message_id);
CREATE INDEX idx_weight_records_client_date ON weight_records(client_id, recorded_at DESC);
```

#### exercise_records テーブル
```sql
-- exercise_type に 'cardio' を追加
ALTER TABLE exercise_records
DROP CONSTRAINT exercise_records_exercise_type_check;

ALTER TABLE exercise_records
ADD CONSTRAINT exercise_records_exercise_type_check
CHECK (exercise_type IN (
  'walking', 'running', 'strength_training', 'cardio', 
  'cycling', 'swimming', 'yoga', 'pilates', 'other'
));

-- 新規カラム追加
ALTER TABLE exercise_records
ADD COLUMN source TEXT DEFAULT 'manual',
ADD COLUMN message_id UUID REFERENCES messages(id),
ADD COLUMN images TEXT[],
ADD COLUMN created_at TIMESTAMPTZ DEFAULT NOW(),
ADD COLUMN updated_at TIMESTAMPTZ DEFAULT NOW();

-- インデックス
CREATE INDEX idx_exercise_records_message ON exercise_records(message_id);
CREATE INDEX idx_exercise_records_client_date ON exercise_records(client_id, recorded_at DESC);
```

### 6.3 RLSポリシー例

#### messages テーブル
```sql
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- 閲覧: 送信者または受信者
CREATE POLICY "Users can view their messages"
ON messages FOR SELECT
USING (sender_id = auth.uid() OR receiver_id = auth.uid());

-- 作成: 送信者のみ
CREATE POLICY "Users can send messages"
ON messages FOR INSERT
WITH CHECK (sender_id = auth.uid());

-- 更新: 送信者のみ（5分以内）
CREATE POLICY "Users can edit own messages within 5 minutes"
ON messages FOR UPDATE
USING (
  sender_id = auth.uid() 
  AND (NOW() - created_at) < INTERVAL '5 minutes'
);
```

---

## 7. タグ機能仕様

### 7.1 タグ一覧

#### カテゴリタグ（入力補助用）
- `#食事`
- `#運動`
- `#体重`

#### 実際に送信されるタグ
- `#食事:朝食`
- `#食事:昼食`
- `#食事:夕食`
- `#食事:間食`
- `#運動:筋トレ`
- `#運動:有酸素`
- `#体重`

### 7.2 タグ入力時の挙動

| 入力内容 | 表示されるタグ候補 |
|---------|------------------|
| なし | 非表示 |
| `#` | `#食事` `#運動` `#体重` |
| `#食` | `#食事:朝食` `#食事:昼食` `#食事:夕食` `#食事:間食` |
| `#食事` | `#食事:朝食` `#食事:昼食` `#食事:夕食` `#食事:間食` |
| `#運` | `#運動:筋トレ` `#運動:有酸素` |
| `#体` | `#体重` |

### 7.3 Edge Function処理

#### タグ解析
```typescript
function parseTag(content: string): TagData | null {
  const tagPattern = /#(食事|運動|体重)(?::(.+?))?(?:\s|$)/;
  const match = content.match(tagPattern);
  
  if (!match) return null;
  
  return {
    category: match[1], // '食事' | '運動' | '体重'
    detail: match[2], // '朝食' | '筋トレ' など
    fullTag: match[0].trim(),
  };
}
```

#### 記録作成
```typescript
// メッセージ挿入時にWebhookでEdge Functionを起動
Deno.serve(async (req) => {
  const { record } = await req.json();
  const tagData = parseTag(record.content);
  
  if (!tagData) return;
  
  switch (tagData.category) {
    case '食事':
      await createMealRecord(record, tagData);
      break;
    case '運動':
      await createExerciseRecord(record, tagData);
      break;
    case '体重':
      await createWeightRecord(record, tagData);
      break;
  }
});
```

---

## 8. MVP範囲

### 8.1 実装する機能

#### ✅ 認証
- QRコード招待
- メール + マジックリンク認証
- セッション保持（6ヶ月）

#### ✅ メッセージ
- テキスト + 画像（最大3枚）
- タグ機能（階層構造）
- リアルタイム更新
- プッシュ通知
- リプライ機能
- 5分以内編集

#### ✅ 食事記録
- メッセージからのみ記録
- カレンダー表示（GitHub草スタイル）
- 記録一覧

#### ✅ 体重記録
- メッセージからのみ記録
- 統計カード
- グラフ表示
- 記録一覧

#### ✅ 運動記録
- メッセージからのみ記録
- タイプ別フィルタ
- カレンダー表示
- 記録一覧

#### ✅ 目標管理
- トレーナーが設定
- 体重目標のみ
- 達成率計算
- 目標達成時の演出

### 8.2 後回しの機能

#### ⏸️ 将来実装
- 栄養素情報（カロリー・タンパク質など）→ AI算出
- 生体認証（Face ID / Touch ID）
- 既読機能
- メッセージ検索
- データエクスポート
- 運動目標設定
- 複数目標対応（体脂肪率など）
- オフライン対応
- プロフィール編集
- 通知設定画面

---

## 9. 開発スケジュール（概算）

### フェーズ1: 基盤構築（2週間）
- プロジェクトセットアップ
- Supabase連携
- 認証フロー実装
- ボトムナビゲーション

### フェーズ2: メッセージ機能（2週間）
- メッセージ送受信
- 画像添付
- タグ入力補助UI
- リアルタイム更新

### フェーズ3: Edge Function & 記録作成（2週間）
- Edge Function実装
- タグ解析ロジック
- 各記録テーブルへの挿入
- リプライ機能

### フェーズ4: 記録画面（3週間）
- 食事記録画面
- 体重記録画面（グラフ含む）
- 運動記録画面
- カレンダーコンポーネント

### フェーズ5: 目標管理 & ホーム画面（1週間）
- 目標表示
- 達成率計算
- 本日のサマリー
- 目標達成演出

### フェーズ6: 通知 & 仕上げ（2週間）
- プッシュ通知（FCM）
- エラーハンドリング
- パフォーマンス最適化
- テスト

**合計: 約3ヶ月**

---

## 付録

### A. ワイヤーフレーム
別途HTMLファイル参照: `wireframes_updated.html`

### B. 用語集
- **タグ**: メッセージに付与するハッシュタグ（例: `#食事:昼食`）
- **記録**: 食事・体重・運動の記録データ
- **サマリー**: ホーム画面に表示される統計情報
- **MVP**: Minimum Viable Product（最小限の機能で動作する製品）

### C. 参考リンク
- Supabase公式ドキュメント: https://supabase.com/docs
- Flutter公式ドキュメント: https://flutter.dev/docs
- Riverpod公式ドキュメント: https://riverpod.dev/

---

**以上**
