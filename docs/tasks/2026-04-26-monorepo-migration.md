# Monorepo Migration Plan (案B: fit-connect リポジトリへ subtree 統合)

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. **DO NOT execute destructive operations (force push, repo rename, archive) without explicit user confirmation per step.**

**Goal:** `hoshiyuu0320/fit-connect` リポジトリを土台に `fit-connect-mobile` を `git subtree` で統合し、`/Users/hoshidayuuya/Documents/FIT-CONNECT/` 全体を1つのGitリポジトリ（モノレポ）にする。Vercelデプロイ・既存履歴・未マージ feature ブランチを保護する。

**Architecture:**
- 既存の `fit-connect` リポジトリの **ルート構造を再編成** し、現Web側ファイルを `fit-connect/` サブディレクトリへ退避
- `fit-connect-mobile` リポジトリの main ブランチを `git subtree add --prefix=fit-connect-mobile` で取り込む（履歴保持）
- Supabase 設定は mobile側（migrations 29本）を真実の所在として、ルート直下 `supabase/` に統合
- CLAUDE.md / .claude は親レベルのものを正として一本化、子ディレクトリの定義は撤廃

**Tech Stack:** Git (subtree), GitHub, Vercel, Supabase CLI, pnpm/Flutter

---

## 重要な前提と制約

### 既知のリスク
1. **多数の未マージ feature ブランチ**: fit-connect 側に40+本、mobile側に20+本ある。マイグレーション後はブランチ上のファイルパスが変わるため、**マージ前にmainへ取り込むか、放棄する判断が必須**。
2. **Vercel設定変更**: Root Directory を `/` → `fit-connect` に変更必要。preview デプロイで先に検証する。
3. **Supabase migrations の不一致**: fit-connect側は1本のみ。mobile側を採用するが、念のためdiffを確認。
4. **未コミット変更**: 両プロジェクトに WIP あり（事前処理必須）。
5. **mobile側 main は廃ブランチ**: PR #21〜#32の全機能が `develop/1.0.0` にしか存在せず、main は初期セットアップ時点で停止。**subtree取り込み元は `develop/1.0.0`** とする（main をマージして整える試みは禁止：移行と別問題が混ざる）。
6. **Web側 main も実質空**: `main` HEAD は Initial commit のみ（122コミット遅れ）。全機能が `develop` にあり、Vercel本番は Mar 14 の develop スナップショットで凍結中。Vercel Production Branch は `main` 設定だが main には何も push されていないため本番更新が止まっている。**移行と同時にこの歪みを解消する**。

### ブランチ採用方針（採用案X：main を develop で上書きする）

| プロジェクト | 作業ブランチ起点 | 最終マージ先 | 旧ブランチの扱い |
|---|---|---|---|
| fit-connect (Web) | `develop` | `main`（develop の内容で上書き） | 移行後 `develop` は休止/削除 |
| fit-connect-mobile | `develop/1.0.0` | （subtree 取り込みのみ） | リポジトリごと archive |

**移行戦略の意図:**
- 移行を機に Web の main/develop の歪みを解消
- 移行後は monorepo の `main` 一本運用に戻す
- Vercel Production Branch は `main` のまま変更不要 → main への push で本番デプロイが復活
- 既存 main の Initial commit は事実上破棄（失うものはない）

### 移行前の合意事項（ユーザー確認済み）
- ✅ 案X採用（main を develop で上書き）
- ✅ Web 作業起点: `develop` / Mobile subtree 元: `develop/1.0.0`
- ✅ Vercel Production Branch は main のまま
- ✅ 移行後は monorepo の main 一本運用、develop は休止/削除
- ✅ mobile WIP (`feature/sleep-data-integration`) は **破棄**（PR #32 でマージ済み、ローカル追加コミットなし、WIP は `ios/build/` のみで gitignore 対象）
- ✅ 両プロジェクトの未マージ feature ブランチは **全て破棄**（残存するのは実験/学習/ボット生成のみ）
- ✅ リポジトリ名: `hoshiyuu0320/fit-connect` の **まま据え置き**（rename しない）
- ✅ subtree 履歴は **フル保持**（`--squash` を使わない）

### 破棄対象の Web 側残存ブランチ（参考）

調査時点で develop にない独自コミットを持つ Web 側ブランチ:

| ブランチ | 独自コミット | 判断 |
|---|---|---|
| `feature/dashboard` | 「一旦コミット、ダッシュボード画面作成」 | 破棄（旧実験、`feature/add-dashboard` で置換済み） |
| `feature/workout-plan-before` | 「ワークアウトプラン機能の作成」 | 破棄（"before" suffix が示す通り旧版） |
| `learning-nextjs` | 「一旦こみっと」×2 | 破棄（学習用） |
| `origin/claude/daily-ai-news-digest-Al6pp` | AI ボット生成 | 破棄（未採用） |

> mobile 側は調査時点で develop/1.0.0 にない独自コミットを持つブランチは **0件**。

---

## File Structure (移行後)

