#!/usr/bin/env bash
# =============================================================================
# 証拠収集スクリプト（読み取り専用、criteria.md 0.1.2 準拠）
# このファイルは assessing-ai-sdlc-maturity スキルによりプロジェクト固有に生成されました。
# https://github.com/kemsakurai/ai-sdlc-maturity-model-skills
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 kemsakurai
#
# 使い方: collect-evidence.sh [対象リポジトリのパス] [--window-days N] [--anonymize-authors]
#   --anonymize-authors  コミット著者名と PR 作成者のログイン名を author-1, author-2, … に置き換える。
#                        証拠 JSON を公開の Issue などに投稿するときに使う。
# 必要なコマンド: git (2.22 以上), gh (認証済み), jq
# 環境変数: GH_RETRY_MAX（gh の最大試行回数、既定 3）、GH_RETRY_SLEEP（再試行の基本間隔の秒数、既定 3）
#
# gh で取得できなかったキーは、値を null にして error に理由を残す（0 とは書かない）。
# 取得できなかったキーの一覧は header.collection_errors に入る。
# =============================================================================
set -u

CRITERIA_VERSION="0.1.2"
SKILL_VERSION="0.1.2"
WINDOW_DAYS=90
TARGET_PATH="."
ANONYMIZE_AUTHORS=0

while [ $# -gt 0 ]; do
  case "$1" in
    --window-days)
      WINDOW_DAYS="$2"
      shift 2
      ;;
    --anonymize-authors)
      ANONYMIZE_AUTHORS=1
      shift
      ;;
    *)
      TARGET_PATH="$1"
      shift
      ;;
  esac
done

if [ -n "$TARGET_PATH" ] && [ "$TARGET_PATH" != "." ]; then
  cd "$TARGET_PATH" || { echo "エラー: $TARGET_PATH に移動できません" >&2; exit 1; }
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "エラー: $(pwd) は git リポジトリではありません" >&2; exit 1; }

# =============================================================================
# [プロジェクト固有設定ブロック]
# 初回実行時に、エージェントが対象リポジトリを調べて {{...}} を埋めます。
# - 空文字のままにした項目は、各セクションの既定値が使われます。
# - '...' で囲まれた項目の値には一重引用符（'）を入れないでください。引用符が要るときは二重引用符（"）を使います。
# - "..." で囲まれた項目の値には二重引用符（"）・$・` を入れないでください。
# =============================================================================
# ADR（設計決定記録）ディレクトリ
ADR_DIR=""

# 変更履歴・リリースログのファイルパス
CHANGELOG_FILE=""

# ルール履歴ドキュメントのパス候補（空白区切り）
RULE_HISTORY_FILES=""

# テストファイルの探索条件（find の式）
# 例: -name "test_*.py" -o -name "*.test.ts" -o -name "*_test.go"
TEST_FILE_FIND_EXPR='-path "./.github/workflows/test.yml" -o -path "./testdata/*" -name "*.java"'

# テストケース（関数・メソッド）のカウント用 grep 正規表現（ERE）
# 例: def test_|it\(|test\(
TEST_CASE_REGEX='^  [a-z0-9-]+:$'

# カバレッジの下限設定を探すファイル（空白区切り）
COVERAGE_GATE_FILES=""

# アーキテクチャ静的検査の設定ファイル（空白区切り、glob 可）と、それを呼ぶ行の正規表現
ARCH_LINT_CONFIG_FILES=""
ARCH_LINT_ENFORCE_PATTERN=''

# 検査・ゲートを実行する場所（pre-commit・タスクランナー・CI の定義。空白区切り）
ENFORCEMENT_FILES=".github/workflows"

# デプロイ・リリース関連ワークフローのファイル名の正規表現
DEPLOY_WORKFLOW_REGEX='release|dockerimage'

# ロールバック手順ドキュメントのパス候補（空白区切り）
ROLLBACK_DOC_FILES=""

# 監視の設定・スクリプトを示す語の正規表現と、探すディレクトリ（空白区切り）
MONITORING_PATTERNS=''
MONITORING_DIRS=".github/workflows"

# データ・スキーマ管理に関連する Issue ラベルの正規表現
DATA_LABELS_REGEX=''

# データ整合性ゲートを示す語の正規表現
DATA_GATE_PATTERN=''

# ユーザーリサーチに関連するキーワードの正規表現（`|` 区切り。GitHub 検索では OR に変換する）
USER_RESEARCH_REGEX=''

# ふりかえりのキーワード正規表現（ドキュメント）と PR タイトルの検索クエリ（GitHub 検索構文）
RETRO_DOC_REGEX=''
RETRO_PR_SEARCH=''

# 価値計測・定量的改善のキーワード正規表現（ドキュメント/変更履歴）
VALUE_METRIC_REGEX=''
QUANTITATIVE_IMPACT_REGEX=''

# ロードマップ・探索のラベル正規表現
ROADMAP_LABELS_REGEX=''

# 設計・運用ドキュメントを置くディレクトリ（空白区切り。ふりかえり・価値計測の検索対象）
DOC_DIRS="README.md .github/instructions"

# AI エージェントの Co-authored-by トレーラーを見分ける正規表現（名前またはメールに一致させる）
AI_COAUTHOR_REGEX=''
# =============================================================================

TMP_JSONL="$(mktemp)"
GH_ERR_FILE="$(mktemp)"
trap 'rm -f "$TMP_JSONL" "$GH_ERR_FILE"' EXIT

