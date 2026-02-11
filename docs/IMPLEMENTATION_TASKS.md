# FIT-CONNECT Web - 実装タスク一覧

**作成日**: 2026年2月1日
**バージョン**: 1.0
**進捗状況**: 全体 70% 完了
**最終更新**: 2026年2月11日 - メッセージ画像添付・表示機能実装

---

## 目次

1. [実装状況サマリー](#実装状況サマリー)
2. [最新の変更履歴](#最新の変更履歴)
3. [フェーズ別タスク一覧](#フェーズ別タスク一覧)
4. [メッセージ機能](#メッセージ機能)
5. [クライアント管理](#クライアント管理)
6. [スケジュール管理](#スケジュール管理)
7. [レポート・分析](#レポート分析)
8. [設定機能](#設定機能)
9. [インフラ・設定](#インフラ設定)
10. [今後のタスク](#今後のタスク)

---

## 実装状況サマリー

### 完了率

| カテゴリ | 進捗 | 状態 |
|---------|------|------|
| **認証（ログイン/サインアップ）** | 100% | 🟢 完了 |
| **ダッシュボード** | 100% | 🟢 完了 |
| **クライアント一覧・検索** | 100% | 🟢 完了 |
| **クライアント詳細表示** | 90% | 🟡 グラフ未実装 |
| **メッセージ基本機能** | 80% | 🟡 編集・返信未実装、画像添付✅ |
| **スケジュール管理** | 100% | 🟢 完了 |
| **レポート機能** | 0% | 🔴 未着手 |
| **ワークアウトプラン** | 0% | 🔴 未着手 |
| **設定画面** | 0% | 🔴 未着手 |
| **クライアント招待（QR）** | 0% | 🔴 未着手 |

### 完了済み項目

- ✅ プロジェクト構造・アーキテクチャ設計
- ✅ Next.js 15 App Router セットアップ
- ✅ Supabase連携（Browser/Admin デュアルクライアント）
- ✅ Tailwind CSS + Radix UIコンポーネント
- ✅ Zustand状態管理（localStorage永続化）
- ✅ 認証フロー（ログイン/サインアップ）
- ✅ ダッシュボード（KPI、アラート、メッセージプレビュー、本日の予定）
- ✅ クライアント一覧・検索・フィルター
- ✅ クライアント詳細（基本情報、体重・食事・運動記録、チケット）
- ✅ メッセージ基本機能（送受信、リアルタイム更新）
- ✅ スケジュール管理（カレンダービュー、セッションCRUD）
- ✅ サイドバーレイアウト（ホバー展開）
- ✅ データベース操作関数（24ファイル）

### 未実装項目

- ✅ メッセージ画像添付・表示
- 🚧 メッセージ編集（5分以内）
- 🚧 メッセージ返信（リプライ）
- 🚧 体重グラフ表示（fl_chart相当）
- 🚧 クライアント編集機能
- 🚧 チケット管理画面
- 🚧 クライアントQRコード招待
- 🚧 プッシュ通知
- 🚧 レポート機能
- 🚧 ワークアウトプラン
- 🚧 設定画面

---

## 最新の変更履歴

### 2026年2月11日

- メッセージ画像添付・表示機能を実装（フェーズ2.1完了）
  - `ImageUploader.tsx` - ドラッグ&ドロップ対応の画像添付コンポーネント
  - `ImageModal.tsx` - 画像拡大表示モーダル
  - `uploadMessageImage.ts` - Supabase Storageアップロード関数
  - API Route更新（`image_urls`対応）
  - メッセージページUI更新（添付・表示・Realtime対応）
  - `Message`型を`src/types/client.ts`に追加

### 2026年2月1日

- 初版作成
- 要件定義書（REQUIREMENTS.md）作成
- 実装タスク一覧（本ファイル）作成

---

## フェーズ別タスク一覧

### 📌 フェーズ1: 基盤構築 ✅ 完了

**目的**: プロジェクトの基盤を整備

| タスク | 状態 | 詳細 |
|--------|------|------|
| Next.js 15セットアップ | ✅ | App Router、TypeScript |
| Supabase連携 | ✅ | Browser/Adminクライアント |
| 認証フロー | ✅ | ログイン/サインアップ |
| レイアウト構築 | ✅ | サイドバー、ルートグループ |
| UIコンポーネント | ✅ | Radix UI、Tailwind CSS |

---

### 📌 フェーズ2: メッセージ機能強化 🟡 進行中

**目的**: クライアントアプリと同等のメッセージ機能を実現

#### 2.1 画像添付・表示機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.1.1 | 画像アップロードコンポーネント作成 | ✅ | `ImageUploader.tsx` - ドラッグ&ドロップ対応 |
| 2.1.2 | Supabase Storageバケット確認 | ✅ | `message-photos`バケット、RLSポリシー |
| 2.1.3 | 画像アップロード関数作成 | ✅ | `src/lib/supabase/uploadMessageImage.ts` |
| 2.1.4 | メッセージ入力欄に添付ボタン追加 | ✅ | 最大3枚まで、プレビュー表示 |
| 2.1.5 | メッセージバブルに画像表示 | ✅ | サムネイル、クリックで拡大モーダル |
| 2.1.6 | API Route更新 | ✅ | `/api/messages/send` - `image_urls`対応 |

**実装詳細**:

```typescript
// src/lib/supabase/uploadMessageImage.ts
export async function uploadMessageImage(
  file: File,
  trainerId: string,
  messageId: string
): Promise<string> {
  const path = `${trainerId}/${messageId}/${file.name}`;
  const { data, error } = await supabaseAdmin.storage
    .from('message-photos')
    .upload(path, file);

  if (error) throw error;

  const { data: { publicUrl } } = supabaseAdmin.storage
    .from('message-photos')
    .getPublicUrl(path);

  return publicUrl;
}
```

```typescript
// ImageUploader.tsx の仕様
interface ImageUploaderProps {
  images: File[];
  onImagesChange: (images: File[]) => void;
  maxImages?: number; // デフォルト: 3
  disabled?: boolean;
}
```

#### 2.2 メッセージ編集機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.2.1 | 編集ボタンUI追加 | 🔴 | メッセージホバー時に表示（自分のメッセージのみ） |
| 2.2.2 | 編集可能判定関数作成 | 🔴 | `canEditMessage()` - 5分以内チェック |
| 2.2.3 | 編集モーダル/インライン編集UI | 🔴 | 編集入力欄、キャンセル/保存ボタン |
| 2.2.4 | 編集API作成 | 🔴 | `/api/messages/edit` または関数 |
| 2.2.5 | 編集済みバッジ表示 | 🔴 | 「(編集済み)」ラベル、編集日時ツールチップ |
| 2.2.6 | Realtime対応 | 🔴 | UPDATE イベント購読 |

**実装詳細**:

```typescript
// src/lib/supabase/editMessage.ts
export async function editMessage(
  messageId: string,
  newContent: string
): Promise<void> {
  const now = new Date();

  // 5分以内チェック
  const { data: message } = await supabase
    .from('messages')
    .select('created_at')
    .eq('id', messageId)
    .single();

  const createdAt = new Date(message.created_at);
  const diffMinutes = (now.getTime() - createdAt.getTime()) / 1000 / 60;

  if (diffMinutes > 5) {
    throw new Error('編集可能な時間（5分）を過ぎました');
  }

  await supabase
    .from('messages')
    .update({
      content: newContent,
      edited_at: now.toISOString(),
      is_edited: true,
      updated_at: now.toISOString(),
    })
    .eq('id', messageId);
}
```

#### 2.3 メッセージ返信（リプライ）機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 2.3.1 | 返信ボタンUI追加 | 🔴 | メッセージホバー時に表示 |
| 2.3.2 | 返信プレビューコンポーネント | 🔴 | `ReplyPreview.tsx` - 入力欄上部に表示 |
| 2.3.3 | 返信引用コンポーネント | 🔴 | `ReplyQuote.tsx` - バブル内に表示 |
| 2.3.4 | 返信先メッセージ取得 | 🔴 | `getMessageById()` 関数 |
| 2.3.5 | 送信時にreply_to_message_id保存 | 🔴 | API Route更新 |
| 2.3.6 | メッセージ一覧で返信情報表示 | 🔴 | `reply_to_message_id`がある場合に引用表示 |

**実装詳細**:

```typescript
// ReplyPreview.tsx
interface ReplyPreviewProps {
  replyToContent: string;
  replyToSenderName: string;
  onCancel: () => void;
}

// ReplyQuote.tsx
interface ReplyQuoteProps {
  senderName: string;
  content: string;
  isTrainerMessage: boolean;
}
```

```
表示イメージ:
┌─────────────────────────────────────┐
│ [クライアントメッセージ]             │
│ #食事:昼食 サラダチキン食べました     │
│ 12:30                               │
│                                     │
│ ┌─────────────────────────────────┐ │ ← リプライ
│ │ トレーナー                       │ │
│ │ ┌─ 返信元 ─────────────────────┐│ │
│ │ │ サラダチキン食べました         ││ │
│ │ └───────────────────────────────┘│ │
│ │ タンパク質しっかり取れてますね！ │ │
│ │ 13:15                           │ │
│ └─────────────────────────────────┘ │
└─────────────────────────────────────┘
```

---

### 📌 フェーズ3: クライアント管理強化 🔴 未着手

**目的**: クライアント情報の編集・可視化機能を追加

#### 3.1 体重グラフ表示

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.1.1 | グラフライブラリ選定・導入 | 🔴 | recharts または chart.js |
| 3.1.2 | WeightChart コンポーネント作成 | 🔴 | 折れ線グラフ、目標体重点線 |
| 3.1.3 | 期間フィルター追加 | 🔴 | 今週/今月/3ヶ月/全期間 |
| 3.1.4 | データポイントホバー詳細 | 🔴 | ツールチップで日付・体重表示 |
| 3.1.5 | クライアント詳細ページに統合 | 🔴 | `/clients/[client_id]` |

**実装詳細**:

```typescript
// src/components/clients/WeightChart.tsx
interface WeightChartProps {
  weightRecords: WeightRecord[];
  targetWeight: number;
  initialWeight?: number;
  period: 'week' | 'month' | '3months' | 'all';
}
```

#### 3.2 クライアント編集機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.2.1 | 編集モーダルコンポーネント作成 | 🔴 | `ClientEditModal.tsx` |
| 3.2.2 | フォームバリデーション | 🔴 | React Hook Form + Zod |
| 3.2.3 | 更新API作成 | 🔴 | `src/lib/supabase/updateClient.ts` |
| 3.2.4 | 目標設定フォーム | 🔴 | 開始時体重、目標体重、期日、説明 |
| 3.2.5 | プロフィール画像アップロード | 🔴 | Supabase Storage連携 |

**編集可能項目**:
- 名前
- 年齢
- 性別
- 身長
- 目標体重
- 開始時体重
- 目的
- 目標説明
- 目標期日
- プロフィール画像

#### 3.3 クライアントQRコード招待

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.3.1 | QRコード生成ライブラリ導入 | 🔴 | qrcode.react |
| 3.3.2 | 招待モーダル作成 | 🔴 | `ClientInviteModal.tsx` |
| 3.3.3 | 招待URL生成ロジック | 🔴 | `trainer_id`をエンコード |
| 3.3.4 | QRコード表示コンポーネント | 🔴 | ダウンロード機能付き |
| 3.3.5 | 招待リンクコピー機能 | 🔴 | クリップボードにコピー |

**実装詳細**:

```typescript
// 招待URLフォーマット
const inviteUrl = `fitconnect://invite?trainer_id=${trainerId}`;

// QRコード生成
import QRCode from 'qrcode.react';

<QRCode
  value={inviteUrl}
  size={256}
  level="H"
/>
```

#### 3.4 チケット管理画面

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 3.4.1 | チケット一覧画面作成 | 🔴 | `/clients/[client_id]/tickets` |
| 3.4.2 | チケット作成モーダル | 🔴 | `TicketCreateModal.tsx` |
| 3.4.3 | チケット編集機能 | 🔴 | 残回数、有効期限の更新 |
| 3.4.4 | チケット作成API | 🔴 | `src/lib/supabase/createTicket.ts` |
| 3.4.5 | セッション紐付けUI改善 | 🔴 | セッション作成時のチケット選択 |

---

### 📌 フェーズ4: レポート・分析機能 🔴 未着手

**目的**: クライアントの進捗を可視化・レポート化

#### 4.1 レポート画面基盤

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.1.1 | レポート画面レイアウト作成 | 🔴 | `/report` プレースホルダー置き換え |
| 4.1.2 | クライアント選択UI | 🔴 | ドロップダウンまたはサイドバー |
| 4.1.3 | 期間選択UI | 🔴 | 日付範囲ピッカー |

#### 4.2 統計・グラフ

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.2.1 | 体重推移グラフ（再利用） | 🔴 | WeightChartコンポーネント流用 |
| 4.2.2 | 食事記録統計 | 🔴 | 記録頻度、食事区分別カウント |
| 4.2.3 | 運動記録統計 | 🔴 | 種目別カウント、総時間 |
| 4.2.4 | 目標達成率推移 | 🔴 | 週次/月次の達成率グラフ |

#### 4.3 エクスポート機能

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 4.3.1 | CSVエクスポート | 🔴 | 体重/食事/運動記録 |
| 4.3.2 | PDFレポート生成 | 🔴 | サマリーレポート |

---

### 📌 フェーズ5: ワークアウトプラン 🔴 未着手

**目的**: トレーニングメニューの作成・管理

#### 5.1 プラン管理

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 5.1.1 | ワークアウトプラン画面作成 | 🔴 | `/workoutplan` プレースホルダー置き換え |
| 5.1.2 | プランテンプレート作成 | 🔴 | 種目、セット数、回数、メモ |
| 5.1.3 | クライアントへのプラン割り当て | 🔴 | プラン選択・適用 |
| 5.1.4 | データベーステーブル設計 | 🔴 | `workout_plans`, `workout_exercises` |

---

### 📌 フェーズ6: 設定機能 🔴 未着手

**目的**: トレーナーのプロフィール・アプリ設定

#### 6.1 設定画面

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 6.1.1 | 設定画面レイアウト作成 | 🔴 | `/settings` プレースホルダー置き換え |
| 6.1.2 | プロフィール編集 | 🔴 | 名前、メール、プロフィール画像 |
| 6.1.3 | パスワード変更 | 🔴 | Supabase Auth連携 |
| 6.1.4 | 通知設定 | 🔴 | メール通知オン/オフ |
| 6.1.5 | ログアウト機能 | 🔴 | 確認ダイアログ付き |

---

### 📌 フェーズ7: プッシュ通知 🔴 未着手

**目的**: クライアントからのメッセージ通知

| # | タスク | 状態 | 詳細 |
|---|--------|------|------|
| 7.1 | Web Push通知設定 | 🔴 | Service Worker、VAPID キー |
| 7.2 | 通知許可フロー | 🔴 | ブラウザ許可ダイアログ |
| 7.3 | Edge Function連携 | 🔴 | メッセージ受信時に通知送信 |
| 7.4 | 通知クリック時のナビゲーション | 🔴 | メッセージ画面へ遷移 |

---

## 優先度別タスク一覧

### 🔴 最優先（次に取り組むべき）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 1 | **メッセージ画像表示** | クライアントからの画像を表示 | 中 |
| 2 | **メッセージ画像添付** | トレーナーからの画像送信 | 中 |
| 3 | **メッセージ編集** | 5分以内の編集機能 | 小 |
| 4 | **メッセージ返信** | リプライ機能 | 中 |

### 🟡 高優先（MVP後すぐ）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 5 | **体重グラフ表示** | recharts導入、折れ線グラフ | 中 |
| 6 | **クライアント編集** | 基本情報・目標の編集 | 中 |
| 7 | **クライアントQRコード招待** | QRコード生成・表示 | 小 |
| 8 | **チケット管理** | 作成・編集機能 | 中 |

### 🟢 中優先（アップデート）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 9 | **設定画面** | プロフィール編集、ログアウト | 中 |
| 10 | **レポート基盤** | 統計画面、クライアント選択 | 大 |
| 11 | **エクスポート機能** | CSV/PDF出力 | 中 |

### ⚪ 低優先（将来実装）

| # | タスク | 詳細 | 見積もり |
|---|--------|------|----------|
| 12 | **ワークアウトプラン** | プラン作成・割り当て | 大 |
| 13 | **プッシュ通知** | Web Push実装 | 大 |
| 14 | **ダークモード** | テーマ切り替え | 中 |

---

## 技術的負債・改善項目

### コード品質

- [ ] TypeScript strict mode 有効化
- [ ] ESLint ルール強化
- [ ] コンポーネントの共通化整理

### パフォーマンス

- [ ] `messages`テーブルのインデックス追加
- [ ] 画像の遅延読み込み
- [ ] バンドルサイズ最適化

### テスト

- [ ] ユニットテスト作成
- [ ] E2Eテスト作成（Playwright）
- [ ] APIテスト作成

### ドキュメント

- [ ] API仕様書作成
- [ ] コンポーネントカタログ作成（Storybook検討）
- [ ] デプロイ手順書作成

---

## ファイル構成（計画）

### 追加予定ファイル

```
src/
├── app/
│   ├── api/
│   │   └── messages/
│   │       └── edit/
│   │           └── route.ts          # メッセージ編集API
│   └── (user_console)/
│       ├── clients/
│       │   └── [client_id]/
│       │       └── tickets/
│       │           └── page.tsx      # チケット管理画面
│       ├── report/
│       │   └── page.tsx              # レポート画面（本実装）
│       ├── workoutplan/
│       │   └── page.tsx              # ワークアウト画面（本実装）
│       └── settings/
│           └── page.tsx              # 設定画面（本実装）
├── components/
│   ├── clients/
│   │   ├── ClientEditModal.tsx       # クライアント編集モーダル
│   │   ├── ClientInviteModal.tsx     # QRコード招待モーダル
│   │   ├── WeightChart.tsx           # 体重グラフ
│   │   └── TicketCreateModal.tsx     # チケット作成モーダル
│   ├── messages/
│   │   ├── ImageUploader.tsx         # 画像アップローダー
│   │   ├── ReplyPreview.tsx          # 返信プレビュー
│   │   ├── ReplyQuote.tsx            # 返信引用
│   │   └── ImageGallery.tsx          # 画像ギャラリー
│   └── settings/
│       └── ProfileEditForm.tsx       # プロフィール編集フォーム
├── lib/
│   └── supabase/
│       ├── uploadMessageImage.ts     # 画像アップロード
│       ├── editMessage.ts            # メッセージ編集
│       ├── getMessageById.ts         # メッセージ取得
│       ├── updateClient.ts           # クライアント更新
│       └── createTicket.ts           # チケット作成
└── types/
    └── client.ts                     # 型定義更新
```

---

## 参考リンク

- [Next.js公式ドキュメント](https://nextjs.org/docs)
- [Supabase公式ドキュメント](https://supabase.com/docs)
- [Radix UI公式ドキュメント](https://www.radix-ui.com/docs)
- [Tailwind CSS公式ドキュメント](https://tailwindcss.com/docs)
- [recharts公式ドキュメント](https://recharts.org/)
- [React Hook Form公式ドキュメント](https://react-hook-form.com/)

---

## 関連ドキュメント

- [REQUIREMENTS.md](../REQUIREMENTS.md) - 要件定義書
- [CLAUDE.md](../CLAUDE.md) - 開発ガイドライン
- [ROADMAP.md](../ROADMAP.md) - 開発ロードマップ

---

**最終更新**: 2026年2月11日 - メッセージ画像添付・表示機能実装（v1.1）
