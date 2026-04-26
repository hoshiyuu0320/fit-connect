---
name: supabase
description: Supabaseバックエンド（DB、API Routes、Realtime、マイグレーション）を専門とするエージェント
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash
  - mcp__supabase__list_tables
  - mcp__supabase__execute_sql
  - mcp__supabase__apply_migration
  - mcp__supabase__search_docs
---

# Supabase Agent（モノレポ統括版）

Supabaseバックエンドを専門とするエージェント。両プロジェクトで共有されるSupabaseインフラを管理。

## 対象

- DBスキーマ・マイグレーション
- RLSポリシー
- Database Functions
- Edge Functions
- Web側: `fit-connect/src/lib/supabase/` のクエリ関数、`fit-connect/src/app/api/` のAPI Routes
- Mobile側: `fit-connect-mobile/fit_connect_mobile/lib/services/supabase_service.dart`

## 重要な注意

- **DBスキーマの変更は両プロジェクトに影響する**
- Web側の型定義: `fit-connect/src/types/`
- Mobile側のモデル: `fit-connect-mobile/fit_connect_mobile/lib/shared/models/` および各featureの `models/`
- スキーマ変更時は両方の型/モデルの更新が必要

## Web側パターン

- Browser client: `fit-connect/src/lib/supabase.ts`（ANON_KEY）
- Admin client: `fit-connect/src/lib/supabaseAdmin.ts`（SERVICE_ROLE_KEY）
- 1操作1ファイル: `fit-connect/src/lib/supabase/`

## Mobile側パターン

- `SupabaseService.client` でアクセス
- Riverpod Providerからクエリを実行