RUN_TS="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
ASSESSED_DATE="$(date -u +%Y-%m-%d)"

compute_window_start() {
  local end_date="$1" days="$2"
  if date -d "$end_date - $days days" +%Y-%m-%d >/dev/null 2>&1; then
    date -d "$end_date - $days days" +%Y-%m-%d
  else
    date -j -v-"${days}"d -f %Y-%m-%d "$end_date" +%Y-%m-%d
  fi
}

WINDOW_START="$(compute_window_start "$ASSESSED_DATE" "$WINDOW_DAYS")"
WINDOW_END="$ASSESSED_DATE"

HEAD_SHA="$(git rev-parse HEAD)"

# emit <key> <command> <limit-or-empty> <value-json>
emit() {
  local key="$1" cmd="$2" limit="$3" value_json="$4"
  jq -n --arg k "$key" --arg cmd "$cmd" --arg limit "$limit" --arg ts "$RUN_TS" --argjson v "$value_json" \
    '{($k): {value: $v, command: $cmd, limit: (if $limit == "" then null else ($limit | tonumber? // $limit) end), collected_at: $ts}}' \
    >> "$TMP_JSONL"
}

# ---------------------------------------------------------------------------
# gh の呼び出し
# gh は一時的に失敗することがある（ネットワーク、API の 5xx、レート制限など）。
# 失敗を 0 や空として記録すると「実態が 0」と読み違えるので、再試行したうえで、それでも失敗したキーは
# value: null、error: 理由 として記録する。
# ---------------------------------------------------------------------------
GH_RETRY_MAX="${GH_RETRY_MAX:-3}"
GH_RETRY_SLEEP="${GH_RETRY_SLEEP:-3}"
# 再試行しても直らない失敗（未認証、リモートが無い、リポジトリが無い等）を見分ける正規表現
GH_PERMANENT_ERROR_REGEX='auth login|not logged|authentication|no git remotes|none of the git remotes|could not resolve to a repository|not a git repository|HTTP 401|HTTP 404'

# gh_retry <gh の引数...> : gh を最大 GH_RETRY_MAX 回実行する。成功したら標準出力を出して 0 を返す。
# 失敗したら最後のエラーを GH_ERR_FILE に残して 1 を返す（$(...) の中で呼ばれても読めるようにファイルに書く）。
gh_retry() {
  local attempt=1 out
  while :; do
    if out="$(gh "$@" 2>"$GH_ERR_FILE")"; then
      printf '%s\n' "$out"
      return 0
    fi
    [ "$attempt" -ge "$GH_RETRY_MAX" ] && return 1
    grep -qiE "$GH_PERMANENT_ERROR_REGEX" "$GH_ERR_FILE" && return 1
    sleep $(( GH_RETRY_SLEEP * attempt ))
    attempt=$(( attempt + 1 ))
  done
}

# gh_last_error : 直前に失敗した gh のエラーメッセージ（1 行・最大 300 文字）
gh_last_error() { tr '\n' ' ' < "$GH_ERR_FILE" | sed -E 's/ +/ /g; s/ $//' | cut -c1-300; }

# gh_failure_reason : gh で取得できなかった理由（gh そのものが使えないのか、直前の呼び出しが失敗したのか）
gh_failure_reason() {
  if [ "$GH_AVAILABLE" = "1" ]; then gh_last_error; else printf 'gh unavailable: %s' "$GH_UNAVAILABLE_REASON"; fi
}

# emit_gh_failure <key> <command> <limit-or-empty> [reason] : 取得できなかったキーを value: null で記録する
emit_gh_failure() {
  local key="$1" cmd="$2" limit="$3" reason="${4:-}"
  [ -n "$reason" ] || reason="$(gh_failure_reason)"
  jq -n --arg k "$key" --arg cmd "$cmd" --arg limit "$limit" --arg ts "$RUN_TS" --arg err "$reason" \
    '{($k): {value: null, error: $err, command: $cmd, limit: (if $limit == "" then null else ($limit | tonumber? // $limit) end), collected_at: $ts}}' \
    >> "$TMP_JSONL"
}

# gh_int_key <key> <command> <limit-or-empty> <gh の引数...> : gh が出力した整数をキーの値にする。取得できなければ null で記録する
gh_int_key() {
  local key="$1" cmd="$2" limit="$3" out
  shift 3
  if [ "$GH_AVAILABLE" = "1" ] && out="$(gh_retry "$@")"; then
    emit "$key" "$cmd" "$limit" "$(json_int "$out")"
  else
    emit_gh_failure "$key" "$cmd" "$limit"
  fi
}

# 最初に gh を使えるか（インストール済み・認証済みで、対象が GitHub のリポジトリか）を確かめる。
# 使えないときは、GitHub 由来のキーを再試行せずにすべて「取得できなかった」と記録する。
GH_AVAILABLE=0
GH_UNAVAILABLE_REASON=""
REPO_NWO=""
if ! command -v gh >/dev/null 2>&1; then
  GH_UNAVAILABLE_REASON="gh command not found"
elif REPO_NWO="$(gh_retry repo view --json nameWithOwner -q .nameWithOwner)"; then
  GH_AVAILABLE=1
else
  REPO_NWO=""
  GH_UNAVAILABLE_REASON="$(gh_last_error)"
