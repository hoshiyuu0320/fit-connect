# CLAUDE.md — FIT-CONNECT Monorepo

このディレクトリは FIT-CONNECT プロジェクトのモノレポルートです。
2つの独立したGitリポジトリを含みます。

## プロジェクト構成

```
FIT-CONNECT/
├── fit-connect/              # Trainer Web App (Next.js 15)
│   ├── .git/                 # Git: hoshiyuu0320/fit-connect
│   ├── CLAUDE.md             # Web固有の設定・ルール
│   └── .claude/              # Web固有のagents・settings
│
├── fit-connect-mobile/       # Client Mobile App (Flutter)
│   ├── .git/                 # Git: hoshiyuu0320/fit-connect-mobile
│   ├── CLAUDE.md             # Mobile固有の設定・ルール
│   ├── .claude/              # Mobile固有のagents・settings
│   └── docs/
│
├── CLAUDE.md                 # ← このファイル（共通ルール）
└── .claude/                  # 統括用agents・settings
```

## 共通ルール

### Git

- **各プロジェクトは独立したGitリポジトリ**。コミット・プッシュは各ディレクトリ内で行う
- git push前にコミットを1つにまとめる（squash）。`git rebase -i` ではなく `git reset --soft` + 再コミットで実施
- `.env` ファイルは参照しないこと
- **新規機能追加・バグ修正時は必ず作業ブランチを作成**してから実装を開始すること
  - ブランチ命名規則: `feature/<機能名>` または `fix/<バグ内容>`
  - develop/mainブランチで直接作業しないこと

### Supabase（共通バックエンド）

両プロジェクトは**同じSupabaseプロジェクト**を共有している。

- DBスキーマの変更は**両プロジェクトへの影響を必ず確認**すること
- Web側の型定義: `fit-connect/src/types/`
- Mobile側のモデル: `fit-connect-mobile/lib/shared/models/`
- スキーマ変更時は**両方の型/モデルを更新**すること

### 実装タスク管理

- **ドキュメント・タスクリストは全て `docs/tasks/` 配下に配置する**
- 横断タスク（新機能）: `docs/tasks/IMPLEMENTATION_TASKS.md`
- Web固有: `fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md`
- Mobile固有: `fit-connect-mobile/docs/tasks/IMPLEMENTATION_TASKS.md`
- 実装の進捗は随時更新すること

## Technology Stack

| 項目      | Web (fit-connect)       | Mobile (fit-connect-mobile) |
| --------- | ----------------------- | --------------------------- |
| Framework | Next.js 15 (App Router) | Flutter                     |
| Language  | TypeScript              | Dart                        |
| State     | Zustand                 | Riverpod                    |
| UI        | Tailwind CSS + Radix UI | Material 3 + AppColors      |
| Backend   | Supabase (共有)         | Supabase (共有)             |
| Auth      | Supabase Auth           | Supabase Auth               |

## エージェント委託

### 統括エージェント（親 .claude/agents/）
| エージェント | 用途                                 |
| ------------ | ------------------------------------ |
| explore      | 両プロジェクト横断のコードベース調査 |
| plan         | プロジェクト横断の実装計画           |
| supabase     | 共有バックエンドの管理               |

### Web固有エージェント（fit-connect/.claude/agents/）
| エージェント | 用途               |
| ------------ | ------------------ |
| nextjs-ui    | Page/Component作成 |
| zustand      | Store作成・管理    |

### Mobile固有エージェント（fit-connect-mobile/.claude/agents/）
| エージェント | 用途               |
| ------------ | ------------------ |
| flutter-ui   | Widget/Screen作成  |
| riverpod     | Provider作成・管理 |

## Design Tokens — Web (fit-connect) 用

> **注意:** 以下のデザイントークンは **fit-connect（Trainer Web App）** 向けに策定されたものです。
> Mobile（fit-connect-mobile）には別途デザイン方針を定義してください。

- Concept: Modern, Sophisticated, Gender-neutral Fitness Management Tool
- Typography (JP): 'Noto Sans JP', sans-serif
- Border-radius: 6px（丸すぎない、尖りすぎないプロフェッショナルなカーブ）

### UI/UX Anti-Patterns — Web (fit-connect) 用
- AI特有の安っぽいグラデーション禁止
- 意味のない濃いドロップシャドウ禁止
- ボタンやカードの角を丸めすぎない（max 8px）
- 彩度が高すぎる原色はステータス以外で使用禁止
- 要素の詰め込みすぎ禁止、十分な余白を確保

## Role: Manager & Agent Orchestrator

**あなたはマネージャーであり、Agentオーケストレーターです。**

1. **実装は絶対に自分で行わない** — 全ての実装はSubagentに委託
2. **タスクの超細分化** — 1サブタスク = 1ファイル or 1機能
3. **プロジェクト横断の影響を常に意識** — 特にSupabaseスキーマ変更時

### UI実装時のデザインスキル運用

UIサブエージェント（`nextjs-ui` / `flutter-ui`）は `Skill` ツールを持たないため、
**マネージャーが `ui-ux-pro-max` スキルを先に実行し、結果をサブエージェントへのコンテキストとして渡す**こと。

```
ワークフロー:
1. マネージャーが ui-ux-pro-max スキルを実行（デザインシステム生成）
2. 得られたスタイル・カラー・タイポグラフィ等の指示を委託プロンプトに含める
3. UIサブエージェントはその指示に従って実装
```

### 実装後の自動QA

サブエージェントによるコード変更が完了したら、**必ず対応するQAスキルを実行**すること:

- **fit-connect（Web）のコード変更後** → `chrome-web-qa` スキルを実行（Chromeブラウザで動作確認）
- **fit-connect-mobile（Mobile）のコード変更後** → `ios-simulator-qa` スキルを実行（iOSシミュレータで動作確認）

ユーザーから「確認不要」「スキップして」と指示された場合を除き、実装完了報告前に必ずQAを通すこと。

### セッション継続

作業を再開するときは、まず以下を読むこと

- `docs/tasks/IMPLEMENTATION_TASKS.md` - 未着手タスクと進捗
- `docs/tasks/lessons.md` - 過去の失敗と学び

変更があった場合、上記を更新すること。
