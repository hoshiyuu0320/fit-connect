# 顧客管理機能 要件定義サマリー

## 📋 概要

FIT-CONNECTの顧客管理機能の要件定義が完了しました。
このドキュメントは、作成された全ドキュメントの概要と実装に向けた次のステップをまとめたものです。

**作成日**: 2025-11-02
**バージョン**: 1.0.0

---

## 📁 作成されたドキュメント一覧

### 1. 詳細要件定義書
**ファイル**: `docs/client-management-requirements.md`

**内容:**
- 機能概要
- 画面一覧
- データ項目定義（全7テーブル）
- 機能詳細（顧客リスト画面、顧客詳細画面）
- 権限・アクセス制御
- UI/UX要件
- 将来の拡張性

### 2. データベース設計書
**ファイル**: `docs/db-design.md`（更新）

**内容:**
- clientsテーブルの拡張（9カラム追加）
- weight_recordsテーブル（新規）
- meal_recordsテーブル（新規）
- exercise_recordsテーブル（新規）
- ticketsテーブル（新規）
- RLSポリシー定義
- インデックス設計

### 3. ER図
**ファイル**: `docs/er-design.md`（更新）

**内容:**
- Mermaid形式のER図
- 全テーブルのリレーション図
- カラム定義

### 4. マイグレーションSQL
**ファイル**: `docs/client-management-migration.sql`

**内容:**
- clientsテーブル拡張SQL
- 新規テーブル作成SQL
- CHECK制約、外部キー制約
- インデックス作成
- RLSポリシー設定
- コメント追加

### 5. 画面設計書
**ファイル**: `docs/client-management-ui-design.md`

**内容:**
- 画面遷移図
- 顧客リスト画面の詳細設計
- 顧客詳細画面の詳細設計
- 共通UIコンポーネント
- レスポンシブ対応
- アクセシビリティ対応

### 6. API設計書
**ファイル**: `docs/client-management-api-design.md`

**内容:**
- API概要・アーキテクチャ
- 認証・認可（RLS）
- データベースクエリ関数（7関数）
- TypeScript型定義
- エラーハンドリング
- パフォーマンス最適化
- セキュリティ考慮事項

---

## 🎯 主要機能

### 顧客リスト画面 (`/clients`)
- 顧客一覧表示（カード形式）
- 名前検索（リアルタイム）
- フィルタリング機能:
  - 性別（男性/女性/その他）
  - 年齢層（10代〜60代以上）
  - 目的（6種類）
- ソート機能（名前順がデフォルト）
- 詳細画面への遷移
- メッセージ画面への遷移

### 顧客詳細画面 (`/clients/[client_id]`)
- 基本情報セクション
  - プロフィール画像
  - 個人情報（名前、年齢、性別、職業、身長）
  - 目標体重・現在の体重
  - 目的、目標の詳細説明
- 体重推移グラフ
  - 折れ線グラフ
  - 目標体重の表示
  - 期間選択（将来実装）
- 食事記録セクション
  - タイムライン表示
  - カテゴリ別タブフィルター
  - 画像表示（最大10枚）
  - ページネーション（20件ずつ）
- 運動記録セクション
  - タイムライン表示
  - 運動種目アイコン
  - 時間/距離/カロリー表示
  - ページネーション（20件ずつ）
- チケット情報セクション
  - チケットカード表示
  - 残りセッション数
  - 有効期限
  - プログレスバー

---

## 🗄️ データベース設計

### テーブル構成

```
clients（拡張）
├── 既存カラム（5）+ 新規カラム（9）= 計14カラム
└── 新規カラム: gender, age, occupation, height, target_weight,
                purpose, goal_description, profile_image_url

weight_records（新規）
├── 4カラム
└── client_id → clients.client_id（外部キー）

meal_records（新規）
├── 7カラム
└── client_id → clients.client_id（外部キー）

exercise_records（新規）
├── 8カラム
└── client_id → clients.client_id（外部キー）

tickets（新規）
├── 9カラム
└── client_id → clients.client_id（外部キー）
```

### セキュリティ（RLS）
すべてのテーブルでRow Level Securityを有効化し、トレーナーは自分が担当するクライアントのデータのみアクセス可能。

---

## 🔧 技術スタック

### フロントエンド
- **React 19** - UIライブラリ
- **Next.js 15** - フレームワーク
- **Tailwind CSS** - スタイリング
- **Radix UI** - UIコンポーネント
- **Recharts / Chart.js** - グラフライブラリ（候補）
- **React Hook Form + Zod** - フォーム＆バリデーション

### バックエンド
- **Supabase** - データベース＆認証
- **Supabase Storage** - 画像保存
- **PostgreSQL** - データベース（Supabase提供）

### データアクセス
- **Supabaseクエリ関数**（推奨）
- **Next.js API Routes**（必要最小限）

---

## 📝 実装に必要なファイル一覧

### 新規作成ファイル

#### TypeScript型定義
```
src/types/client.ts
```

#### Supabaseクエリ関数
```
src/lib/supabase/
├── getClientDetail.ts
├── getWeightRecords.ts
├── getMealRecords.ts
├── getExerciseRecords.ts
├── getTickets.ts
├── searchClients.ts
└── updateClientGoal.ts（将来実装）
```

#### 画面コンポーネント
```
src/app/(user_console)/clients/
├── page.tsx                    # 顧客リスト画面
└── [client_id]/
    └── page.tsx                # 顧客詳細画面
```

#### UIコンポーネント
```
src/components/clients/
├── ClientCard.tsx              # 顧客カード
├── ClientFilters.tsx           # フィルター
├── ClientSearchBar.tsx         # 検索バー
├── ProfileAvatar.tsx           # プロフィールアバター
├── WeightChart.tsx             # 体重グラフ
├── MealRecordList.tsx          # 食事記録リスト
├── ExerciseRecordList.tsx      # 運動記録リスト
└── TicketCard.tsx              # チケットカード
```