fi
if [ -z "$REPO_NWO" ]; then
  REPO_NWO="$(git remote get-url origin 2>/dev/null | sed -E 's#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#' || true)"
fi

json_bool() { [ "$1" = "1" ] && echo true || echo false; }
json_int() { echo "${1:-0}" | tr -d '[:space:]' | sed 's/^$/0/'; }
lines_to_array() { jq -R -s 'split("\n") | map(select(length>0))'; }

# uniq_c_to_array <name> : `uniq -c` の出力を [{<name>: 値, count: 件数}, …] にする
uniq_c_to_array() {
  jq -R -s --arg name "$1" 'split("\n") | map(select(length>0)) | map(capture("^\\s*(?<count>[0-9]+)\\s+(?<v>.+)$")) | map({($name): .v, count: (.count|tonumber)})'
}

# uniq_c_to_object : `uniq -c` の出力を {値: 件数, …} にする
uniq_c_to_object() {
  jq -R -s 'split("\n") | map(select(length>0)) | map(capture("^\\s*(?<count>[0-9]+)\\s+(?<v>.+)$")) | map({(.v): (.count|tonumber)}) | add // {}'
}

# existing_paths <path>... : 存在するパスだけを 1 行ずつ出力する（glob は呼び出し側で展開済み）
existing_paths() {
  local p
  for p in "$@"; do [ -e "$p" ] && printf '%s\n' "$p"; done
  return 0
}

# list_file_names <dir> : ディレクトリ直下のファイル名を 1 行ずつ、名前順に出力する（ディレクトリが無ければ何も出さない）
list_file_names() {
  [ -d "$1" ] || return 0
  find "$1" -mindepth 1 -maxdepth 1 -type f -exec basename {} \; | LC_ALL=C sort
}

# grep_any [-i] <ERE> <path>... : 存在するパスだけを再帰検索し、1 件でも一致すれば 0 を返す。
# grep は読めないパスが 1 つでもあると、一致があっても終了コード 2 を返すので、先に存在するものだけに絞る。
grep_any() {
  local icase=""
  if [ "$1" = "-i" ]; then icase="-i"; shift; fi
  local ptn="$1"; shift
  local found=() p
  for p in "$@"; do [ -e "$p" ] && found+=("$p"); done
  [ ${#found[@]} -gt 0 ] || return 1
  grep -rqE $icase -- "$ptn" "${found[@]}" 2>/dev/null
}

# regex_to_gh_query <a|b|c> : GitHub 検索用に `a OR b OR c` へ変換する
regex_to_gh_query() { printf '%s' "$1" | sed 's/|/ OR /g'; }

# anonymize_authors <prefix> : [{author, count}, …] の author を <prefix>-1, <prefix>-2, … に置き換える。
# --anonymize-authors が無いときは何もしない。bot（`[bot]` で終わる名前、`app/` で始まるログイン）は置き換えない。
anonymize_authors() {
  if [ "$ANONYMIZE_AUTHORS" = "1" ]; then
    jq --arg p "$1" '[to_entries[] | .key as $i | .value
      | if (.author | test("\\[bot\\]$|^app/"; "i")) then . else .author = "\($p)-\($i + 1)" end]'
  else
    cat
  fi
}

AUTHORS_TOP5_JSON="$(git log --format='%an' | sort | uniq -c | sort -rn | head -5 | uniq_c_to_array author | anonymize_authors author)"
SINGLE_AUTHOR="$(echo "$AUTHORS_TOP5_JSON" | jq 'length <= 1')"

# gh の一覧取得の安全上限（値が上限に張り付いていたら、実数はもっと多い）
GH_LIMIT=500
GH_LABEL_LIMIT=1000

# Issue に付いたラベル名の一覧（延べ。対象は最大 GH_LABEL_LIMIT 件の Issue）。H・M・P で使い回す
LABELS_OK=0
LABELS_FAILURE_REASON=""
if [ "$GH_AVAILABLE" = "1" ] && ALL_ISSUE_LABELS="$(gh_retry issue list --state all --limit "$GH_LABEL_LIMIT" --json labels -q '.[].labels[].name')"; then
  LABELS_OK=1
else
  ALL_ISSUE_LABELS=""
  LABELS_FAILURE_REASON="$(gh_failure_reason)"
fi
# count_labels <ERE> : ALL_ISSUE_LABELS のうち正規表現に一致するラベルの延べ数
count_labels() { printf '%s\n' "$ALL_ISSUE_LABELS" | grep -ciE -- "$1" || true; }

# label_key <key> <command> <ERE> : ラベルの延べ数をキーの値にする。ラベル一覧を取得できなかったら null で記録する
label_key() {
  if [ "$LABELS_OK" = "1" ]; then
    emit "$1" "$2" "$GH_LABEL_LIMIT" "$(json_int "$(count_labels "$3")")"
  else
    emit_gh_failure "$1" "$2" "$GH_LABEL_LIMIT" "$LABELS_FAILURE_REASON"
  fi
}

ENFORCE_TARGETS="${ENFORCEMENT_FILES:-.pre-commit-config.yaml .husky lefthook.yml Taskfile.yml Makefile justfile package.json .github/workflows}"

# ---------------------------------------------------------------------------
# A. エージェント運用知識の蓄積と継承
# ---------------------------------------------------------------------------
A_FILES=()
for f in AGENTS.md CLAUDE.md GEMINI.md .agents .claude .cursor .github/copilot-instructions.md; do
  [ -e "$f" ] && A_FILES+=("$f")
done
A_FILES_JSON="$(printf '%s\n' "${A_FILES[@]:-}" | lines_to_array)"
emit "a.agent_instruction_files" \
  "ls AGENTS.md CLAUDE.md GEMINI.md .agents .claude .cursor .github/copilot-instructions.md" "" "$A_FILES_JSON"

# スキルはディレクトリ（またはその symlink）単位で数え、同名は 1 つにまとめる
A_SKILLS_COUNT="$(for d in .agents/skills .claude/skills skills; do
    [ -d "$d" ] && find "$d" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -exec basename {} \;
  done | sort -u | wc -l | tr -d ' ')"
