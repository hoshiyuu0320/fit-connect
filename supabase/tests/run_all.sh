#!/usr/bin/env bash
# supabase/tests の SQL テストを、ローカルの Supabase の DB コンテナに psql で順に流す。
#
# 使い方（リポジトリのどこからでも）:
#   bash supabase/tests/run_all.sh              # supabase/tests/*_test.sql を名前順にすべて
#   bash supabase/tests/run_all.sh <file> ...   # 指定したファイルだけ（今いるディレクトリからのパス）
# 環境変数:
#   SUPABASE_DB_CONTAINER  DB のコンテナ名（既定 supabase_db_fit-connect）
#
# 成功の条件: psql の終了コードが 0 で、出力の最後の空でない行に PASSED がある。
# 終了コード: 0 = すべて成功 / 1 = 失敗したファイルがある / 2 = 流す前の確認で止まった
# 詳しくは supabase/tests/README.md。
set -euo pipefail

# 名前順を環境によらずそろえる
LC_ALL=C
export LC_ALL

TESTS_DIR=$(CDPATH='' cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SUPABASE_DIR=$(dirname -- "$TESTS_DIR")
REPO_ROOT=$(dirname -- "$SUPABASE_DIR")
MIGRATIONS_DIR="$SUPABASE_DIR/migrations"
CONTAINER=${SUPABASE_DB_CONTAINER:-supabase_db_fit-connect}
TAIL_LINES=30

die() {
  echo "ERROR: $*" >&2
  exit 2
}

# 今の時刻（ミリ秒）。bash 5 は EPOCHREALTIME、無ければ perl、それも無ければ秒の単位
now_ms() {
  if [ -n "${EPOCHREALTIME:-}" ]; then
    local us=${EPOCHREALTIME/[.,]/}
    echo $((us / 1000))
  elif command -v perl >/dev/null 2>&1; then
    perl -MTime::HiRes=time -e 'printf "%d\n", time() * 1000'
  else
    echo $(($(date +%s) * 1000))
  fi
}

format_secs() {
  printf '%d.%02ds' $(($1 / 1000)) $((($1 % 1000) / 10))
}

# 1つの SQL ファイルを流す。stdout と stderr（NOTICE・ERROR）はコンテナの中で 1 本にまとめる。
# docker exec の外でまとめると、2 本の流れの順序が入れ替わり、最後の行が PASSED でなくなることがある。
# -q はコマンドの完了タグ（DO・ROLLBACK など）を出さない（最後の PASSED が NOTICE のファイルがあるため）
run_sql_file() {
  docker exec -i "$CONTAINER" sh -c 'exec psql -U postgres -d postgres -v ON_ERROR_STOP=1 -X -q -f - 2>&1' < "$1"
}

# --- 流す前の確認 ---

command -v docker >/dev/null 2>&1 || die "docker が見つからない"

if ! state=$(docker inspect --type container -f '{{.State.Running}}' "$CONTAINER" 2>&1); then
  die "DB のコンテナ $CONTAINER を調べられない: $(printf '%s\n' "$state" | awk 'NF')
  ローカルのスタックを起動したか（supabase start）、SUPABASE_DB_CONTAINER を確かめる"
fi
[ "$state" = true ] || die "DB のコンテナ $CONTAINER が動いていない（状態: $state）"

# migration が当たっていない DB で流して「通った」とならないように、当たっている版をファイルと突き合わせる
[ -d "$MIGRATIONS_DIR" ] || die "migration のディレクトリが無い: $MIGRATIONS_DIR"
expected=$(
  for f in "$MIGRATIONS_DIR"/*.sql; do
    [ -e "$f" ] || continue
    b=${f##*/}
    echo "${b%%_*}"
  done | sort
)
expected_count=$(printf '%s\n' "$expected" | awk 'NF { n++ } END { print n + 0 }')

if ! applied=$(docker exec "$CONTAINER" psql -U postgres -d postgres -X -v ON_ERROR_STOP=1 -At \
  -c 'select version from supabase_migrations.schema_migrations' 2>&1); then
  die "supabase_migrations.schema_migrations を読めない（Supabase CLI で migration を当てた DB か確かめる）:
$applied"
fi
applied=$(printf '%s\n' "$applied" | awk 'NF' | sort)
applied_count=$(printf '%s\n' "$applied" | awk 'NF { n++ } END { print n + 0 }')

if [ "$applied_count" -ne "$expected_count" ] || [ "$applied" != "$expected" ]; then
  missing=$(comm -23 <(printf '%s\n' "$expected") <(printf '%s\n' "$applied") | awk 'NF' | paste -sd ' ' -)
  extra=$(comm -13 <(printf '%s\n' "$expected") <(printf '%s\n' "$applied") | awk 'NF' | paste -sd ' ' -)
  {
    echo "ERROR: DB に当たっている migration が supabase/migrations と合わない（DB $applied_count 行 / ファイル $expected_count 本）"
    if [ -n "$missing" ]; then echo "  DB に無い: $missing"; fi
    if [ -n "$extra" ]; then echo "  DB にだけある: $extra"; fi
    echo "  今のブランチの migration を当て直してから流す（ローカルのスタックなら supabase db reset など）"
  } >&2
  exit 2
fi

# --- 流すファイル ---

files=()
if [ "$#" -gt 0 ]; then
  for arg in "$@"; do
    { [ -f "$arg" ] && [ -r "$arg" ]; } || die "テストのファイルが無い: $arg"
    files+=("$arg")
  done
else
  for f in "$TESTS_DIR"/*_test.sql; do
    [ -e "$f" ] || continue
    files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || die "テストが無い: $TESTS_DIR/*_test.sql"
fi

echo "DB のコンテナ: $CONTAINER（migration $applied_count 本）/ テスト ${#files[@]} 本"
echo

# --- 流す ---

pass=0
fail=0
failed=()
all_started=$(now_ms)

for file in "${files[@]}"; do
  name=${file##*/}
  started=$(now_ms)
  # 外側の 2>&1 は docker 自身のエラー（コンテナが途中で止まったときなど）を受けるため
  if output=$(run_sql_file "$file" 2>&1); then status=0; else status=$?; fi
  elapsed=$(format_secs $(($(now_ms) - started)))
  last=$(printf '%s\n' "$output" | awk 'NF { line = $0 } END { print line }')

  if [ "$status" -eq 0 ] && [[ $last == *PASSED* ]]; then
    pass=$((pass + 1))
    printf 'PASS  %s  %s\n' "$name" "$elapsed"
    continue
  fi

  fail=$((fail + 1))
  shown=${file#"$REPO_ROOT"/}
  failed+=("$shown")
  if [ "$status" -ne 0 ]; then
    reason="終了コード $status"
  else
    reason="最後の行に PASSED が無い"
  fi
  printf 'FAIL  %s  %s  （%s）出力の末尾 %d 行:\n' "$name" "$elapsed" "$reason" "$TAIL_LINES"
  printf '%s\n' "$output" | tail -n "$TAIL_LINES" | sed 's/^/    | /'
  if [ "${GITHUB_ACTIONS:-}" = true ]; then
    echo "::error file=$shown,title=SQL テストの失敗::$name が失敗（$reason）"
  fi
done

echo
echo "成功 $pass / 失敗 $fail（$(format_secs $(($(now_ms) - all_started)))）"
if [ "$fail" -gt 0 ]; then
  echo "失敗したファイル:"
  for f in "${failed[@]}"; do
    echo "  $f"
  done
  exit 1
fi