```
FIT-CONNECT/                              # ← Git ルート (hoshiyuu0320/fit-connect リポジトリ)
├── .git/                                 # 単一の .git
├── .claude/                              # 統括用（既存の親 .claude/ を残す）
├── .gitignore                            # モノレポ統合版
├── CLAUDE.md                             # 既存の親 CLAUDE.md を正とする
├── README.md                             # 新規作成（モノレポ説明）
├── docs/
│   └── tasks/
│       ├── IMPLEMENTATION_TASKS.md
│       └── lessons.md
├── supabase/                             # ★ ルート直下に集約（mobile側を採用）
│   ├── config.toml
│   ├── migrations/                       # 29本 (mobile側ベース)
│   ├── functions/
│   └── Seed.sql
├── fit-connect/                          # Web (Next.js) — 旧ルートから移動
│   ├── src/
│   ├── public/
│   ├── package.json
│   ├── next.config.ts
│   ├── tailwind.config.ts
│   └── ...                               # 旧 fit-connect ルート直下のファイル全て
└── fit-connect-mobile/                   # Mobile (Flutter) — subtree 取り込み
    ├── lib/
    ├── pubspec.yaml
    ├── ios/
    ├── android/
    └── ...
```

**削除されるもの:**
- `fit-connect/.claude/`, `fit-connect/CLAUDE.md` （親レベルへ統合）
- `fit-connect-mobile/.claude/`, `fit-connect-mobile/CLAUDE.md` （親レベルへ統合）
- `fit-connect/supabase/` （ルート `supabase/` へ移動）
- `fit-connect-mobile/supabase/` （subtree 取り込み後にルートへマージ）
- `fit-connect-mobile/.git/` （subtree 統合により不要）

---

## Task 0: Pre-flight チェック & バックアップ

**Files:** バックアップディレクトリのみ

- [ ] **Step 0.1: 両プロジェクトの未コミット変更を整理（合意事項どおり破棄）**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
git status
# 未コミット例: .serena/project.yml, docs/tasks/IMPLEMENTATION_TASKS.md, docs/superpowers/plans/*
# → 必要なものは事前にコミット、不要なものは破棄/stash

# 必要に応じて
# git stash push -m "pre-monorepo-migration backup"
# または既存ファイルへ戻す
# git checkout -- .serena/project.yml