emit "a.skills_count" "find .agents/skills .claude/skills skills -mindepth 1 -maxdepth 1 (dir|symlink) | sort -u | wc -l" "" "$(json_int "$A_SKILLS_COUNT")"

A_RULE_HISTORY="0"
for rf in ${RULE_HISTORY_FILES:-docs/rule-history.md rule-history.md}; do
  [ -f "$rf" ] && { A_RULE_HISTORY="1"; break; }
done
emit "a.rule_history_doc_present" "check rule-history docs" "" "$(json_bool "$A_RULE_HISTORY")"

# ---------------------------------------------------------------------------
# B. 要件定義
# ---------------------------------------------------------------------------
B_ISSUE_TMPL="0"; { [ -d .github/ISSUE_TEMPLATE ] || [ -f .github/issue_template.md ]; } && B_ISSUE_TMPL="1"
emit "b.issue_template_exists" "check issue templates" "" "$(json_bool "$B_ISSUE_TMPL")"

B_PR_TMPL="0"; { [ -f .github/pull_request_template.md ] || [ -f .github/PULL_REQUEST_TEMPLATE.md ] || [ -d .github/PULL_REQUEST_TEMPLATE ]; } && B_PR_TMPL="1"
emit "b.pr_template_exists" "check pr templates" "" "$(json_bool "$B_PR_TMPL")"

gh_int_key "b.issues_open_count" "gh issue list --state open --limit $GH_LIMIT --json number -q 'length'" "$GH_LIMIT" \
  issue list --state open --limit "$GH_LIMIT" --json number -q 'length'

gh_int_key "b.issues_closed_count" "gh issue list --state closed --limit $GH_LABEL_LIMIT --json number -q 'length'" "$GH_LABEL_LIMIT" \
  issue list --state closed --limit "$GH_LABEL_LIMIT" --json number -q 'length'

# ---------------------------------------------------------------------------
# C. システム設計・アーキテクチャ
# ---------------------------------------------------------------------------
ADR_TARGET="${ADR_DIR:-docs/adr}"
# 索引・テンプレートは ADR として数えない（ファイル名だけでもパスでも一致する）
ADR_NON_RECORD_REGEX='(^|/)(readme|index|template)[^/]*\.md$'
adr_files() { list_file_names "$ADR_TARGET" | grep -E '\.md$' | grep -viE "$ADR_NON_RECORD_REGEX"; }

C_ADR_COUNT="$(adr_files | wc -l | tr -d ' ')"
emit "c.adr_count" "ls $ADR_TARGET | grep '\\.md$' (excluding README/index/template) | wc -l" "" "$(json_int "$C_ADR_COUNT")"

# ファイル名の最初の数字列を ADR 番号とみなし（先頭のゼロは無視）、同じ番号が複数あるものを列挙する
C_ADR_DUP_JSON="$(adr_files | sed -nE 's/^[^0-9]*([0-9]+).*$/\1/p' | sed -E 's/^0+([0-9])/\1/' | sort | uniq -d | lines_to_array)"
emit "c.adr_duplicates" "detect duplicate ADR numbers (first digit run in the file name)" "" "$C_ADR_DUP_JSON"

C_ARCH_CFG="0"
for af in ${ARCH_LINT_CONFIG_FILES:-.importlinter .dependency-cruiser.* .eslintrc-boundaries.* archunit.properties}; do
  [ -e "$af" ] && { C_ARCH_CFG="1"; break; }
done
emit "c.arch_lint_configured" "check arch lint configs" "" "$(json_bool "$C_ARCH_CFG")"

C_ARCH_ENFORCED="0"
ARCH_ENFORCE_PTN="${ARCH_LINT_ENFORCE_PATTERN:-lint-imports|import-linter|depcruise|dependency-cruiser|archunit}"
# shellcheck disable=SC2086
grep_any "$ARCH_ENFORCE_PTN" $ENFORCE_TARGETS && C_ARCH_ENFORCED="1"
emit "c.arch_lint_enforced" "grep arch lint invocation in pre-commit / task runner / CI" "" "$(json_bool "$C_ARCH_ENFORCED")"

# ---------------------------------------------------------------------------
# D. コーディング・開発
# ---------------------------------------------------------------------------
D_COMMIT_TOTAL="$(git rev-list --count HEAD)"
emit "d.commit_count_total" "git rev-list --count HEAD" "" "$(json_int "$D_COMMIT_TOTAL")"

D_COMMITS_WINDOW="$(git log --since="$WINDOW_START" --oneline | wc -l | tr -d ' ')"
emit "d.commits_window" "git log --since=<window-start> --oneline | wc -l" "" "$(json_int "$D_COMMITS_WINDOW")"

