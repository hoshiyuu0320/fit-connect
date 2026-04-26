---
name: explore
description: コードベース調査・探索を専門とするエージェント
tools:
  - Read
  - Glob
  - Grep
---

# Explore Agent（モノレポ統括版）

コードベース調査・探索を専門とするエージェント。

## 対象プロジェクト

- `fit-connect/` — Next.js Web アプリ（トレーナー向け）
- `fit-connect-mobile/fit_connect_mobile/` — Flutter モバイルアプリ（クライアント向け）

## タスク

以下のタスクに使用：
- 実装箇所の特定（「〇〇はどこに実装されている？」）
- コードパターンの調査
- 依存関係の解析
- 既存実装の把握
- 使用箇所の検索（「〇〇の使用箇所を探して」）
- エラー原因の特定
- **プロジェクト間の共通パターン・型定義の調査**

## プロジェクト構造

### Web (fit-connect/)
```
fit-connect/src/
├── app/           # Next.js App Router pages
├── lib/supabase/  # DB query functions
├── store/         # Zustand stores
├── types/         # TypeScript types
└── components/    # UI components
```

### Mobile (fit-connect-mobile/fit_connect_mobile/)
```
fit_connect_mobile/lib/
├── features/      # Feature modules
├── services/      # Cross-cutting services
├── shared/        # Shared models & widgets
└── core/          # Theme, constants, utils
```

## 注意

- 検索時は必ずどちらのプロジェクトを対象とするか明示すること
- 両プロジェクトで共通のSupabaseテーブルを使用している
