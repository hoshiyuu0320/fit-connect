# supabase/tests — DB の SQL テスト

DB の RLS・権限（GRANT）・トリガー・関数を確かめる SQL です。
1ファイルが1つの自己完結したテストです。`BEGIN ... ROLLBACK` の中で試験データを作るので、DB には何も残りません。
期待と違えば `RAISE EXCEPTION 'FAIL: ...'` で止まります。すべて通れば、最後に `ALL ... PASSED` の行を出します。

## 手元で流す

ローカルのスタック（`supabase start`。DB のコンテナは `supabase_db_fit-connect`）を起動している前提です。

```bash
# すべて（supabase/tests/*_test.sql を名前順に）
bash supabase/tests/run_all.sh

# 1本だけ（複数も並べられる。パスは今いるディレクトリから）
bash supabase/tests/run_all.sh supabase/tests/payments_rls_test.sql

# 別のスタックの DB に流す（コンテナ名は supabase_db_<config.toml の project_id>）
SUPABASE_DB_CONTAINER=supabase_db_<project_id> bash supabase/tests/run_all.sh
```

- 流す前に、DB に当たっている migration（`supabase_migrations.schema_migrations`）を `supabase/migrations/*.sql` と突き合わせます。合わなければ流さずに止まります。migration が当たっていない DB で「通った」とならないようにするためです。今のブランチの migration を当て直してから流します（`supabase db reset` など）
- 成功の条件は、psql の終了コードが 0 で、出力の最後の空でない行に `PASSED` があることです
- 失敗したファイルは、出力の末尾 30 行を出して次へ進みます。最後に「成功 N / 失敗 M」と失敗したファイルを出します
- 終了コードは、すべて成功で 0、失敗が1つでもあれば 1、流す前の確認で止まったら 2 です

## CI

`.github/workflows/supabase-db-tests.yml`（Supabase DB tests）が流します。

- いつ: `main`・`develop/**` へのプルリクエストと push で、`supabase/**` かこのワークフローが変わったとき。Actions の画面から手で流すこともできます（workflow_dispatch）
- 何を: Supabase CLI（2.120.0）で DB のコンテナだけを起動し（`supabase db start`）、`supabase/migrations` を当てます。そのあと `bash supabase/tests/run_all.sh` を流します
- seed は止めています。起動の前に、CI の作業ディレクトリの `config.toml` の末尾に `[db.seed] enabled = false` を足します（リポジトリの `config.toml` は変えません）。CI の DB は migration だけで、`public` の表は空です
- 秘密の値は使いません。公開リポジトリなので、ログは誰でも読めます

### マージの必須条件にするとき

- GitHub の branch protection（または ruleset）で、チェック `SQL tests` を必須にします
- このワークフローは paths で絞っています。`supabase/**` を変えないプルリクエストでは、チェックが出ません。そのまま必須にすると、そうしたプルリクエストはチェック待ちのままマージできません
- 必須にするなら、paths の絞り込みをやめてすべてのプルリクエストで流すか、変更が無いときに成功で終わるジョブを用意します

## 新しいテストを書くとき

- ファイル名は `*_test.sql` にします（`run_all.sh` が名前順に拾います）
- 先頭のコメントに、何を確かめるか・対象の migration・流し方を書きます
- 試験は `BEGIN;` と `ROLLBACK;` の間に書きます。試験データもその中で作り、コミットしません
- 期待と違えば `RAISE EXCEPTION 'FAIL: ...'` で止めます。`ON_ERROR_STOP=1` で流すので、そこで終わります
- すべて通ったら、最後に `PASSED` を含む行を出します（例: `\echo 'ALL PAYMENTS RLS TESTS PASSED'`）。その後ろには何も出しません
- seed のデータに頼りません。ローカルのスタックには `Seed.sql` のデータが入っていることがあり、CI には無いので、件数などは自分の試験データに絞って確かめます
- 手本は `device_tokens_rls_test.sql`・`payments_rls_test.sql`（RLS）などです

public に表を足したら、`rls_baseline_test.sql` にもその表を足します（足さないと、このテストが落ちます）。詳しい決まりは `rls_baseline_test.sql` の先頭のコメントにあります。