D_BY_MONTH_JSON="$(git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c | tail -12 | uniq_c_to_object)"
emit "d.commits_by_month" "git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c | tail -12" "12" "$D_BY_MONTH_JSON"

# 既定ブランチの first-parent 履歴のうち、PR 由来のコミット（squash の `(#N)` / merge commit の `Merge pull request #N`）の割合
D_FP_SUBJECTS="$(git log --first-parent --since="$WINDOW_START" --format='%s')"
D_FP_TOTAL="$(printf '%s' "$D_FP_SUBJECTS" | grep -c . || true)"
D_FP_PR="$(printf '%s' "$D_FP_SUBJECTS" | grep -cE '\(#[0-9]+\)|^Merge pull request #[0-9]+' || true)"
if [ "$(json_int "$D_FP_TOTAL")" -gt 0 ]; then
  D_PR_RATIO="$(jq -n --argjson a "$(json_int "$D_FP_PR")" --argjson b "$D_FP_TOTAL" '(($a/$b)*1000|round)/1000')"
else
  D_PR_RATIO="null"
fi
emit "d.pr_commit_ratio_window" "git log --first-parent --since=<window-start>: subjects with (#N) or 'Merge pull request #N' / all subjects" "" "$D_PR_RATIO"

# ---------------------------------------------------------------------------
# E. テスト・QA
# ---------------------------------------------------------------------------
EXCLUDE_DIRS="-path '*/node_modules' -o -path '*/.worktrees' -o -path '*/.claude/worktrees' -o -path '*/.git' -o -path '*/vendor' -o -path '*/.venv' -o -path '*/venv' -o -path '*/site-packages' -o -path '*/.tox' -o -path '*/target' -o -path '*/dist' -o -path '*/build'"
DEFAULT_TEST_FIND="-name 'test_*.py' -o -name '*_test.py' -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.spec.ts' -o -name '*.spec.js' -o -name '*_test.go' -o -name '*Test.java' -o -name '*_spec.rb'"
TEST_FIND="${TEST_FILE_FIND_EXPR:-$DEFAULT_TEST_FIND}"
list_test_files() { eval "find . \\( $EXCLUDE_DIRS \\) -prune -o -type f \\( $TEST_FIND \\) -print0" 2>/dev/null; }

E_TEST_FILES="$(list_test_files | tr -cd '\0' | wc -c | tr -d ' ')"
emit "e.test_files_count" "find test files" "" "$(json_int "$E_TEST_FILES")"

# 一致した行を数える（-h でファイル名を付けずに行だけを出すので、ファイルが 1 件でも複数でも同じ形で数えられる）
E_CASE_REGEX="${TEST_CASE_REGEX:-def test_|it\(|test\(|func Test|#\[test\]|@Test}"
E_TEST_CASES="$(list_test_files | xargs -0 grep -hE -- "$E_CASE_REGEX" /dev/null 2>/dev/null | wc -l | tr -d ' ')"
emit "e.test_cases_count" "grep test cases across test files" "" "$(json_int "$E_TEST_CASES")"

E_COV_GATE="0"
# shellcheck disable=SC2086
grep_any 'fail-under|fail_under|cov-fail|minimum-coverage|coverageThreshold|jacoco.*minimum' \
  ${COVERAGE_GATE_FILES:-pytest.ini pyproject.toml setup.cfg .coveragerc jest.config.js jest.config.ts vitest.config.ts vitest.config.js} $ENFORCE_TARGETS \
  && E_COV_GATE="1"
emit "e.coverage_gate_configured" "check coverage gate in config/workflows" "" "$(json_bool "$E_COV_GATE")"

# ---------------------------------------------------------------------------
# F. デプロイ・リリース
# ---------------------------------------------------------------------------
DEPLOY_WF_PTN="${DEPLOY_WORKFLOW_REGEX:-deploy|release|publish|^cd[-_.]}"
DEPLOY_FILES="$(list_file_names .github/workflows | grep -iE "$DEPLOY_WF_PTN" || true)"

F_SMOKE=0
for df in $DEPLOY_FILES; do
  smoke_hits="$(grep -c -iE 'smoke|curl|health|verify' ".github/workflows/$df" 2>/dev/null || true)"
  F_SMOKE=$((F_SMOKE + $(json_int "$smoke_hits")))
done
emit "f.smoke_steps" "grep smoke/health/verify in deploy workflows" "" "$(json_int "$F_SMOKE")"

# デプロイ系ワークフローのどれか 1 つに記載があるか、ロールバック手順のドキュメントがあれば true
F_ROLLBACK="0"
for df in $DEPLOY_FILES; do
  grep -qi 'rollback' ".github/workflows/$df" 2>/dev/null && { F_ROLLBACK="1"; break; }
done
if [ "$F_ROLLBACK" = "0" ]; then
  for rbd in ${ROLLBACK_DOC_FILES:-docs/rollback.md docs/ops/rollback.md docs/runbooks/rollback.md}; do
    [ -f "$rbd" ] && { F_ROLLBACK="1"; break; }
  done
fi
emit "f.rollback_doc_present" "check rollback documentation in deploy workflows and docs" "" "$(json_bool "$F_ROLLBACK")"

