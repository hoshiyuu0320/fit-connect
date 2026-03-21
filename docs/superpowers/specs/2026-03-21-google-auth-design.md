# Google認証機能 設計書

**作成日**: 2026-03-21
**ステータス**: 承認済み

---

## 概要

FIT-CONNECTにGoogle OAuth認証を追加し、Googleアカウントのみで新規登録・ログインを可能にする。

## 要件

- Googleアカウントでログイン・サインアップ両方に対応
- 新規登録時はGoogleの表示名を自動取得（後から設定画面で変更可能）
- 既存のメール/パスワード認証はそのまま維持
- ログイン・サインアップ両ページのGoogleボタンは既存UIを使用（変更なし）

## 認証フロー

### 新規ユーザー（Google）

```
Googleボタン → Google OAuth画面 → /auth/callback
  → supabase.auth.exchangeCodeForSession(code)
  → supabaseAdmin で trainers テーブルを確認（user.id で検索）
  → レコードなし → INSERT { id: user.id, name: user_metadata.full_name, email: user.email }
  → /dashboard?welcome=true へリダイレクト
  → ダッシュボードでトースト表示:
    「Googleアカウントの名前で登録しました。設定画面から変更できます」
```

### 既存ユーザー（Google）

```
Googleボタン → Google OAuth画面 → /auth/callback
  → セッション交換
  → trainers テーブルにレコードあり → スキップ
  → /dashboard へリダイレクト
```

### 既存フロー（メール/パスワード）

変更なし。

## 変更対象ファイル

### 1. `/src/app/auth/callback/route.ts`（主要変更）

コード交換後にトレーナーレコードの存在確認・自動作成ロジックを追加。

- `supabaseAdmin` を使用（RLSバイパス、既存パターン踏襲）
- `user_metadata.full_name` が空の場合、メールアドレスの `@` 前をフォールバック名に使用
- 新規作成時は `/dashboard?welcome=true` にリダイレクト
- 既存ユーザーは `/dashboard` にリダイレクト

### 2. `/src/app/(user_console)/dashboard/page.tsx`（トースト追加）

- URLパラメータ `welcome=true` を検知
- トースト通知で「Googleアカウントの名前で登録しました。設定画面から変更できます」を表示
- 表示後にURLからパラメータを除去（`router.replace`）

### 3. UIボタン（変更なし）

ログイン・サインアップページのGoogleボタンは既に配置済み。変更不要。

## 事前設定手順（手動）

### Google Cloud Console

1. Google Cloud Console (https://console.cloud.google.com) でプロジェクトを作成（または既存を使用）
2. 「APIとサービス」→「OAuth同意画面」を設定
   - ユーザータイプ: 外部
   - アプリ名、サポートメール等を入力
3. 「認証情報」→「認証情報を作成」→「OAuth 2.0 クライアントID」
   - アプリケーションの種類: ウェブアプリケーション
   - 承認済みリダイレクトURI: `https://<supabase-project-ref>.supabase.co/auth/v1/callback`
4. Client ID と Client Secret を控える

### Supabase Dashboard

1. Authentication → Providers → Google を有効化
2. 取得した Client ID と Client Secret を入力
3. 保存

## 技術的考慮事項

- `supabaseAdmin`（サービスロールキー）はサーバーサイドのみで使用
- トレーナーレコード作成はコールバック（サーバーサイド）で行うため、RLSの影響を受けない
- 既存のメール/パスワードサインアップフローの`/api/trainers/create`ルートはそのまま維持