#### API Routes（必要な場合）
```
src/app/api/clients/
└── [client_id]/
    └── goal/
        └── route.ts            # 目標更新API
```

---

## 🚀 実装ステップ

### Phase 1: データベースセットアップ
1. ✅ マイグレーションSQLの実行
   - `docs/client-management-migration.sql`を実行
   - テーブル作成とRLS設定
2. ✅ 既存データの更新（既存のclientsレコードがある場合）
   - デフォルト値で埋められた新カラムを適切な値に更新

### Phase 2: 型定義とクエリ関数
1. ✅ TypeScript型定義の作成
   - `src/types/client.ts`
2. ✅ Supabaseクエリ関数の実装
   - 7つのクエリ関数を作成
3. ✅ ユニットテスト（任意）

### Phase 3: UIコンポーネント実装
1. ✅ 共通コンポーネント
   - ProfileAvatar
   - ClientCard
   - ClientFilters
   - ClientSearchBar
2. ✅ グラフコンポーネント
   - WeightChart（グラフライブラリの選定）
3. ✅ 記録表示コンポーネント
   - MealRecordList
   - ExerciseRecordList
   - TicketCard

### Phase 4: 画面実装
1. ✅ 顧客リスト画面
   - `/clients`ページ
   - 検索・フィルタリング機能
   - ページネーション
2. ✅ 顧客詳細画面
   - `/clients/[client_id]`ページ
   - 全セクションの実装
   - データ取得とローディング状態

### Phase 5: 編集機能（将来実装）
1. ⏸ 目標編集機能
   - モーダルまたは別画面
   - API Route実装
2. ⏸ 画像アップロード機能
   - Supabase Storageとの連携

### Phase 6: テスト・最適化
1. ⏸ E2Eテスト（Playwright等）
2. ⏸ パフォーマンス最適化
   - React Queryによるキャッシング
   - 画像の遅延読み込み
3. ⏸ アクセシビリティチェック

---

## ⚠️ 実装時の注意事項

### 1. 既存データの扱い
現在のclientsテーブルにデータがある場合：
- 新しいカラムはデフォルト値で埋められます
- 実装前に既存データを適切な値に更新する必要があります
- 特に`gender`, `age`, `height`, `target_weight`, `purpose`は必須項目

### 2. LINE連携との関係
- 既存のLINE連携機能（line_user_id）は維持
- クライアント側アプリ実装時にLIFF経由で基本情報を登録する想定

### 3. 画像保存先
- Supabase Storageを使用
- バケット名: `client-profiles`, `meal-images`（要作成）
- RLSポリシーの設定が必要

### 4. パフォーマンス
- 食事記録・運動記録は必ずページネーション実装
- 画像は遅延読み込み（Lazy Loading）
- グラフデータはクライアント側でキャッシュ

### 5. セキュリティ
- すべてのデータアクセスはRLSで保護
- 画像アップロード時はファイルサイズ・拡張子チェック
- XSS対策（ユーザー入力のサニタイズ）

---

## 📊 見積もり

### 開発工数（概算）
- **Phase 1**: 1日（データベースセットアップ）
- **Phase 2**: 2日（型定義・クエリ関数）
- **Phase 3**: 3日（UIコンポーネント）
- **Phase 4**: 4日（画面実装）
- **Phase 5**: 2日（編集機能、将来実装）
- **Phase 6**: 2日（テスト・最適化）

**合計**: 約14日（実装のみ）

※編集機能とテスト・最適化を除いた最小構成: 約10日

---

## 🔄 将来の拡張案

### 短期（3ヶ月以内）
- 目標編集機能
- 期間選択付き体重グラフ
- 食事記録のカロリー自動算出（画像認識API連携）

### 中期（6ヶ月以内）
- クライアント側アプリの実装
- PDFエクスポート機能
- 高度な分析機能（予測グラフ、栄養バランス）

### 長期（1年以内）
- AI による食事・運動アドバイス
- ウェアラブルデバイス連携
- リアルタイム通知機能

---

## ✅ チェックリスト

実装開始前に以下を確認してください：

### 要件定義
- [x] 詳細要件定義書の作成
- [x] データベース設計の完了
- [x] 画面設計の完了
- [x] API設計の完了
- [ ] クライアントとの最終確認

### 環境準備
- [ ] Supabaseプロジェクトの確認
- [ ] マイグレーションSQLの実行
- [ ] Supabase Storageバケットの作成
- [ ] 環境変数の設定確認

### 開発準備
- [ ] グラフライブラリの選定
- [ ] コンポーネント命名規則の確認
- [ ] Git ブランチ戦略の確認
- [ ] タスク管理ツールへの登録

---

## 📞 次のステップ

### 1. 要件の最終確認
このドキュメントおよび関連ドキュメントを確認し、不明点や修正が必要な箇所がないか確認してください。

### 2. 実装開始の判断
要件に問題がなければ、Phase 1（データベースセットアップ）から実装を開始できます。

### 3. 質問・相談
実装中に疑問点や技術的な課題が発生した場合は、随時相談してください。

---

## 📚 参考リンク

- [Supabase Documentation](https://supabase.com/docs)
- [Next.js Documentation](https://nextjs.org/docs)
- [Tailwind CSS Documentation](https://tailwindcss.com/docs)
- [Recharts Documentation](https://recharts.org/en-US/)
- [Radix UI Documentation](https://www.radix-ui.com/docs/primitives/overview/introduction)

---

**作成者**: Claude Code
**作成日**: 2025-11-02
**最終更新日**: 2025-11-02
**バージョン**: 1.0.0