# デプロイ系ワークフローが 1 件も無ければ gh を呼ばずに {} とする。1 件でも取得できなければキー全体を null で記録する
F_DEPLOY_RUNS_JSON="{}"
F_DEPLOY_RUNS_FAILURE=""
for w in $DEPLOY_FILES; do
  if [ "$GH_AVAILABLE" != "1" ]; then
    F_DEPLOY_RUNS_FAILURE="$(gh_failure_reason)"
    break
  fi
  if ! CONCLUSIONS="$(gh_retry run list --workflow "$w" --created ">=$WINDOW_START" -L "$GH_LIMIT" --json conclusion -q '.[].conclusion')"; then
    F_DEPLOY_RUNS_FAILURE="$w: $(gh_last_error)"
    break
  fi
  CONCL_JSON="$(printf '%s\n' "$CONCLUSIONS" | grep -v '^$' | sort | uniq -c | uniq_c_to_object)"
  F_DEPLOY_RUNS_JSON="$(jq -n --argjson base "$F_DEPLOY_RUNS_JSON" --arg w "$w" --argjson c "$CONCL_JSON" '$base + {($w): $c}')"
done
if [ -z "$F_DEPLOY_RUNS_FAILURE" ]; then
  emit "f.deploy_runs" "gh run list for deploy workflows in window" "$GH_LIMIT" "$F_DEPLOY_RUNS_JSON"
else
  emit_gh_failure "f.deploy_runs" "gh run list for deploy workflows in window" "$GH_LIMIT" "$F_DEPLOY_RUNS_FAILURE"
fi

# ---------------------------------------------------------------------------
# G. 監視・インシデント対応
# ---------------------------------------------------------------------------
G_MONITORING="0"
MON_PTN="${MONITORING_PATTERNS:-sentry|uptime|healthcheck|health-check|datadog|newrelic|prometheus|grafana|pagerduty|opentelemetry}"
# shellcheck disable=SC2086
grep_any -i "$MON_PTN" ${MONITORING_DIRS:-.github/workflows terraform infra deploy k8s helm scripts} && G_MONITORING="1"
emit "g.monitoring_configured" "check monitoring configuration" "" "$(json_bool "$G_MONITORING")"

gh_int_key "g.incident_labeled_issues_count" "gh issue list with incident/postmortem labels in window" "$GH_LIMIT" \
  issue list --state all --search "created:>=$WINDOW_START" -L "$GH_LIMIT" --json labels -q \
  '[.[] | select([.labels[].name] | any(test("incident|postmortem";"i")))] | length'

# ---------------------------------------------------------------------------
# H. データ管理
# ---------------------------------------------------------------------------
DATA_PTN="${DATA_LABELS_REGEX:-dataset|data-pipeline|data-quality|schema|migration|etl}"
label_key "h.data_management_labels_count" "gh issue list labels matching data management keywords" "$DATA_PTN"

H_DATA_GATE="0"
# shellcheck disable=SC2086
grep_any "${DATA_GATE_PATTERN:-validate-data|data-validation|drift|integrity|schema-check|great_expectations|dbt test}" $ENFORCE_TARGETS && H_DATA_GATE="1"
emit "h.data_integrity_gate_configured" "check data/schema integrity gate in pre-commit / task runner / CI" "" "$(json_bool "$H_DATA_GATE")"

# ---------------------------------------------------------------------------
# I. 開発環境・パイプラインへの AI 組み込み
# ---------------------------------------------------------------------------
I_FILES=()
for f in .claude/settings.json .cursor .cursorrules .github/copilot-instructions.md .gemini .aider.conf.yml .continue; do
  [ -e "$f" ] && I_FILES+=("$f")
done
I_FILES_JSON="$(printf '%s\n' "${I_FILES[@]:-}" | lines_to_array)"
emit "i.tool_integration_files" "check AI tool config files" "" "$I_FILES_JSON"

# ローカルで強制されるガードレール: pre-commit の repo: local フック数 + .husky のフックファイル数 + lefthook.yml の有無
I_PRECOMMIT_LOCAL="$(grep -c 'repo: local' .pre-commit-config.yaml 2>/dev/null || true)"
I_HUSKY="$(find .husky -maxdepth 1 -type f ! -name '.*' 2>/dev/null | wc -l | tr -d ' ')"
I_LEFTHOOK="0"; [ -f lefthook.yml ] && I_LEFTHOOK="1"
I_LOCAL_HOOKS=$(( $(json_int "$I_PRECOMMIT_LOCAL") + $(json_int "$I_HUSKY") + I_LEFTHOOK ))
emit "i.local_guardrail_hooks_count" "count pre-commit repo: local + .husky hooks + lefthook.yml" "" "$I_LOCAL_HOOKS"

# ---------------------------------------------------------------------------
# J. AI 利用ポリシーと機械的強制
# ---------------------------------------------------------------------------
J_GOV="0"
for gf in AGENTS.md CLAUDE.md GEMINI.md docs/ai-policy.md docs/governance.md docs/ai-guidelines.md; do
  [ -f "$gf" ] && { J_GOV="1"; break; }
done
emit "j.governance_docs_present" "check governance docs" "" "$(json_bool "$J_GOV")"

J_DEPENDABOT="0"
{ [ -f .github/dependabot.yml ] || [ -f .github/dependabot.yaml ] || [ -f .github/renovate.json ] || [ -f renovate.json ]; } && J_DEPENDABOT="1"
emit "j.dependabot_or_renovate_present" "check dependabot/renovate" "" "$(json_bool "$J_DEPENDABOT")"

