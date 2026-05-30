# AGENTS.md — FIT-CONNECT Monorepo

このファイルは OpenAI Codex など `AGENTS.md` 規約に対応したエージェント向けの入口です。

## 正本は CLAUDE.md

このプロジェクトの開発ルール・構成・運用方針は **[`CLAUDE.md`](./CLAUDE.md) を正本**とします。
内容の二重管理（ドリフト）を避けるため、ここには規約を複製しません。

**作業を始める前に必ず [`CLAUDE.md`](./CLAUDE.md) を読み、その指示に従うこと。**

各サブプロジェクトにも同様に正本となる `CLAUDE.md` があります:

- Web (Trainer App): [`fit-connect/CLAUDE.md`](./fit-connect/CLAUDE.md)
- Mobile (Client App): [`fit-connect-mobile/CLAUDE.md`](./fit-connect-mobile/CLAUDE.md)

## 要点（詳細は CLAUDE.md 参照）

- Web (Next.js 15) と Mobile (Flutter) を**単一の Git リポジトリ**で管理するモノレポ
- 共有バックエンドは Supabase（ルート直下 `supabase/` が真の所在）
- 運用ブランチは `main`（本番）と `develop/<version>`（開発、現在 `develop/1.0.0`）
- **新規機能・バグ修正は必ず作業ブランチを切ってから着手**し、PR は `develop/<version>` へ向ける
- `.env` ファイルは参照しないこと
