# Monorepo Migration — Follow-ups & Decisions Log

移行実行中に発生した「あとで対応が必要なもの」「計画から逸脱した判断」を記録するファイル。
進行中に随時追記されます。

---

## 後で対応が必要なもの

### 0. ⚠️ 移行直後に発覚した問題（対応済み）

**症状**: `flutter run --release` で `No file or variants found for asset: assets/.env.` エラー。

**原因**: `git subtree add` は **コミット済みファイルのみ** を取り込むため、gitignore 対象だった以下のファイルが mobile から moonsrepo に持ち越されなかった:
- `fit-connect-mobile/assets/.env` — Supabase URL/Key、Google Web Client ID 入り（pubspec.yaml の assets で必須）
- `fit-connect-mobile/android/gradlew`、`gradlew.bat`
- `fit-connect-mobile/android/gradle/wrapper/gradle-wrapper.jar`

**対応**: `FIT-CONNECT-BACKUP-2026-04-26/fit-connect-mobile/` から手動コピーで復元（gitignore 対象なので git status には現れない）。

**教訓**: 今後 subtree や fresh clone で開発環境を立ち上げるときは、上記4ファイルを別経路で配布する仕組み（README に記載 / 1Password 等）を整えること。
特に `.env` はチーム間で共有が必要だが gitignore のため手動配布が必要。


### 1. Supabase `config.toml` の `project_id` 統一 ✅ 解決済み

- 旧mobile側の `project_id = "fit-connect-mobile"` を `"fit-connect"` に統一（Supabase CLI 参照時に自動書き換えされたものをそのまま採用）
- リモート Supabase プロジェクトには影響なし

### 2. `pre-monorepo-migration: WIP on feature/weight-prediction` stash の処理

- Task 0.1 で stash した内容が残っている（`stash@{0}`）
- 含まれるファイル:
  - `M .serena/project.yml`（旧Web側 → 現 `fit-connect/.serena/project.yml`）
  - `M docs/tasks/IMPLEMENTATION_TASKS.md`（旧Web側 → 現 `fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md`）
  - `?? docs/superpowers/plans/2026-03-21-weight-period-stats.md`（既にマージ済み機能の plan）
  - `?? docs/superpowers/plans/2026-03-22-weight-prediction.md`（既にマージ済み機能の plan）
  - `?? docs/superpowers/specs/2026-03-22-weight-prediction-design.md`（既にマージ済み機能の spec）
- 判断: 全てモノレポ化前のパス前提。発掘して移植するか、廃棄するか
- 推奨: ファイル移動後のパスは `fit-connect/docs/superpowers/...` のはず。手動で内容を確認し、必要なら新パスにコピー、不要なら `git stash drop`
- コマンド例:
  ```bash
  cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
  git stash show -p stash@{0}  # 内容確認
  # 必要なら適用、不要なら drop
  git stash drop stash@{0}
  ```

### 3. ランタイム/キャッシュ系ファイルを .gitignore に追加

- Task 4 で `.superpowers/brainstorm/*/.server.pid`, `.server-stopped`, 一部のHTML成果物がコミットされた
- Task 7 で `.claude/skills/ui-ux-pro-max/scripts/__pycache__/*.pyc` がコミットされた
- これらは Python バイトコードキャッシュや brainstorm のランタイム状態で、本来 git管理不要
- 対応: ルート `.gitignore` に以下を追記し、コミット済みのものは `git rm --cached -r`
  ```
  # Python bytecode cache
  __pycache__/
  *.pyc

  # Superpowers brainstorm runtime
  .superpowers/brainstorm/*/.server.pid
  .superpowers/brainstorm/*/.server-stopped
  .superpowers/brainstorm/*/*.html
  ```

### 4. Web側 supabase/ ダンプ破棄の記録

- 旧 `fit-connect/supabase/migrations/20251227090908_remote_schema.sql`（Dec 27 のスキーマダンプ）は **削除**
- 理由: mobile 側 `20251230131753_remote_schema.sql` (Dec 30) のほうが新しく、その後 28 本の差分が積み上がっている。古い完全スキーマダンプを再投入すると整合性を壊す
- 履歴は git log で追える（Task 6 のコミット参照）

### 5. CLAUDE.md / .claude の冗長定義削除（Task 7）

- 親レベル CLAUDE.md / .claude を採用済み
- `fit-connect/CLAUDE.md` および `fit-connect-mobile/CLAUDE.md` には親と重複する内容（共通ルール、Supabase運用ルール等）が残存
- 親と重複する部分を削除し、Web/Mobile 固有のみに整理する必要あり

### 6. `migrations_backup` / `migrations_old` の取り扱い

- 採用した mobile 側 supabase/ には以下が含まれる:
  - `migrations_backup/` — 過去のスキーマバックアップ
  - `migrations_old/` — さらに古いマイグレーション
  - `rollback_migrate_profiles_to_trainers.sql` — 単発のロールバック SQL
- いずれも歴史的な参照用。残すか削除するか判断。残す場合 `.gitignore` で参照しないことを明示すると安全

### 7. fit-connect-mobile/supabase/ の重複保持

- subtree で取り込んだ `fit-connect-mobile/supabase/` 配下も `fit-connect-mobile/` 配下に存在（subtree のスナップショットそのもの）
- ルート `supabase/` を真実の所在とした以上、`fit-connect-mobile/supabase/` は **削除** 予定（Task 6 内で対応）

### 8. fit-connect-mobile の subtree 履歴に対する将来の同期方針

- 旧 mobile リポジトリは Task 12 で archive 化される予定
- それ以降、mobile 側の更新は monorepo 内で直接行うため、subtree pull の必要はない
- ただし archive 化前にもしリモート mobile に追加 push する場合は、`git subtree pull --prefix=fit-connect-mobile <remote> <branch>` で取り込み可能

---

## ユーザー対応が必要な手順（実行中に該当ステップで案内する）

| Step | 内容 | 担当 |
|---|---|---|
| Task 9.1 | Vercel preview deploy を一時抑止（任意） | ユーザー |
| Task 10.1 | Vercel Settings → General → Root Directory を `/` → `fit-connect` に変更 | ユーザー |
| Task 11.2 | GitHub Settings → Branches → main の Branch protection を一時解除 | ユーザー |
| Task 11.4 | force push 実行直前の最終確認 | ユーザー（Claude が実行直前に確認を要求） |
| Task 11.5 | Branch protection を元に戻す | ユーザー |
| Task 11.6 | Vercel 本番デプロイの動作確認 | ユーザー |
| Task 12.1 | 旧 fit-connect-mobile リポジトリの README に移動先を明記 | ユーザー |
| Task 12.3 | GitHub Settings → Archive this repository | ユーザー |

---

## 移行完了後の運用変更点

### Vercel 本番デプロイの仕組み

- **Production Branch**: `main`（変更なし）
- **Root Directory**: `/` → `fit-connect`（Task 10.1 で変更）
- 本番更新フロー: `main` への push → Vercel が `fit-connect/` を Next.js プロジェクトとしてビルド・デプロイ

### Git 運用

- 移行後はモノレポの `main` 一本運用
- `develop` は廃止（Task 13.4）
- 旧 mobile リポジトリは archive、すべての mobile 開発は monorepo の `fit-connect-mobile/` 配下で行う

---

最終更新: 2026-04-26 (移行実行中、随時追記)