# キー名は互換のため codeql のままだが、CodeQL 以外のセキュリティ系ワークフローも対象にする
J_SECURITY_WF="0"
{ list_file_names .github/workflows | grep -iE 'codeql|security|audit|snyk|trivy|semgrep' >/dev/null 2>&1; } && J_SECURITY_WF="1"
emit "j.codeql_security_workflow_present" "check security workflows (codeql/snyk/trivy/semgrep/...)" "" "$(json_bool "$J_SECURITY_WF")"

# ---------------------------------------------------------------------------
# K. 透明性・監査証跡
# ---------------------------------------------------------------------------
# Co-authored-by トレーラー（キーの大文字小文字は区別しない）のうち、AI エージェントのものだけを数える。
# 1 コミットに AI の共著者が複数いても 1 件と数える。
AI_CO_PTN="${AI_COAUTHOR_REGEX:-claude|anthropic|copilot|openai|codex|chatgpt|gemini|cursor|devin|aider|\[bot\]}"
K_TRAILERS="$(git log --format='%(trailers:key=Co-authored-by,valueonly,separator=%x1f)')"
K_COAUTHORED="$(printf '%s' "$K_TRAILERS" | grep -ciE "$AI_CO_PTN" || true)"
emit "k.coauthored_count" "git log: commits with an AI agent Co-authored-by trailer" "" "$(json_int "$K_COAUTHORED")"

K_BY_MODEL_JSON="$(printf '%s' "$K_TRAILERS" | tr '\037' '\n' | grep -iE "$AI_CO_PTN" | sed -E 's/[[:space:]]*<[^>]*>[[:space:]]*$//' | \
  sort | uniq -c | sort -rn | head -10 | uniq_c_to_array model)"
emit "k.coauthored_by_model" "git log: AI agent Co-authored-by names (top 10)" "10" "$K_BY_MODEL_JSON"

if [ "${D_COMMIT_TOTAL:-0}" -gt 0 ]; then
  K_RATIO="$(jq -n --argjson a "$(json_int "$K_COAUTHORED")" --argjson b "$D_COMMIT_TOTAL" '(($a/$b)*1000|round)/1000')"
else
  K_RATIO="null"
fi
emit "k.coauthored_ratio_lower_bound" "coauthored_count / commit_count_total" "" "$K_RATIO"

# ---------------------------------------------------------------------------
# L. 人間–AI・AI–AI の協働プロトコル
# ---------------------------------------------------------------------------
# 窓内にマージされた PR の一覧を 1 回だけ取得し、レビュー状況と作成者の両方に使う
if [ "$GH_AVAILABLE" = "1" ] && L_MERGED_PRS="$(gh_retry pr list --state merged --search "merged:>=$WINDOW_START" \
    --json reviews,comments,additions,author -L "$GH_LIMIT")"; then
  L_PR_STATS_JSON="$(printf '%s' "$L_MERGED_PRS" | jq -c \
    '{count: length, with_review: ([.[] | select(.reviews|length>0)]|length), with_comments: ([.[] | select(.comments|length>0)]|length), avg_additions: (if length>0 then (([.[].additions]|add)/length|floor) else 0 end)}')"
  L_PR_AUTHORS_JSON="$(printf '%s' "$L_MERGED_PRS" | jq -r '.[].author.login' | \
    sort | uniq -c | sort -rn | uniq_c_to_array author | anonymize_authors pr-author)"
  emit "l.pr_review_stats_window" "gh pr list merged review stats in window" "$GH_LIMIT" "$L_PR_STATS_JSON"
  emit "l.pr_authors_window" "gh pr list merged authors in window" "$GH_LIMIT" "$L_PR_AUTHORS_JSON"
else
  L_FAILURE_REASON="$(gh_failure_reason)"
  emit_gh_failure "l.pr_review_stats_window" "gh pr list merged review stats in window" "$GH_LIMIT" "$L_FAILURE_REASON"
  emit_gh_failure "l.pr_authors_window" "gh pr list merged authors in window" "$GH_LIMIT" "$L_FAILURE_REASON"
fi

# ---------------------------------------------------------------------------
# M. 合成ユーザーリサーチ
# ---------------------------------------------------------------------------
UR_PTN="${USER_RESEARCH_REGEX:-persona|ペルソナ|user-research|ux-research|user-interview|usability}"
gh_int_key "m.user_research_issues_count" "gh issue list user research issues in window (keywords joined with OR)" "$GH_LIMIT" \
  issue list --state all --search "created:>=$WINDOW_START $(regex_to_gh_query "$UR_PTN")" -L "$GH_LIMIT" --json number -q 'length'

label_key "m.user_research_labels_count" "gh issue list labels matching user research" "$UR_PTN"

# ---------------------------------------------------------------------------
# N. 継続的改善のフィードバックループ
# ---------------------------------------------------------------------------
DOC_TARGETS="${DOC_DIRS:-docs}"
RETRO_DOC_PTN="${RETRO_DOC_REGEX:-ふりかえり|振り返り|retrospect|postmortem}"
# shellcheck disable=SC2086
N_RETRO_DOCS="$(existing_paths $DOC_TARGETS | tr '\n' '\0' | xargs -0 grep -rliE -- "$RETRO_DOC_PTN" /dev/null 2>/dev/null | wc -l | tr -d ' ')"
emit "n.retro_docs_count" "grep retro docs in DOC_DIRS ($DOC_TARGETS)" "" "$(json_int "$N_RETRO_DOCS")"