cd ../fit-connect-mobile
git status
# 未コミット: ios/build/ のみ（ビルド成果物、gitignore で除外すべき）
# 移行後の .gitignore で fit-connect-mobile/ios/build/ を除外するため、ローカルでは無視 or 削除
```

期待: 両リポジトリで `git status` が clean、または無害な untracked のみ。

> **mobile WIP の最終確認:** `feature/sleep-data-integration` は PR #32 でマージ済みで、ローカルに追加コミットなし。安心して破棄可。

- [ ] **Step 0.2: 完全バックアップ（作業前）**

```bash
cd /Users/hoshidayuuya/Documents
mkdir -p FIT-CONNECT-BACKUP-2026-04-26
cp -R FIT-CONNECT/fit-connect FIT-CONNECT-BACKUP-2026-04-26/
cp -R FIT-CONNECT/fit-connect-mobile FIT-CONNECT-BACKUP-2026-04-26/
# サイズ確認
du -sh FIT-CONNECT-BACKUP-2026-04-26/*
```

期待: 両プロジェクトの完全コピーが別フォルダに保存される。**この時点でmigration中断しても元に戻せる状態。**

- [ ] **Step 0.3: 両リモートの最新を取得**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
git fetch --all --prune
# ⚠️ Web 側も main は Initial commit のみ。作業起点は develop。
git checkout develop
git pull origin develop

cd ../fit-connect-mobile
git fetch --all --prune
# ⚠️ mobile は default branch が develop/1.0.0。main は古いブランチなので checkout しない。
git checkout develop/1.0.0
git pull origin develop/1.0.0
```

期待: fit-connect は develop、fit-connect-mobile は develop/1.0.0 がリモートと同期。

- [ ] **Step 0.3b: 採用ブランチが正しいか最終確認**

```bash
# Web 側
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
echo "Web develop only: $(git log --oneline origin/main..origin/develop | wc -l)"  # 期待: 100+件
echo "Web main only: $(git log --oneline origin/develop..origin/main | wc -l)"     # 期待: 0件

# Mobile 側
cd ../fit-connect-mobile
echo "Mobile develop only: $(git log --oneline origin/main..origin/develop/1.0.0 | wc -l)"  # 期待: 30+件
echo "Mobile main only: $(git log --oneline origin/develop/1.0.0..origin/main | wc -l)"     # 期待: 0件
```

期待: 両プロジェクトで develop が真実の所在であることが定量確認できる。

- [ ] **Step 0.4: GitHub上の feature ブランチ一覧をアーカイブ用にエクスポート**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
git branch -r | grep -v HEAD > /tmp/fit-connect-branches.txt
cd ../fit-connect-mobile
git branch -r | grep -v HEAD > /tmp/fit-connect-mobile-branches.txt
cat /tmp/fit-connect-branches.txt
cat /tmp/fit-connect-mobile-branches.txt

# 永続保存用にバックアップ先へコピー
cp /tmp/fit-connect-branches.txt /Users/hoshidayuuya/Documents/FIT-CONNECT-BACKUP-2026-04-26/
cp /tmp/fit-connect-mobile-branches.txt /Users/hoshidayuuya/Documents/FIT-CONNECT-BACKUP-2026-04-26/
```

期待: 移行後すべての feature ブランチを破棄するため、後日「どのブランチが存在したか」を参照できるリストをバックアップに保管。

> **合意事項:** 残存ブランチは全て破棄方針。本ステップはあくまで履歴記録目的。

---

## Task 1: 作業ブランチ作成

**Files:** branch state only

- [ ] **Step 1.1: fit-connect 側に統合作業ブランチを作成（develop から切る）**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
git checkout develop
git pull origin develop
git checkout -b feature/monorepo-migration
git status
```

期待: `develop` ベースの `feature/monorepo-migration` ブランチに切り替わり、tree clean。

> **重要:** main から切らない。main は Initial commit のみのため、ベースにすると develop の122コミットが失われる。

- [ ] **Step 1.2: ローカルテストタグを打つ（戻り先用）**

```bash
# develop の現在地に戻れるタグ
git tag pre-monorepo-migration

# 万一 main を破壊した場合の戻り先として、現 main のタグも打っておく
git tag pre-monorepo-migration-main-original origin/main
git tag
```

期待: `pre-monorepo-migration`（=develop の現在地）と `pre-monorepo-migration-main-original`（=旧 main の Initial commit）の2つのタグが存在。問題発生時に両方の状態へ戻れる。

---

## Task 2: fit-connect リポジトリ内ファイルを `fit-connect/` サブディレクトリへ移動

**Files:** fit-connect リポジトリ内の全ファイル（`.git/` 除く）

> **重要:** `git mv` を使うことで Git は rename として認識し、blame履歴が壊れない。

- [ ] **Step 2.1: 移動対象ディレクトリを作成**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
mkdir fit-connect
ls -la
```

期待: 既存ファイル群と並んで空の `fit-connect/` ディレクトリができる。

- [ ] **Step 2.2: ルート直下の全ファイル・ディレクトリを `fit-connect/` へ移動**

注意: `.git`, 新規作成した `fit-connect/`, 親レベルへ昇格するもの (`docs/`, `supabase/`) は除外。

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect

# 移動対象（Web側に閉じるもの）
for item in src public package.json package-lock.json pnpm-lock.yaml pnpm-workspace.yaml \
            next.config.ts next-env.d.ts tsconfig.json tsconfig.tsbuildinfo \
            tailwind.config.js tailwind.config.ts postcss.config.js postcss.config.mjs \
            eslint.config.mjs components.json \
            README.md REQUIREMENTS.md ROADMAP.md \
            scripts sequence wireframes \
            CLAUDE.md .claude .cursor .superpowers \
            node_modules .next .vercel .env.local .env \
            .gitignore .eslintrc \
            ; do
  if [ -e "$item" ]; then
    git mv "$item" "fit-connect/$item" 2>/dev/null || mv "$item" "fit-connect/$item"
  fi
done

# 念のため確認
ls -la
ls fit-connect/
```

期待: ルート直下に `.git/`, `fit-connect/`, （`docs/`, `supabase/` は次タスク） のみ残る。

> **注意:** `.gitignore` に該当する `node_modules/` などは `git mv` ではなく単純 `mv` でOK。`.env` 系も同様。

- [ ] **Step 2.3: docs/ を親レベルへ移動（既に親に同名あるためマージ）**

```bash
# fit-connect/docs/ を一時退避してマージ判断
ls docs/
ls /Users/hoshidayuuya/Documents/FIT-CONNECT/docs/  # 親 docs (既存)
```

判断:
- 親 `docs/tasks/IMPLEMENTATION_TASKS.md` と `fit-connect/docs/tasks/IMPLEMENTATION_TASKS.md` を **手動マージ**（内容を統合）
- `fit-connect/docs/superpowers/plans/*.md` は親 `docs/superpowers/plans/` へ移動

```bash
# 親 docs に既に統合タスク管理がある場合: fit-connect/docs はそのまま残し、Web固有タスクとして扱う
# ただしファイルシステム上は親docsに集約推奨

# fit-connect/docs を fit-connect 内に残す（Web固有docsとして）
git mv docs fit-connect/docs
```

期待: `docs/` は親レベルにのみ存在（既存）。Web固有ドキュメントは `fit-connect/docs/` 配下に残る。

- [ ] **Step 2.4: supabase/ を親レベルへ移動（仮）**

```bash
# fit-connect/supabase/ は migrations 1本のみ。一旦 fit-connect 配下へ退避
git mv supabase fit-connect/supabase
ls fit-connect/supabase/migrations/
```

期待: ルートに `supabase/` がない状態。後で mobile側 supabase/ をルートに採用する。

- [ ] **Step 2.5: 移動後のコミット**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
git status
git add -A
git commit -m "chore(monorepo): move web app contents into fit-connect/ subdirectory"
```

期待: 1コミットで全ファイル移動。`git log --follow fit-connect/src/...` で履歴追跡可能。

- [ ] **Step 2.6: ローカルでビルド検証**

```bash
cd fit-connect
pnpm install
pnpm build
# 失敗するならパス参照の修正が必要
```

期待: `pnpm build` が成功する。失敗時はパス問題（tsconfig paths など）を修正してから次へ。

---

## Task 3: 親ディレクトリのリネーム & .git の昇格

**Files:** ファイルシステム再編

> **重要:** ここで「fit-connect リポジトリのルート位置を、親 FIT-CONNECT/ 階層に持ち上げる」操作を行う。

- [ ] **Step 3.1: 親 FIT-CONNECT/ を一時退避**

```bash
cd /Users/hoshidayuuya/Documents
mv FIT-CONNECT FIT-CONNECT-OLD
```

期待: 旧 FIT-CONNECT が一時的に FIT-CONNECT-OLD として残る。

- [ ] **Step 3.2: fit-connect リポジトリ全体を新 FIT-CONNECT/ として復元**

```bash
cd /Users/hoshidayuuya/Documents
mv FIT-CONNECT-OLD/fit-connect FIT-CONNECT
ls FIT-CONNECT/
# fit-connect/ サブディレクトリと .git/ が見える
```

期待: 新 `FIT-CONNECT/` の直下が「fit-connect リポジトリのルート」になる。`.git/` が新 FIT-CONNECT 直下に存在。

- [ ] **Step 3.3: 親 FIT-CONNECT-OLD/ から残りを救出**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT-OLD
ls
# 残: .claude/, .cursor/, .DS_Store, .superpowers/, CLAUDE.md, docs/, fit-connect-mobile/

cd /Users/hoshidayuuya/Documents/FIT-CONNECT
# 親レベルの統合資産を取り込む
mv ../FIT-CONNECT-OLD/.claude .claude-parent  # 一旦 -parent suffix（既存 fit-connect/.claude と衝突回避）
mv ../FIT-CONNECT-OLD/CLAUDE.md CLAUDE-parent.md
mv ../FIT-CONNECT-OLD/docs docs-parent
mv ../FIT-CONNECT-OLD/.cursor . 2>/dev/null
mv ../FIT-CONNECT-OLD/.superpowers . 2>/dev/null
ls -la
```

期待: 新 `FIT-CONNECT/` 直下に旧親レベルの資産が `*-parent` suffix付きで存在（後でマージ）。

- [ ] **Step 3.4: fit-connect-mobile を一時退避**

```bash
cd /Users/hoshidayuuya/Documents
mv FIT-CONNECT-OLD/fit-connect-mobile fit-connect-mobile-temp
ls FIT-CONNECT-OLD/  # ほぼ空に近いはず（.DS_Store のみ）
rmdir FIT-CONNECT-OLD || rm -rf FIT-CONNECT-OLD/.DS_Store && rmdir FIT-CONNECT-OLD
```

期待: `FIT-CONNECT-OLD` が削除され、mobile プロジェクトは隣の `fit-connect-mobile-temp/` にある。次タスクで subtree 経由で取り込む。

---

## Task 4: 親レベル CLAUDE.md と .claude/ の統合

**Files:**
- Modify: `CLAUDE.md` (親レベルを正とする)
- Modify: `.claude/` (親レベルを正とする)

- [ ] **Step 4.1: CLAUDE.md を統合**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
# 親 CLAUDE.md を正として採用
mv CLAUDE-parent.md CLAUDE.md  # 旧 fit-connect/CLAUDE.md は既に fit-connect/ 内にある
diff CLAUDE.md fit-connect/CLAUDE.md  # 差分確認
```

判断: 既存親 `CLAUDE.md` を正として採用。`fit-connect/CLAUDE.md` のWeb固有内容（デザイントークン等）はそのまま fit-connect/ 配下で保持し、親 CLAUDE.md からは削除。

- [ ] **Step 4.2: .claude/ を統合**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
ls .claude-parent/  # 親
ls fit-connect/.claude/  # Web固有

# 親 .claude/ を正として採用
mv .claude-parent .claude
# fit-connect/.claude/ は Web固有として残す（CLAUDE.md ルートに従う）
```

期待: ルート `.claude/` は統括用、`fit-connect/.claude/` は Web固有 agents を保持、`fit-connect-mobile/.claude/` も後で同様に。

- [ ] **Step 4.3: docs/ を統合**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
mv docs-parent docs
ls docs/  # tasks/IMPLEMENTATION_TASKS.md, lessons.md, この plan ファイル
```

期待: ルート `docs/tasks/` に既存タスク管理が存在。

- [ ] **Step 4.4: ルートに .gitignore を整備**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
cat > .gitignore <<'EOF'
# OS
.DS_Store

# IDE
.vscode/
.idea/

# Logs
*.log

# Env
.env
.env.local
.env.*.local

# Dependencies (web)
node_modules/

# Build outputs (web)
fit-connect/.next/
fit-connect/out/
fit-connect/build/

# Build outputs (mobile/flutter)
fit-connect-mobile/build/
fit-connect-mobile/.dart_tool/
fit-connect-mobile/.flutter-plugins
fit-connect-mobile/.flutter-plugins-dependencies
fit-connect-mobile/ios/Pods/
fit-connect-mobile/ios/build/
fit-connect-mobile/android/.gradle/
fit-connect-mobile/android/build/
fit-connect-mobile/android/app/build/

# Supabase
supabase/.branches/
supabase/.temp/
EOF

git add -A
git status
git commit -m "chore(monorepo): consolidate parent CLAUDE.md and .claude at root"
```

期待: モノレポ全体をカバーする `.gitignore` ができ、コミットされる。

---

## Task 5: fit-connect-mobile を subtree で取り込み

**Files:**
- Create: `fit-connect-mobile/` (subtree 経由)

- [ ] **Step 5.1: subtree add 実行**

> **取り込み元ブランチ: `develop/1.0.0`**（main ではない）
> 理由: mobile の main は PR #21〜#32 の全機能が未統合の廃ブランチ状態。GitHub default branch かつ事実上の main である `develop/1.0.0` を真実の所在として採用する。

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
# 一時退避していた mobile を消す（subtree が新規取り込みするため）
rm -rf /Users/hoshidayuuya/Documents/fit-connect-mobile-temp

# リモートから直接 subtree で取り込む（履歴保持）
git remote add mobile-origin git@github.com:hoshiyuu0320/fit-connect-mobile.git
git fetch mobile-origin

# develop/1.0.0 を取り込む（main ではない点に注意）
git subtree add --prefix=fit-connect-mobile mobile-origin develop/1.0.0

ls fit-connect-mobile/
git log --oneline | head -10
```

期待: `fit-connect-mobile/` が出現、mobile側 develop/1.0.0 の全履歴が現リポジトリに統合される（commit数が大幅増加）。

> **合意事項どおり `--squash` は使わずフル履歴保持。** これにより `git log fit-connect-mobile/lib/...` で個別コミットを追える、`git blame` も機能する。リポジトリ容量はやや増えるが運用上の利点が大きい。

> **取り込み後の確認:** mobile の最新コミット（PR #32 sleep-data-integration: `c4ac997`）が monorepo の履歴に含まれていることを確認。
> ```bash
> git log --oneline fit-connect-mobile/ | grep c4ac997
> ```

- [ ] **Step 5.2: mobile-origin リモートを削除（不要になったため）**

```bash
git remote remove mobile-origin
git remote -v
```

期待: `origin` (fit-connect.git) のみ残る。

- [ ] **Step 5.3: 取り込み確認**

```bash
ls fit-connect-mobile/lib/
cat fit-connect-mobile/pubspec.yaml | head -10
git log --oneline fit-connect-mobile/ | head -5
```

期待: mobile プロジェクトが正常に存在し、Flutter プロジェクト構造が見える。

---

## Task 6: Supabase の統合（mobile側を真実の所在として）

**Files:**
- Move: `fit-connect-mobile/supabase/` → `supabase/` (root)
- Delete: `fit-connect/supabase/` (旧Web側、1ファイルのみ)

> **重要:** mobile側 supabase migrations が29本、Web側は1本のみ。mobile側を採用するが、Web側1本が mobile側に **存在するかどうか** 必ず確認。

- [ ] **Step 6.1: 両 supabase/ ディレクトリの差分確認**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
diff -r fit-connect/supabase/migrations fit-connect-mobile/supabase/migrations
ls fit-connect/supabase/migrations/  # 1本だけ: 20251227090908_remote_schema.sql
ls fit-connect-mobile/supabase/migrations/ | head -5
```

判断:
- mobile側にWeb側の `20251227090908_remote_schema.sql` が含まれているか確認
- 含まれていなければ統合時にコピー必要
- `config.toml` の差分も確認

- [ ] **Step 6.2: mobile 側 supabase/ をルートへ昇格**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
git mv fit-connect-mobile/supabase supabase
ls supabase/migrations/ | wc -l  # 29 のはず
```

期待: ルート `supabase/` に29本の migrations が存在。`fit-connect-mobile/supabase/` は消える。

- [ ] **Step 6.3: Web側 supabase/ の差分マージ**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
ls fit-connect/supabase/migrations/

# Web側の migration が mobile 側に既に存在するか確認
ls supabase/migrations/ | grep 20251227090908 || echo "NOT FOUND - 要マージ"
```

判断:
- 存在する → Web側 supabase/ を削除
- 存在しない → Web側 migration を `supabase/migrations/` にコピー

```bash
# 存在する場合（多くのケース）
git rm -r fit-connect/supabase
```

- [ ] **Step 6.4: コミット**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
git status
git commit -m "chore(monorepo): consolidate supabase config at repository root"
```

期待: ルート `supabase/` のみ存在。両プロジェクト配下の supabase/ は消える。

- [ ] **Step 6.5: Supabase CLI 接続確認**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/supabase
# config.toml の project_id 等を確認
cat config.toml | grep project_id

# Supabase CLI で local 起動テスト（任意）
# supabase start
# supabase db diff
```

期待: ルート `supabase/` でCLI操作が成立する。

---

## Task 7: 子の CLAUDE.md / .claude を再整備

**Files:**
- Modify: `fit-connect/CLAUDE.md` (Web固有のみに削減)
- Modify: `fit-connect-mobile/CLAUDE.md` (Mobile固有のみに削減)

- [ ] **Step 7.1: fit-connect/CLAUDE.md をWeb固有に絞る**

ルート CLAUDE.md と重複する内容（Supabase共通ルール、Git共通ルール等）を削除し、Web固有のみ（デザイントークン、Web専用エージェント説明）を残す。

```bash
# 手動編集が必要
$EDITOR fit-connect/CLAUDE.md
```

- [ ] **Step 7.2: fit-connect-mobile/CLAUDE.md を Mobile 固有に絞る**

```bash
$EDITOR fit-connect-mobile/CLAUDE.md
```

- [ ] **Step 7.3: 子 .claude/ から重複 agents/skills を削除**

```bash
# 親 .claude/agents/ にあるもの (explore, plan, supabase) は子から削除
ls .claude/agents/
ls fit-connect/.claude/agents/      # 残: nextjs-ui, zustand のみ
ls fit-connect-mobile/.claude/agents/  # 残: flutter-ui, riverpod のみ
```

- [ ] **Step 7.4: コミット**

```bash
git add -A
git commit -m "chore(monorepo): scope child CLAUDE.md and .claude to project-specific concerns"
```

---

## Task 8: ローカル動作確認

**Files:** なし（検証のみ）

- [ ] **Step 8.1: Web ビルド検証**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
pnpm install
pnpm build
pnpm dev   # localhost:3000 で起動確認
# 確認したら Ctrl+C
```

期待: Next.js が正常にビルド・起動する。

- [ ] **Step 8.2: Mobile ビルド検証**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile
flutter clean
flutter pub get
flutter analyze
# iOS シミュレータで起動 (任意)
# flutter run -d <simulator-id>
```

期待: Flutter analyze が通る。

- [ ] **Step 8.3: Supabase 接続確認**

両プロジェクトから ルート `supabase/` 設定への参照を確認:
- Web: `.env.local` の `NEXT_PUBLIC_SUPABASE_URL` 等
- Mobile: `lib/shared/config/supabase_config.dart` 等

```bash
# 接続テスト（任意）
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect
pnpm dev
# 別ターミナル
cd /Users/hoshidayuuya/Documents/FIT-CONNECT/fit-connect-mobile
flutter run
```

期待: 両方が同じSupabaseに接続して動作する。

---

## Task 9: リモートへのプッシュ（preview検証）

**Files:** リモートブランチ

> **⚠️ Vercel が origin/feature/monorepo-migration を preview deploy する可能性に注意。Vercel の Root Directory を変更してから push する方が安全。**

- [ ] **Step 9.1: Vercel 側で preview deploy を一時無効化（任意）**

Vercel ダッシュボード → Project → Settings → Git → "Ignored Build Step" に以下を設定:

```bash
# feature/monorepo-migration ブランチの自動デプロイを抑止
if [ "$VERCEL_GIT_COMMIT_REF" == "feature/monorepo-migration" ]; then exit 0; else exit 1; fi
```

または Pre-Production deploy を無効化。

- [ ] **Step 9.2: ブランチをリモートへ push**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
git push -u origin feature/monorepo-migration
```

期待: GitHub に新ブランチが pushされる。Vercel が自動 deploy しないことを確認。

---

## Task 10: Vercel 設定変更 & preview デプロイ検証

**Files:** Vercel Dashboard 設定（コード変更なし）

> **⚠️ Vercel 設定変更は本番デプロイに直接影響する。preview ブランチで検証してから main に merge する。**

- [ ] **Step 10.1: Vercel ダッシュボードで Root Directory を変更**

[Vercel Dashboard](https://vercel.com/) → fit-connect プロジェクト → Settings → General

- **Root Directory**: `/` → `fit-connect`
- **Build Command**: 必要なら `pnpm build` （プロジェクトに依存）
- **Output Directory**: デフォルト `.next` のまま
- **Install Command**: `pnpm install`
- "Save" を押す

- [ ] **Step 10.2: feature/monorepo-migration ブランチの preview deploy を手動トリガー**

Vercel ダッシュボード → Deployments → "Redeploy" or git push で再トリガー
（Step 9.1 で抑止していた場合は解除）

- [ ] **Step 10.3: preview URL で動作確認**

```
https://fit-connect-git-feature-monorepo-migration-<account>.vercel.app/
```

確認項目:
- [ ] ログインページが表示される
- [ ] Supabase認証が機能する
- [ ] 主要ページがレンダリングされる
- [ ] 静的アセット（画像・フォント）が読み込まれる
- [ ] API ルート (`/api/*`) が動作する

期待: 本番と同等の動作が preview で確認できる。

- [ ] **Step 10.4: 環境変数の再確認**

Vercel ダッシュボード → Settings → Environment Variables で、Web側に必要な変数（`NEXT_PUBLIC_SUPABASE_URL` 等）が引き継がれていることを確認。

---

## Task 11: main を feature/monorepo-migration で上書き & 本番デプロイ

**Files:** main ブランチ（**force push が発生**）

> **🚨 ここから不可逆。前ステップまで全てOKの確信が持ててから実行。**
> **🚨 案X 特有: main の Initial commit を捨て、feature/monorepo-migration の内容で上書きする。これは破壊的操作。**

### 案X の main 上書き戦略

通常の merge では「Initial commit のみの main」と「develop ベースの大量コミット」を merge することになり、履歴が grafted で気持ち悪い状態になる。
**案X では main の Git 履歴を feature/monorepo-migration の履歴で完全に置き換える** ことで、移行後 main = 真実の所在 という綺麗な状態を作る。

- [ ] **Step 11.1: 事前確認**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
# 移行ブランチが期待通りか
git log --oneline -5
# main をどう上書きするか dry-run 的に確認
git log --oneline origin/main..feature/monorepo-migration | wc -l  # 122 + 移行コミット数
git log --oneline feature/monorepo-migration..origin/main | wc -l  # 1 (Initial commit) — これを破棄する
```

期待: main 側に「feature/monorepo-migration に含まれない commit が Initial commit のみ」であることを定量確認。それ以外があれば中断して調査。

- [ ] **Step 11.2: GitHub 上の main ブランチ保護を一時的に解除**

GitHub Repository → Settings → Branches → main の Branch protection rules:
- "Require pull request" を一時 OFF（or admin override 有効化）
- "Allow force pushes" を一時的に許可

> **注意: 設定変更後、Step 11.4 で必ず元に戻すこと。**

- [ ] **Step 11.3: ローカルで main を feature/monorepo-migration で上書き**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
git checkout main
# main を feature/monorepo-migration の HEAD に強制リセット
git reset --hard feature/monorepo-migration
git log --oneline -5
# 期待: 最新コミットが feature/monorepo-migration の HEAD と一致
```

期待: ローカル main が feature/monorepo-migration と完全一致。Initial commit (`cb6c869`) は履歴から消える。

- [ ] **Step 11.4: リモート main へ force push**

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT
# 安全のため lease 付きで push
git push --force-with-lease origin main
```

期待: GitHub 上の main が新しい状態（develop 内容 + モノレポ構造）に更新される。Vercel が自動で Production Deploy をトリガー。

> **`--force-with-lease` を使う理由:** 単純な `--force` と違い、リモート main が想定外に更新されていた場合は push が拒否される。万一誰かが main に push していた場合の保険。

- [ ] **Step 11.5: Branch protection を元に戻す**

GitHub Repository → Settings → Branches → main の Branch protection rules を Step 11.2 以前の状態に復元。

- [ ] **Step 11.6: Vercel 本番デプロイ確認**

Vercel Dashboard → Deployments で main の新 deploy が動くことを確認:
- Production URL (`fit-connect-xi.vercel.app`) にアクセス
- Mar 14 凍結状態から、最新 develop 相当（PR #41 weight-prediction まで）に切り替わっていること
- 主要機能の動作確認（ログイン、ダッシュボード、Google認証 等）

期待: 約6週間ぶりに本番が更新され、最新 develop の機能が反映される。

- [ ] **Step 11.7: 失敗時のロールバック手順**

優先度順:

1. **Vercel ロールバック（最優先）**: Vercel Dashboard → Deployments → 旧 develop ベースの Mar 14 deploy を "Promote to Production"。即時に旧本番状態に戻る。
2. **Git ロールバック**: main を旧 Initial commit に戻す
   ```bash
   git checkout main
   git reset --hard pre-monorepo-migration-main-original
   git push --force-with-lease origin main
   ```
3. **完全復旧**: バックアップから両プロジェクトを復元 → 旧 fit-connect-mobile リポジトリも未 archive のため新規 push 可能

> **重要: Vercel ロールバックを最優先。Git の force push は最後の手段。**

---

## Task 12: Mobile 旧リポジトリのアーカイブ

**Files:** GitHub Repository 設定

- [ ] **Step 12.1: 旧リポジトリの README に移動先を明記**

`hoshiyuu0320/fit-connect-mobile` の README を編集:

```markdown
# ⚠️ This repository has been archived

This project has been migrated into the monorepo at:
**https://github.com/hoshiyuu0320/fit-connect**

Located at: `fit-connect-mobile/`

All future development happens there. This repository is preserved for historical reference only.
```

- [ ] **Step 12.2: 未マージ feature ブランチを判断**

旧 fit-connect-mobile のリモート feature ブランチで継続したいものをユーザーが選定:
- 継続不要 → そのまま archive
- 継続したい → 各ブランチを cherry-pick or 手動移行（ファイルパスが `fit-connect-mobile/` になっている前提で再実装）

> **注意: 旧 mobile の `main` ブランチは PR #21〜#32 が未統合の廃ブランチ。** archive 前にこれを誤って参照しないよう、README に「`develop/1.0.0` が default branch だった」旨を明記しておくこと（履歴を遡る人へのヒント）。

- [ ] **Step 12.3: GitHub で archive 化**

GitHub Repository → Settings → "Archive this repository"

期待: read-only 状態になり、以後 push できなくなる。

---

## Task 13: 残務整理

- [ ] **Step 13.1: バックアップを保管 or 削除**

```bash
ls /Users/hoshidayuuya/Documents/FIT-CONNECT-BACKUP-2026-04-26/
# 1〜2週間運用が安定してから削除推奨
```

- [ ] **Step 13.2: 未マージ feature ブランチを全削除（合意事項どおり）**

合意事項により、既存の feature ブランチは全て破棄。GitHub UI または gh CLI で一括削除:

```bash
# Web側 — develop と main 以外の全リモートブランチを削除
cd /Users/hoshidayuuya/Documents/FIT-CONNECT  # rename 後の monorepo
git branch -r | grep 'origin/' | grep -v 'HEAD' | grep -v 'origin/main$' \
  | sed 's|origin/||' | while read branch; do
    echo "deleting origin/$branch"
    # 確認のため最初は dry-run（コメントアウト中の行）
    # echo git push origin --delete "$branch"
    git push origin --delete "$branch"
  done

# 旧 fit-connect-mobile リポジトリは Task 12 で archive 済みのためブランチ削除不要
# （archive されたリポジトリでは push できない＝事実上ブランチもfreeze）
```

> **注意:** 上記スクリプトは monorepo（旧 fit-connect リポジトリ）の全 feature ブランチを削除する。**Step 13.4（develop 削除）の後に実行する場合は develop の grep 除外を追加不要。develop 削除前に実行する場合は `grep -v 'origin/develop$'` を追加。**

> **ブランチ一覧は `/tmp/fit-connect-branches.txt` および `FIT-CONNECT-BACKUP-2026-04-26/*.txt` に保管済み（Step 0.4）**。後日「あのブランチ何だっけ」となった際の参照用。

- [ ] **Step 13.3: ドキュメント更新**

```bash
$EDITOR /Users/hoshidayuuya/Documents/FIT-CONNECT/CLAUDE.md
$EDITOR /Users/hoshidayuuya/Documents/FIT-CONNECT/docs/tasks/IMPLEMENTATION_TASKS.md
```

更新内容:
- モノレポ移行完了日を記載
- 新ディレクトリ構造の確定
- 旧リポジトリ参照は archive リンクへ

- [ ] **Step 13.4: develop ブランチの後始末（案X特有）**

main 上書きにより develop は main と同じ歴史を共有する状態になる（force push 後の main は元 develop の延長）。今後 develop は不要なため処理する:

```bash
cd /Users/hoshidayuuya/Documents/FIT-CONNECT

# 1. develop と main が同じ HEAD を指していることを確認
git log --oneline origin/main -1
git log --oneline origin/develop -1
# → 同じ commit hash か、main の方が進んでいる（モノレポ系コミットを含む）

# 2. develop に main にない変更がないか最終確認
git log --oneline origin/main..origin/develop
# 期待: 出力なし（あれば cherry-pick 検討）
```

選択肢:
- **A. develop を削除（推奨）**: モノレポ後は main 一本運用に揃える
  ```bash
  git push origin --delete develop
  git branch -d develop  # ローカルからも削除
  ```
- **B. develop をアーカイブ用に残す**: 念のため数ヶ月保持してから削除

> **注意: 旧 develop に紐づく未マージ feature ブランチがある場合、それらは parent が消えると履歴的に孤立する（git log では追える）。継続したい feature ブランチは、削除前に main ベースへ rebase しておくこと。**

- [ ] **Step 13.5: GitHub default branch の確認**

Step 11 で main へ force push 済みのため、GitHub default branch は `main` のままで良い。Vercel Production Branch も `main` のまま、設定変更不要。

- [ ] **Step 13.6: GitHub リポジトリ名はそのまま（rename しない）**

合意事項どおり `hoshiyuu0320/fit-connect` の名称は維持。
- monorepo 化したことは README に明記する（次の Step 13.3 で対応）
- 旧 mobile リポジトリ (`hoshiyuu0320/fit-connect-mobile`) は archive 化（Task 12）し、移動先として fit-connect リポジトリを案内

> **将来的に rename したくなった場合:** GitHub の repository rename は旧URLからのリダイレクトが効くため、後日でも比較的低コストで実施可能。現時点で急ぐ理由はない。

---

## Rollback Strategy（緊急時）

各 Task ごとの戻り方:

| Task | ロールバック方法 |
|------|---------------|
| Task 0-2 | バックアップから復元: `rm -rf FIT-CONNECT && cp -R FIT-CONNECT-BACKUP-2026-04-26 FIT-CONNECT` |
| Task 3-7 | `git reset --hard pre-monorepo-migration` (develop の元位置に戻る、まだ push してない) |
| Task 8-9 | `git reset --hard pre-monorepo-migration` + リモート feature/monorepo-migration 削除 |
| Task 10 | Vercel Dashboard で旧deploy（Mar 14, develop ベース）を Promote to Production |
| Task 11 (force push 後) | **最優先: Vercel で旧 deploy を Promote**。Git は `git reset --hard pre-monorepo-migration-main-original && git push --force-with-lease origin main` で旧 main（Initial commit）に戻す |
| Task 12+ | バックアップ復元 + 旧 mobile リポジトリ archive 解除（archive する前なら不要） |

---

## チェックリスト：完了条件

- [ ] `/Users/hoshidayuuya/Documents/FIT-CONNECT/` が単一の Git リポジトリになっている
- [ ] ルート直下に `fit-connect/`, `fit-connect-mobile/`, `supabase/`, `docs/`, `.claude/`, `CLAUDE.md` が存在
- [ ] `fit-connect/.git/` と `fit-connect-mobile/.git/` が存在しない
- [ ] **main が develop の内容 + モノレポ構造で更新されている**（Initial commit のみの状態から脱出）
- [ ] **本番 (`fit-connect-xi.vercel.app`) が Mar 14 凍結状態から最新（PR #41 weight-prediction まで）に更新されている**
- [ ] Vercel Production Branch は `main` のまま、Root Directory が `fit-connect` に変更済み
- [ ] mobile アプリがビルド可能
- [ ] Supabase migrations がルート `supabase/migrations/` から実行可能（29本）
- [ ] 旧 `fit-connect-mobile` リポジトリが archive 化されている
- [ ] CLAUDE.md / .claude が一本化され、子の冗長定義が削除されている
- [ ] **develop ブランチが削除済み（or アーカイブ）、main 一本運用に移行**
- [ ] 14日以上問題なく運用できている → バックアップ削除可

---

## 想定所要時間

- Task 0-2: 30分（バックアップ + ファイル移動）
- Task 3-4: 20分（ディレクトリ昇格 + CLAUDE 統合）
- Task 5: 10分（subtree 取り込み）
- Task 6-7: 30分（Supabase 統合 + CLAUDE 整理）
- Task 8: 30分（ローカル検証）
- Task 9-11: 60分（Vercel 設定 + preview 検証 + 本番マージ）
- Task 12-13: 任意（後日でOK）

**合計: 半日〜1日（検証含む）**