CHANGELOG_TARGET="${CHANGELOG_FILE:-CHANGELOG.md}"
N_CHANGELOG_LINES="0"
[ -f "$CHANGELOG_TARGET" ] && N_CHANGELOG_LINES="$(wc -l < "$CHANGELOG_TARGET" | tr -d ' ')"
emit "n.changelog_lines" "wc -l $CHANGELOG_TARGET" "" "$(json_int "$N_CHANGELOG_LINES")"

RETRO_PR_SEARCH_PTN="${RETRO_PR_SEARCH:-retro OR retrospective OR postmortem OR ふりかえり OR 振り返り in:title}"
gh_int_key "n.retro_prs_window_count" "gh pr list retro PRs in window" "$GH_LIMIT" \
  pr list --state merged --search "merged:>=$WINDOW_START $RETRO_PR_SEARCH_PTN" -L "$GH_LIMIT" --json number -q 'length'

# ---------------------------------------------------------------------------
# O. 価値計測
# ---------------------------------------------------------------------------
VAL_PTN="${VALUE_METRIC_REGEX:-lead time|リードタイム|サイクルタイム|cycle time|throughput|スループット|dora|deployment frequency|change failure rate|mttr}"
# shellcheck disable=SC2086
O_VALUE_MENTIONS="$(existing_paths $DOC_TARGETS | tr '\n' '\0' | xargs -0 grep -rnEi --include='*.md' -- "$VAL_PTN" /dev/null 2>/dev/null | wc -l | tr -d ' ')"
emit "o.value_metric_mentions_count" "grep value metrics mentions in DOC_DIRS ($DOC_TARGETS)" "" "$(json_int "$O_VALUE_MENTIONS")"

QUANT_PTN="${QUANTITATIVE_IMPACT_REGEX:-[0-9]+(\.[0-9]+)? ?(%|ms|sec|min|秒|分)|短縮|削減|speedup|faster|reduction}"
O_MEASUREMENT_LINES="$(grep -cEi -- "$QUANT_PTN" "$CHANGELOG_TARGET" 2>/dev/null || true)"
emit "o.changelog_measurement_lines_count" "grep quantitative impact in changelog" "" "$(json_int "$O_MEASUREMENT_LINES")"

# ---------------------------------------------------------------------------
# P. ビジョンと適応
# ---------------------------------------------------------------------------
ROADMAP_PTN="${ROADMAP_LABELS_REGEX:-roadmap|explore|探索|rfc|proposal|spike}"
label_key "p.roadmap_label_count" "gh issue list labels matching roadmap/explore" "$ROADMAP_PTN"

P_ADR_RECENT="$(git log --since="$WINDOW_START" --name-only --format='' -- "$ADR_TARGET" 2>/dev/null | sort -u | \
  grep -E '\.md$' | grep -viE "$ADR_NON_RECORD_REGEX" | wc -l | tr -d ' ')"
emit "p.adr_recent_count_window" "git log: ADR files changed in window (excluding README/index/template)" "" "$(json_int "$P_ADR_RECENT")"

# ---------------------------------------------------------------------------
# 出力
# ---------------------------------------------------------------------------
EVIDENCE_JSON="$(jq -s 'reduce .[] as $item ({}; . + $item)' "$TMP_JSONL")"

jq -n \
  --arg repo "$REPO_NWO" \
  --arg head "$HEAD_SHA" \
  --arg assessed_at "$ASSESSED_DATE" \
  --arg criteria_version "$CRITERIA_VERSION" \
  --arg skill_version "$SKILL_VERSION" \
  --arg window_start "$WINDOW_START" \
  --arg window_end "$WINDOW_END" \
  --argjson window_days "$WINDOW_DAYS" \
  --argjson authors_top5 "$AUTHORS_TOP5_JSON" \
  --argjson single_author "$SINGLE_AUTHOR" \
  --argjson authors_anonymized "$(json_bool "$ANONYMIZE_AUTHORS")" \
  --argjson gh_available "$(json_bool "$GH_AVAILABLE")" \
  --argjson evidence "$EVIDENCE_JSON" \
  '{
    header: {
      repository: $repo,
      head_sha: $head,
      assessed_at: $assessed_at,
      criteria_version: $criteria_version,
      skill_version: $skill_version,
      window: {start: $window_start, end: $window_end, days: $window_days},
      authors_top5: $authors_top5,
      single_author: $single_author,
      authors_anonymized: $authors_anonymized,
      gh_available: $gh_available,
      collection_errors: [$evidence | to_entries[] | select(.value.error != null) | .key]
    },
    evidence: $evidence
  }'

# 取得できなかったキーがあれば、標準エラーに一覧を出す（出力 JSON は壊さない）
COLLECTION_ERRORS="$(printf '%s' "$EVIDENCE_JSON" | jq -r 'to_entries[] | select(.value.error != null) | "\(.key): \(.value.error)"')"
if [ -n "$COLLECTION_ERRORS" ]; then
  {
    echo "警告: 次のキーは GitHub から取得できなかったため null にしました。採点では 0 ではなく「未取得」として扱ってください。"
    printf '%s\n' "$COLLECTION_ERRORS" | sed 's/^/  - /'
  } >&2
fi
