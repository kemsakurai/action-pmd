#!/usr/bin/env bash
# =============================================================================
# 証拠収集スクリプト（読み取り専用、criteria.md 0.3.0 準拠）
# このファイルは assessing-ai-sdlc-maturity スキルによりプロジェクト固有に生成されました。
# https://github.com/kemsakurai/ai-sdlc-maturity-model-skills
#
# SPDX-License-Identifier: MIT
# Copyright (c) 2026 kemsakurai
#
# 使い方: collect-evidence.sh [対象リポジトリのパス] [--window-days N] [--anonymize-authors] [--framework-checked-at YYYY-MM-DD]
#   --anonymize-authors     コミット著者名と PR 作成者のログイン名を author-1, author-2, … に置き換える。
#                           証拠 JSON を公開の Issue などに投稿するときに使う。
#   --framework-checked-at  上流フレームワーク（DEFRA / Gigacore）との差分を最後に確認した日。header.framework_checked_at に入る。
# 必要なコマンド: git (2.22 以上), gh (認証済み), jq
# 環境変数: GH_RETRY_MAX（gh の最大試行回数、既定 3）、GH_RETRY_SLEEP（再試行の基本間隔の秒数、既定 3）
#
# ファイルの有無と中身は、git で追跡されているファイルだけを見る（未追跡のファイルは数えない）。
# 評価したブランチ・コミットと、既定ブランチからの遅れは header.evaluated_ref に入る。
# GitHub からの取得は REST API（gh api / gh run list）で行う。GraphQL API が使えない環境（Claude Code on the web 等）でも
# 取得できるようにするため。GraphQL を使うのは l.* の PR 一覧だけで、失敗したら REST で取り直す。
# gh で取得できなかったキーは、値を null にして error に理由を残す（0 とは書かない）。
# 取得できなかったキーの一覧は header.collection_errors に入る。
# =============================================================================
set -u

# git が ASCII 以外のパス（日本語のファイル名など）を "\350\252..." のように引用符付きで出力しないようにする
# （git の既定は core.quotePath=true で、そのままだと ls-files / grep の出力とパスの照合が一致しない）
git() { command git -c core.quotePath=false "$@"; }

CRITERIA_VERSION="0.3.0"
SKILL_VERSION="0.3.0"
# このスクリプト自身とテンプレートは、設定ファイルの grep の対象から外す（自分の本文にある検索語に一致しないように）
SELF_NAME="$(basename "$0")"
TEMPLATE_NAME="collect-evidence.template.sh"
WINDOW_DAYS=90
TARGET_PATH="."
ANONYMIZE_AUTHORS=0
FRAMEWORK_CHECKED_AT=""

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
    --framework-checked-at)
      FRAMEWORK_CHECKED_AT="$2"
      shift 2
      ;;
    *)
      TARGET_PATH="$1"
      shift
      ;;
  esac
done

if [ -n "$FRAMEWORK_CHECKED_AT" ] && ! printf '%s' "$FRAMEWORK_CHECKED_AT" | grep -qE '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'; then
  echo "エラー: --framework-checked-at は YYYY-MM-DD で指定してください" >&2; exit 1
fi
if [ -n "$TARGET_PATH" ] && [ "$TARGET_PATH" != "." ]; then
  cd "$TARGET_PATH" || { echo "エラー: $TARGET_PATH に移動できません" >&2; exit 1; }
fi
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo "エラー: $(pwd) は git リポジトリではありません" >&2; exit 1; }
# パスはすべてリポジトリのルートからの相対で扱う
cd "$(git rev-parse --show-toplevel)" || exit 1

# =============================================================================
# [プロジェクト固有設定ブロック]
# 初回実行時に、エージェントが対象リポジトリを調べて {{...}} を埋めます。
# - 空文字のままにした項目は、各セクションの既定値が使われます。
# - '...' で囲まれた項目の値には一重引用符（'）を入れないでください。引用符が要るときは二重引用符（"）を使います。
# - "..." で囲まれた項目の値には二重引用符（"）・$・` を入れないでください。
# - ここで埋めた値は、出力 JSON の header.config にそのまま記録されます（スクリプトを残さなくても再生成できるように）。
# =============================================================================
# ADR（設計決定記録）ディレクトリ
ADR_DIR="{{ADR_DIR}}"

# 変更履歴・リリースログのファイルパス
CHANGELOG_FILE="{{CHANGELOG_FILE}}"

# ルール履歴ドキュメントのパス候補（空白区切り）
RULE_HISTORY_FILES="{{RULE_HISTORY_FILES}}"

# 識別子付きのルールファイルを見分ける正規表現（ERE。リポジトリのルートからの相対パスに一致させる）
RULE_FILES_REGEX='{{RULE_FILES_REGEX}}'

# テストファイルの探索条件（find の式）
# 例: -name "test_*.py" -o -name "*.test.ts" -o -name "*_test.go"
TEST_FILE_FIND_EXPR='{{TEST_FILE_FIND_EXPR}}'

# テストケース（関数・メソッド）のカウント用 grep 正規表現（ERE）
# 例: def test_|it\(|test\(
TEST_CASE_REGEX='{{TEST_CASE_REGEX}}'

# カバレッジの下限設定を探すファイル（空白区切り）
COVERAGE_GATE_FILES="{{COVERAGE_GATE_FILES}}"

# アーキテクチャ静的検査の設定ファイル（空白区切り、glob 可）と、それを呼ぶ行の正規表現
ARCH_LINT_CONFIG_FILES="{{ARCH_LINT_CONFIG_FILES}}"
ARCH_LINT_ENFORCE_PATTERN='{{ARCH_LINT_ENFORCE_PATTERN}}'

# 検査・ゲートを実行する場所（pre-commit・タスクランナー・CI の定義。空白区切り）
ENFORCEMENT_FILES="{{ENFORCEMENT_FILES}}"

# デプロイ・リリース関連ワークフローのファイル名の正規表現
DEPLOY_WORKFLOW_REGEX='{{DEPLOY_WORKFLOW_REGEX}}'

# ロールバック手順ドキュメントのパス候補（空白区切り）
ROLLBACK_DOC_FILES="{{ROLLBACK_DOC_FILES}}"

# 監視の設定・スクリプトを示す語の正規表現と、探すディレクトリ（空白区切り）
MONITORING_PATTERNS='{{MONITORING_PATTERNS}}'
MONITORING_DIRS="{{MONITORING_DIRS}}"

# データ・スキーマ管理に関連する Issue ラベルの正規表現
DATA_LABELS_REGEX='{{DATA_LABELS_REGEX}}'

# データ整合性ゲートを示す語の正規表現
DATA_GATE_PATTERN='{{DATA_GATE_PATTERN}}'

# ユーザーリサーチに関連するキーワードの正規表現（`|` 区切り。GitHub 検索では OR に変換する）
USER_RESEARCH_REGEX='{{USER_RESEARCH_REGEX}}'

# ふりかえりのキーワード正規表現（ドキュメント）と PR タイトルの検索クエリ（GitHub 検索構文）
RETRO_DOC_REGEX='{{RETRO_DOC_REGEX}}'
RETRO_PR_SEARCH='{{RETRO_PR_SEARCH}}'

# 価値計測・定量的改善のキーワード正規表現（ドキュメント/変更履歴）
VALUE_METRIC_REGEX='{{VALUE_METRIC_REGEX}}'
QUANTITATIVE_IMPACT_REGEX='{{QUANTITATIVE_IMPACT_REGEX}}'

# ロードマップ・探索のラベル正規表現
ROADMAP_LABELS_REGEX='{{ROADMAP_LABELS_REGEX}}'

# 設計・運用ドキュメントを置くディレクトリ（空白区切り。ふりかえり・価値計測の検索対象）
DOC_DIRS="{{DOC_DIRS}}"

# AI エージェントの Co-authored-by トレーラーを見分ける正規表現（名前またはメールに一致させる）
AI_COAUTHOR_REGEX='{{AI_COAUTHOR_REGEX}}'

# AI のレビュアー・PR を作る AI エージェントの GitHub ログインを見分ける正規表現
AI_REVIEWER_REGEX='{{AI_REVIEWER_REGEX}}'
AI_AGENT_LOGIN_REGEX='{{AI_AGENT_LOGIN_REGEX}}'
# =============================================================================
CONFIG_VARS="ADR_DIR CHANGELOG_FILE RULE_HISTORY_FILES RULE_FILES_REGEX TEST_FILE_FIND_EXPR TEST_CASE_REGEX COVERAGE_GATE_FILES ARCH_LINT_CONFIG_FILES ARCH_LINT_ENFORCE_PATTERN ENFORCEMENT_FILES DEPLOY_WORKFLOW_REGEX ROLLBACK_DOC_FILES MONITORING_PATTERNS MONITORING_DIRS DATA_LABELS_REGEX DATA_GATE_PATTERN USER_RESEARCH_REGEX RETRO_DOC_REGEX RETRO_PR_SEARCH VALUE_METRIC_REGEX QUANTITATIVE_IMPACT_REGEX ROADMAP_LABELS_REGEX DOC_DIRS AI_COAUTHOR_REGEX AI_REVIEWER_REGEX AI_AGENT_LOGIN_REGEX"

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

# epoch_to_iso <秒> : UTC の ISO 8601 にする（GNU / BSD の date の両方に対応）
epoch_to_iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ
}

# file_mtime_epoch <path> : ファイルの更新日時（秒）。無ければ何も出さない
file_mtime_epoch() {
  [ -e "$1" ] || return 0
  stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"
}

WINDOW_START="$(compute_window_start "$ASSESSED_DATE" "$WINDOW_DAYS")"
WINDOW_END="$ASSESSED_DATE"

HEAD_SHA="$(git rev-parse HEAD)"
LAST_COMMIT_DATE="$(git log -1 --format='%cs')"

# ---------------------------------------------------------------------------
# 評価したブランチと、既定ブランチとのずれ
# ローカルのチェックアウトが既定ブランチの最新より古いと、最近追加された指示書・ワークフロー等が欠ける。
# ---------------------------------------------------------------------------
CURRENT_BRANCH="$(git branch --show-current)"
DEFAULT_BRANCH="$(git symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null | sed 's#^origin/##')"
if [ -z "$DEFAULT_BRANCH" ]; then
  for b in main master; do
    git rev-parse -q --verify "refs/remotes/origin/$b" >/dev/null && { DEFAULT_BRANCH="$b"; break; }
  done
fi
BEHIND_DEFAULT="null"
# 既定ブランチを評価しているか：ブランチ名が同じか、HEAD が origin/<既定ブランチ> と同じコミットなら true
# （origin/<既定ブランチ> を git worktree add で取り出すと detached HEAD になり、ブランチ名は空になるため）
IS_DEFAULT_BRANCH="null"
if [ -n "$DEFAULT_BRANCH" ]; then
  IS_DEFAULT_BRANCH="false"
  [ "$CURRENT_BRANCH" = "$DEFAULT_BRANCH" ] && IS_DEFAULT_BRANCH="true"
fi
if [ -n "$DEFAULT_BRANCH" ] && DEFAULT_SHA="$(git rev-parse -q --verify "refs/remotes/origin/$DEFAULT_BRANCH")"; then
  BEHIND_DEFAULT="$(git rev-list --count "HEAD..refs/remotes/origin/$DEFAULT_BRANCH")"
  [ "$DEFAULT_SHA" = "$HEAD_SHA" ] && IS_DEFAULT_BRANCH="true"
fi
# 最後に fetch した日時は FETCH_HEAD の更新日時。FETCH_HEAD は worktree ごとに別で、メインのチェックアウトで fetch すると
# 共通の git ディレクトリに、worktree で fetch するとその worktree 専用のディレクトリに書かれる。両方を見て新しい方を採る
FETCH_EPOCH="$(for fh in "$(git rev-parse --git-common-dir)/FETCH_HEAD" "$(git rev-parse --git-path FETCH_HEAD)"; do
    file_mtime_epoch "$fh"
  done | sort -n | tail -1)"
LAST_FETCH_AT=""
[ -n "$FETCH_EPOCH" ] && LAST_FETCH_AT="$(epoch_to_iso "$FETCH_EPOCH")"
UNCOMMITTED_CHANGES="false"
[ -n "$(git status --porcelain --untracked-files=no)" ] && UNCOMMITTED_CHANGES="true"

# 追跡されているファイルの一覧（リポジトリのルートからの相対パス）
ALL_TRACKED="$(git ls-files)"

# emit <key> <command> <limit-or-empty> <value-json> [note]
# note は、gh の失敗以外の理由で値が null になるときなどに、その理由を残す
emit() {
  local key="$1" cmd="$2" limit="$3" value_json="$4" note="${5:-}"
  jq -n --arg k "$key" --arg cmd "$cmd" --arg limit "$limit" --arg ts "$RUN_TS" --argjson v "$value_json" --arg note "$note" \
    '{($k): ({value: $v, command: $cmd, limit: (if $limit == "" then null else ($limit | tonumber? // $limit) end), collected_at: $ts}
      + (if $note == "" then {} else {note: $note} end))}' \
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
# 再試行しても直らない失敗（未認証、権限が無い、GraphQL が使えない、リモートが無い、リポジトリが無い等）を見分ける正規表現
GH_PERMANENT_ERROR_REGEX='auth login|not logged|authentication|no git remotes|none of the git remotes|could not resolve to a repository|not a git repository|HTTP 401|HTTP 403|HTTP 404|GraphQL is not available'
# レート制限（HTTP 403 で返ることがある）は待てば直るので、上の正規表現に一致しても再試行する
GH_RATE_LIMIT_REGEX='rate limit'

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
    if ! grep -qiE "$GH_RATE_LIMIT_REGEX" "$GH_ERR_FILE"; then
      grep -qiE "$GH_PERMANENT_ERROR_REGEX" "$GH_ERR_FILE" && return 1
    fi
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

# 対象の owner/name は git のリモート（origin、無ければ最初のリモート）から決める。
# gh repo view は GraphQL API を使うので、GraphQL が使えない環境でも動くように使わない。
REPO_REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$REPO_REMOTE" ]; then
  FIRST_REMOTE="$(git remote | head -1)"
  [ -n "$FIRST_REMOTE" ] && REPO_REMOTE="$(git remote get-url "$FIRST_REMOTE" 2>/dev/null || true)"
fi
REPO_NWO="$(printf '%s' "$REPO_REMOTE" | sed -E 's#/+$##; s#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')"

# 最初に gh を使えるか（インストール済み・認証済みで、対象が GitHub のリポジトリか）を REST API で確かめる。
# 使えないときは、GitHub 由来のキーを再試行せずにすべて「取得できなかった」と記録する。
GH_AVAILABLE=0
GH_UNAVAILABLE_REASON=""
if ! command -v gh >/dev/null 2>&1; then
  GH_UNAVAILABLE_REASON="gh command not found"
elif [ -z "$REPO_NWO" ]; then
  GH_UNAVAILABLE_REASON="no git remotes found"
elif gh_retry api "repos/$REPO_NWO" --jq .full_name >/dev/null; then
  GH_AVAILABLE=1
else
  GH_UNAVAILABLE_REASON="$(gh_last_error)"
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

# ---------------------------------------------------------------------------
# 追跡されているファイルだけを見るための関数
# 未追跡のファイル（ローカルにしかない指示書など）を「存在する」と数えないようにする。
# ---------------------------------------------------------------------------
# tracked <パス（glob 可）> : そのパス（ディレクトリならその下）に追跡されているファイルがあれば 0
tracked() { [ -n "$(git ls-files -- "$1" | head -1)" ]; }

# list_file_names <dir> : ディレクトリ直下の追跡されているファイル名を 1 行ずつ、名前順に出力する
list_file_names() {
  git ls-files -- "$1" | awk -v d="${1%/}/" 'index($0, d) == 1 { r = substr($0, length(d) + 1); if (r !~ /\//) print r }' | LC_ALL=C sort
}

# SELF_EXCLUDES : git grep で、このスクリプト自身とテンプレートを除くパススペック
SELF_EXCLUDES=(":(exclude,glob)**/$SELF_NAME" ":(exclude,glob)**/$TEMPLATE_NAME")

# grep_any [-i] <ERE> <path>... : 追跡されているファイルのうち、指定したパスの下を検索し、1 件でも一致すれば 0 を返す。
# このスクリプト自身とテンプレートは検索しない（本文にある既定の検索語に一致してしまうため）。
grep_any() {
  local icase=""
  if [ "$1" = "-i" ]; then icase="-i"; shift; fi
  local ptn="$1"; shift
  local found=() p
  for p in "$@"; do tracked "$p" && found+=("$p"); done
  [ ${#found[@]} -gt 0 ] || return 1
  # shellcheck disable=SC2086
  git grep -qE $icase -e "$ptn" -- "${found[@]}" "${SELF_EXCLUDES[@]}" 2>/dev/null
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

# bot の名前・ログイン（`[bot]` で終わるもの、`app/` で始まるもの）
BOT_NAME_REGEX='\[bot\]$|^app/'

# コミット著者は .mailmap で名寄せしてから数える（同じ人が複数の名前・メールアドレスでコミットしていることがある）
COMMIT_AUTHORS="$(git log --use-mailmap --format='%aN' | sort | uniq -c | sort -rn)"
AUTHORS_TOP5_JSON="$(printf '%s\n' "$COMMIT_AUTHORS" | head -5 | uniq_c_to_array author | anonymize_authors author)"
HUMAN_COMMIT_AUTHORS="$(printf '%s\n' "$COMMIT_AUTHORS" | uniq_c_to_array author | jq --arg bot "$BOT_NAME_REGEX" '[.[] | select(.author | test($bot; "i") | not)] | length')"

# gh の一覧取得の安全上限（値が上限に張り付いていたら、実数はもっと多い）
GH_LIMIT=500
GH_LABEL_LIMIT=1000
# GitHub の検索 API が返す結果の上限
GH_SEARCH_LIMIT=1000

# fetch_issue_labels : 新しい順に最大 GH_LABEL_LIMIT 件の Issue（PR を除く）に付いたラベル名を 1 行ずつ出す（REST API）
fetch_issue_labels() {
  local page=1 page_json page_len issues=0 rest
  while :; do
    page_json="$(gh_retry api "repos/$REPO_NWO/issues?state=all&per_page=100&page=$page")" || return 1
    page_len="$(printf '%s' "$page_json" | jq 'length')"
    rest=$(( GH_LABEL_LIMIT - issues ))
    printf '%s' "$page_json" | jq -r --argjson rest "$rest" '[.[] | select(.pull_request | not)] | .[:$rest][] | .labels[].name'
    issues=$(( issues + $(printf '%s' "$page_json" | jq --argjson rest "$rest" '[.[] | select(.pull_request | not)] | .[:$rest] | length') ))
    { [ "$page_len" -lt 100 ] || [ "$issues" -ge "$GH_LABEL_LIMIT" ]; } && return 0
    page=$(( page + 1 ))
  done
}

# Issue に付いたラベル名の一覧（延べ。対象は最大 GH_LABEL_LIMIT 件の Issue）。H・M・P で使い回す
LABELS_OK=0
LABELS_FAILURE_REASON=""
if [ "$GH_AVAILABLE" = "1" ] && ALL_ISSUE_LABELS="$(fetch_issue_labels)"; then
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
# エージェント向けの指示書（GitHub Copilot のパス別指示書 .github/instructions/*.instructions.md 等を含む）
AGENT_INSTRUCTION_PATHS="AGENTS.md CLAUDE.md GEMINI.md .agents .claude .cursor .github/copilot-instructions.md .github/instructions .github/prompts .github/chatmodes .github/skills .windsurfrules .clinerules CONVENTIONS.md"
A_FILES=()
for f in $AGENT_INSTRUCTION_PATHS; do
  tracked "$f" && A_FILES+=("$f")
done
A_FILES_JSON="$(printf '%s\n' "${A_FILES[@]:-}" | lines_to_array)"
emit "a.agent_instruction_files" "git ls-files $AGENT_INSTRUCTION_PATHS" "" "$A_FILES_JSON"

# スキルはディレクトリ（またはその symlink）単位で数え、同名は 1 つにまとめる。
# 直下の通常ファイル（README.md、.gitkeep 等）は数えない。git ls-files -s の 1 列目が 120000 なら symlink
SKILL_DIRS=".agents/skills .claude/skills .github/skills skills"
A_SKILLS_COUNT="$(for d in $SKILL_DIRS; do
    git ls-files -s -- "$d" | awk -v d="$d/" '{
      mode = $1; path = $0; sub(/^[^\t]*\t/, "", path)
      if (index(path, d) != 1) next
      r = substr(path, length(d) + 1)
      if (r ~ /\//) { sub(/\/.*/, "", r); print r } else if (mode == "120000") print r
    }'
  done | sort -u | grep -c . || true)"
emit "a.skills_count" "git ls-files $SKILL_DIRS: distinct first-level entries" "" "$(json_int "$A_SKILLS_COUNT")"

A_RULE_HISTORY="0"
for rf in ${RULE_HISTORY_FILES:-docs/rule-history.md rule-history.md}; do
  tracked "$rf" && { A_RULE_HISTORY="1"; break; }
done
emit "a.rule_history_doc_present" "check rule-history docs" "" "$(json_bool "$A_RULE_HISTORY")"

# 識別子付きのルールファイル（Cursor の .mdc、Copilot のパス別指示書、Claude / Windsurf / Cline のルール等）
RULE_PTN="${RULE_FILES_REGEX:-^\.cursor/rules/.+\.mdc$|^\.github/instructions/.+\.instructions\.md$|^\.claude/rules/.+\.md$|^\.agents/rules/.+\.md$|^\.windsurf/rules/.+\.md$|^\.clinerules/.+\.md$}"
A_RULE_FILES="$(printf '%s\n' "$ALL_TRACKED" | grep -cE -- "$RULE_PTN" || true)"
emit "a.rule_files_count" "git ls-files | grep -E RULE_FILES_REGEX" "" "$(json_int "$A_RULE_FILES")"

# 窓内に、指示書・ルール・ルール履歴のパスを変えた既定ブランチのコミット（squash なら PR）の数。
# .claude・.agents 等はディレクトリごと対象なので、スキルや設定ファイルだけを変えたコミットも数える。ラベルや Issue フォームは見ない。
# git log が失敗したときは 0 ではなく null と note を記録する
A_RULE_CHANGES_CMD="git log --first-parent --since=<window-start> -- <agent instruction paths> <rule history files> | wc -l"
# shellcheck disable=SC2086
if A_RULE_CHANGES_LOG="$(git log --first-parent --since="$WINDOW_START" --format='%H' -- $AGENT_INSTRUCTION_PATHS ${RULE_HISTORY_FILES:-docs/rule-history.md rule-history.md} 2>"$GH_ERR_FILE")"; then
  emit "a.rule_change_commits_window" "$A_RULE_CHANGES_CMD" "" "$(printf '%s' "$A_RULE_CHANGES_LOG" | grep -c . || true)"
else
  emit "a.rule_change_commits_window" "$A_RULE_CHANGES_CMD" "" "null" "git log failed: $(gh_last_error)"
fi

# ---------------------------------------------------------------------------
# B. 要件定義
# ---------------------------------------------------------------------------
# GitHub はリポジトリのルート・docs/・.github/ のどこに置いたテンプレートでも使う（ファイル名の大文字小文字は問わない）
B_ISSUE_TMPL="0"
grep -qiE '^(\.github/|docs/)?issue_template(\.md$|/)' <<< "$ALL_TRACKED" && B_ISSUE_TMPL="1"
emit "b.issue_template_exists" "git ls-files: issue_template.md or ISSUE_TEMPLATE/ in root, docs/ or .github/ (case-insensitive)" "" "$(json_bool "$B_ISSUE_TMPL")"

B_PR_TMPL="0"
grep -qiE '^(\.github/|docs/)?pull_request_template(\.md$|/)' <<< "$ALL_TRACKED" && B_PR_TMPL="1"
emit "b.pr_template_exists" "git ls-files: pull_request_template.md or PULL_REQUEST_TEMPLATE/ in root, docs/ or .github/ (case-insensitive)" "" "$(json_bool "$B_PR_TMPL")"

gh_int_key "b.issues_open_count" "gh api search/issues q='type:issue state:open' --jq .total_count" "" \
  api -X GET search/issues -f q="repo:$REPO_NWO type:issue state:open" -f per_page=1 --jq .total_count

gh_int_key "b.issues_closed_count" "gh api search/issues q='type:issue state:closed' --jq .total_count" "" \
  api -X GET search/issues -f q="repo:$REPO_NWO type:issue state:closed" -f per_page=1 --jq .total_count

# ---------------------------------------------------------------------------
# C. システム設計・アーキテクチャ
# ---------------------------------------------------------------------------
ADR_TARGET="${ADR_DIR:-docs/adr}"
# 索引・テンプレートは ADR として数えない（ファイル名だけでもパスでも一致する）
ADR_NON_RECORD_REGEX='(^|/)(readme|index|template)[^/]*\.md$'
adr_files() { list_file_names "$ADR_TARGET" | grep -E '\.md$' | grep -viE "$ADR_NON_RECORD_REGEX"; }

C_ADR_COUNT="$(adr_files | wc -l | tr -d ' ')"
emit "c.adr_count" "git ls-files $ADR_TARGET | grep '\\.md$' (excluding README/index/template) | wc -l" "" "$(json_int "$C_ADR_COUNT")"

# ファイル名の最初の数字列を ADR 番号とみなし（先頭のゼロは無視）、同じ番号が複数あるものを列挙する
C_ADR_DUP_JSON="$(adr_files | sed -nE 's/^[^0-9]*([0-9]+).*$/\1/p' | sed -E 's/^0+([0-9])/\1/' | sort | uniq -d | lines_to_array)"
emit "c.adr_duplicates" "detect duplicate ADR numbers (first digit run in the file name)" "" "$C_ADR_DUP_JSON"

C_ARCH_CFG="0"
for af in ${ARCH_LINT_CONFIG_FILES:-.importlinter .dependency-cruiser.* .eslintrc-boundaries.* archunit.properties}; do
  tracked "$af" && { C_ARCH_CFG="1"; break; }
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
D_COMMITS_WINDOW_NOTE=""
[ "$(json_int "$D_COMMITS_WINDOW")" -eq 0 ] && D_COMMITS_WINDOW_NOTE="no commits in the window (last commit: $LAST_COMMIT_DATE)"
emit "d.commits_window" "git log --since=<window-start> --oneline | wc -l" "" "$(json_int "$D_COMMITS_WINDOW")" "$D_COMMITS_WINDOW_NOTE"

D_BY_MONTH_JSON="$(git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c | tail -12 | uniq_c_to_object)"
emit "d.commits_by_month" "git log --format='%ad' --date=format:'%Y-%m' | sort | uniq -c | tail -12" "12" "$D_BY_MONTH_JSON"

# 既定ブランチの first-parent 履歴のうち、PR 由来のコミット（squash の `(#N)` / merge commit の `Merge pull request #N`）の割合
D_FP_SUBJECTS="$(git log --first-parent --since="$WINDOW_START" --format='%s')"
D_FP_TOTAL="$(printf '%s' "$D_FP_SUBJECTS" | grep -c . || true)"
D_FP_PR="$(printf '%s' "$D_FP_SUBJECTS" | grep -cE '\(#[0-9]+\)|^Merge pull request #[0-9]+' || true)"
D_PR_RATIO_NOTE=""
if [ "$(json_int "$D_FP_TOTAL")" -gt 0 ]; then
  D_PR_RATIO="$(jq -n --argjson a "$(json_int "$D_FP_PR")" --argjson b "$D_FP_TOTAL" '(($a/$b)*1000|round)/1000')"
else
  D_PR_RATIO="null"
  D_PR_RATIO_NOTE="no first-parent commits in the window (last commit: $LAST_COMMIT_DATE)"
fi
emit "d.pr_commit_ratio_window" "git log --first-parent --since=<window-start>: subjects with (#N) or 'Merge pull request #N' / all subjects" "" "$D_PR_RATIO" "$D_PR_RATIO_NOTE"

# ---------------------------------------------------------------------------
# E. テスト・QA
# ---------------------------------------------------------------------------
EXCLUDE_DIRS="-path '*/node_modules' -o -path '*/.worktrees' -o -path '*/.claude/worktrees' -o -path '*/.git' -o -path '*/vendor' -o -path '*/.venv' -o -path '*/venv' -o -path '*/site-packages' -o -path '*/.tox' -o -path '*/target' -o -path '*/dist' -o -path '*/build'"
DEFAULT_TEST_FIND="-name 'test_*.py' -o -name '*_test.py' -o -name '*.test.ts' -o -name '*.test.tsx' -o -name '*.test.js' -o -name '*.spec.ts' -o -name '*.spec.js' -o -name '*_test.go' -o -name '*Test.java' -o -name '*Test.kt' -o -name '*_spec.rb'"
TEST_FIND="${TEST_FILE_FIND_EXPR:-$DEFAULT_TEST_FIND}"
# find で見つけたファイルのうち、追跡されているものだけを NUL 区切りで出す
list_test_files() {
  eval "find . \\( $EXCLUDE_DIRS \\) -prune -o -type f \\( $TEST_FIND \\) -print" 2>/dev/null | sed 's#^\./##' | \
    grep -Fx -f <(printf '%s\n' "$ALL_TRACKED") | tr '\n' '\0'
}

E_TEST_FILES="$(list_test_files | tr -cd '\0' | wc -c | tr -d ' ')"
emit "e.test_files_count" "find test files (tracked only)" "" "$(json_int "$E_TEST_FILES")"

# 一致した行を数える（-h でファイル名を付けずに行だけを出すので、ファイルが 1 件でも複数でも同じ形で数えられる）
E_CASE_REGEX="${TEST_CASE_REGEX:-def test_|it\(|test\(|func Test|#\[test\]|@Test}"
E_TEST_CASES="$(list_test_files | xargs -0 grep -hE -- "$E_CASE_REGEX" /dev/null 2>/dev/null | wc -l | tr -d ' ')"
emit "e.test_cases_count" "grep test cases across test files" "" "$(json_int "$E_TEST_CASES")"

E_COV_GATE="0"
# shellcheck disable=SC2086
grep_any 'fail-under|fail_under|cov-fail|minimum-coverage|coverageThreshold|jacoco.*minimum|jacocoTestCoverageVerification|violationRules|koverVerify' \
  ${COVERAGE_GATE_FILES:-pytest.ini pyproject.toml setup.cfg .coveragerc jest.config.js jest.config.ts vitest.config.ts vitest.config.js build.gradle build.gradle.kts pom.xml} $ENFORCE_TARGETS \
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
    tracked "$rbd" && { F_ROLLBACK="1"; break; }
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
# scripts には証拠収集スクリプト自身（既定の配置先 scripts/ai-sdlc/）も入るが、grep_any が自分自身を除くので誤検知しない
# shellcheck disable=SC2086
grep_any -i "$MON_PTN" ${MONITORING_DIRS:-.github/workflows terraform infra deploy k8s helm scripts} && G_MONITORING="1"
emit "g.monitoring_configured" "check monitoring configuration" "" "$(json_bool "$G_MONITORING")"

# 窓内に作られた Issue を検索 API で取り、incident / postmortem ラベルが付いたものを数える（ページごとの件数を足す）
G_INCIDENT_CMD="gh api --paginate search/issues q='type:issue created:>=<window-start>' | labels matching incident|postmortem"
if [ "$GH_AVAILABLE" = "1" ] && G_INCIDENT_PAGES="$(gh_retry api -X GET --paginate search/issues \
    -f q="repo:$REPO_NWO type:issue created:>=$WINDOW_START" -f per_page=100 \
    --jq '[.items[] | select([.labels[].name] | any(test("incident|postmortem"; "i")))] | length')"; then
  emit "g.incident_labeled_issues_count" "$G_INCIDENT_CMD" "$GH_SEARCH_LIMIT" \
    "$(printf '%s\n' "$G_INCIDENT_PAGES" | awk '{s += $1} END {print s + 0}')"
else
  emit_gh_failure "g.incident_labeled_issues_count" "$G_INCIDENT_CMD" "$GH_SEARCH_LIMIT"
fi

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
TOOL_INTEGRATION_PATHS=".claude/settings.json .cursor .cursorrules .github/copilot-instructions.md .github/instructions .github/prompts .github/chatmodes .gemini .aider.conf.yml .continue .windsurfrules .clinerules"
I_FILES=()
for f in $TOOL_INTEGRATION_PATHS; do
  tracked "$f" && I_FILES+=("$f")
done
I_FILES_JSON="$(printf '%s\n' "${I_FILES[@]:-}" | lines_to_array)"
emit "i.tool_integration_files" "check AI tool config files ($TOOL_INTEGRATION_PATHS)" "" "$I_FILES_JSON"

# ローカルで強制されるガードレール: pre-commit の repo: local フック数 + .husky のフックファイル数 + lefthook.yml の有無
I_PRECOMMIT_LOCAL="0"
tracked .pre-commit-config.yaml && I_PRECOMMIT_LOCAL="$(grep -c 'repo: local' .pre-commit-config.yaml 2>/dev/null || true)"
I_HUSKY="$(list_file_names .husky | grep -vc '^\.' || true)"
I_LEFTHOOK="0"; tracked lefthook.yml && I_LEFTHOOK="1"
I_LOCAL_HOOKS=$(( $(json_int "$I_PRECOMMIT_LOCAL") + $(json_int "$I_HUSKY") + I_LEFTHOOK ))
emit "i.local_guardrail_hooks_count" "count pre-commit repo: local + .husky hooks + lefthook.yml" "" "$I_LOCAL_HOOKS"

# AI エージェントの設定で強制されるガードレール（Claude Code / Gemini CLI の settings.json の hooks、Claude Code の権限の拒否ルール）
AGENT_SETTINGS_FILES=".claude/settings.json .gemini/settings.json"
I_HOOKS=0
I_DENIES=0
I_SETTINGS_BROKEN=""
for sf in $AGENT_SETTINGS_FILES; do
  tracked "$sf" || continue
  if ! jq -e . "$sf" >/dev/null 2>&1; then
    I_SETTINGS_BROKEN="${I_SETTINGS_BROKEN}${I_SETTINGS_BROKEN:+, }$sf"
    continue
  fi
  I_HOOKS=$(( I_HOOKS + $(jq '[(.hooks // {}) | .[]? | .[]? | .hooks[]?] | length' "$sf") ))
  I_DENIES=$(( I_DENIES + $(jq '(.permissions.deny // []) | length' "$sf") ))
done
if [ -z "$I_SETTINGS_BROKEN" ]; then
  emit "i.agent_hooks_count" "count hooks in $AGENT_SETTINGS_FILES" "" "$I_HOOKS"
  emit "i.agent_permission_denies_count" "count permissions.deny rules in $AGENT_SETTINGS_FILES" "" "$I_DENIES"
else
  emit "i.agent_hooks_count" "count hooks in $AGENT_SETTINGS_FILES" "" "null" "invalid JSON: $I_SETTINGS_BROKEN"
  emit "i.agent_permission_denies_count" "count permissions.deny rules in $AGENT_SETTINGS_FILES" "" "null" "invalid JSON: $I_SETTINGS_BROKEN"
fi

# ---------------------------------------------------------------------------
# J. AI 利用ポリシーと機械的強制
# ---------------------------------------------------------------------------
# エージェント向けの指示書（ツール別の指示書を含む）か、AI 利用の方針文書があれば true
GOVERNANCE_PATHS="AGENTS.md CLAUDE.md GEMINI.md .github/copilot-instructions.md .github/instructions .windsurfrules .clinerules CONVENTIONS.md docs/ai-policy.md docs/governance.md docs/ai-guidelines.md"
J_GOV="0"
for gf in $GOVERNANCE_PATHS; do
  tracked "$gf" && { J_GOV="1"; break; }
done
emit "j.governance_docs_present" "check governance docs ($GOVERNANCE_PATHS)" "" "$(json_bool "$J_GOV")"

J_DEPENDABOT="0"
for df in .github/dependabot.yml .github/dependabot.yaml .github/renovate.json renovate.json; do
  tracked "$df" && { J_DEPENDABOT="1"; break; }
done
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

# 窓内の、マージコミットを除いたコミットに限った割合（歴史の長いリポジトリで、最近の実態を見るため）
K_WIN_TRAILERS="$(git log --no-merges --since="$WINDOW_START" --format='%(trailers:key=Co-authored-by,valueonly,separator=%x1f)%x1e')"
K_WIN_TOTAL="$(printf '%s' "$K_WIN_TRAILERS" | tr -cd '\036' | wc -c | tr -d ' ')"
K_WIN_AI="$(printf '%s' "$K_WIN_TRAILERS" | tr '\036' '\n' | grep -ciE "$AI_CO_PTN" || true)"
K_WIN_NOTE=""
if [ "$(json_int "$K_WIN_TOTAL")" -gt 0 ]; then
  K_WIN_RATIO="$(jq -n --argjson a "$(json_int "$K_WIN_AI")" --argjson b "$K_WIN_TOTAL" '(($a/$b)*1000|round)/1000')"
else
  K_WIN_RATIO="null"
  K_WIN_NOTE="no non-merge commits in the window (last commit: $LAST_COMMIT_DATE)"
fi
emit "k.coauthored_ratio_window" "git log --no-merges --since=<window-start>: commits with an AI agent Co-authored-by trailer / all commits" "" "$K_WIN_RATIO" "$K_WIN_NOTE"

# ---------------------------------------------------------------------------
# L. 人間–AI・AI–AI の協働プロトコル
# ---------------------------------------------------------------------------
# 窓内にマージされた PR の一覧を 1 回だけ取得し、レビュー状況・作成者・AI の関与に使う。
# 一覧は [{reviews: 件数, comments: 件数, additions: 追加行数, author: ログイン, rv: [{login, state, at}]}, …] にそろえる。
# まず GraphQL（gh pr list、1 回で済む）で取り、失敗したら REST（検索 API + PR ごとに 2 回）で取り直す。
# bot のログインは GraphQL の表記（app/<name>）にそろえる（REST では <name>[bot] になる）。
l_merged_prs_graphql() {
  local out
  out="$(gh_retry pr list --state merged --search "merged:>=$WINDOW_START" --json reviews,comments,additions,author -L "$GH_LIMIT")" || return 1
  printf '%s' "$out" | jq -c '[.[] | {reviews: (.reviews | length), comments: (.comments | length), additions, author: .author.login,
    rv: [.reviews[] | {login: (.author.login // ""), state, at: (.submittedAt // "")}]}]'
}
l_merged_prs_rest() {
  local items line num additions reviews rows=""
  items="$(gh_retry api -X GET --paginate search/issues -f q="repo:$REPO_NWO type:pr is:merged merged:>=$WINDOW_START" -f per_page=100 \
    --jq '.items[] | {number, comments, author: (if .user.type == "Bot" then "app/" + (.user.login | sub("\\[bot\\]$"; "")) else .user.login end)} | @json')" || return 1
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    num="$(printf '%s' "$line" | jq '.number')"
    additions="$(gh_retry api "repos/$REPO_NWO/pulls/$num" --jq .additions)" || return 1
    reviews="$(gh_retry api "repos/$REPO_NWO/pulls/$num/reviews?per_page=100" \
      --jq '[.[] | {login: (if .user.type == "Bot" then "app/" + (.user.login | sub("\\[bot\\]$"; "")) else .user.login end), state, at: (.submitted_at // "")}]')" || return 1
    rows+="$(printf '%s' "$line" | jq -c --argjson a "$(json_int "$additions")" --argjson rv "$reviews" \
      '{reviews: ($rv | length), comments, additions: $a, author, rv: $rv}')"$'\n'
  done <<< "$(printf '%s\n' "$items" | head -n "$GH_LIMIT")"
  printf '%s' "$rows" | jq -s -c '.'
}

L_ROUTE=""
if [ "$GH_AVAILABLE" != "1" ]; then
  :
elif L_MERGED_PRS="$(l_merged_prs_graphql)"; then
  L_ROUTE="gh pr list --state merged --search 'merged:>=<window-start>' (GraphQL)"
elif L_MERGED_PRS="$(l_merged_prs_rest)"; then
  L_ROUTE="gh api search/issues 'type:pr is:merged merged:>=<window-start>' + pulls/{n} + pulls/{n}/reviews (REST)"
fi
AI_REVIEWER_PTN="${AI_REVIEWER_REGEX:-copilot|coderabbit|claude|gemini|codex|cursor|devin|sourcery|qodo|greptile|ellipsis}"
AI_AGENT_PTN="${AI_AGENT_LOGIN_REGEX:-copilot|devin|claude|codex|cursor|jules|openhands|sweep|gemini}"
L_HUMAN_PR_AUTHORS=""
if [ -n "$L_ROUTE" ]; then
  L_PR_STATS_JSON="$(printf '%s' "$L_MERGED_PRS" | jq -c \
    '{count: length, with_review: ([.[] | select(.reviews > 0)] | length), with_comments: ([.[] | select(.comments > 0)] | length), avg_additions: (if length > 0 then (([.[].additions] | add) / length | floor) else 0 end)}')"
  L_PR_AUTHORS_JSON="$(printf '%s' "$L_MERGED_PRS" | jq -r '.[].author' | \
    sort | uniq -c | sort -rn | uniq_c_to_array author | anonymize_authors pr-author)"
  L_HUMAN_PR_AUTHORS="$(printf '%s' "$L_MERGED_PRS" | jq --arg bot "$BOT_NAME_REGEX" '[.[].author | select(test($bot; "i") | not)] | unique | length')"
  # AI の関与：AI エージェントが作った PR、AI のレビュアーが付いた PR、AI のレビューの後に人が承認した PR
  L_AI_STATS_JSON="$(printf '%s' "$L_MERGED_PRS" | jq -c --arg ai "$AI_REVIEWER_PTN" --arg agent "$AI_AGENT_PTN" --arg bot "$BOT_NAME_REGEX" '
    def is_ai: test($ai; "i");
    def is_human: (is_ai | not) and (test($bot; "i") | not);
    {count: length,
     ai_authored: ([.[] | select(.author | test($agent; "i"))] | length),
     ai_reviewed: ([.[] | select(any(.rv[]; .login | is_ai))] | length),
     human_approved_after_ai_review: ([.[] | ([.rv[] | select(.login | is_ai) | .at] | min) as $t
       | select($t != null and any(.rv[]; (.login | is_human) and .state == "APPROVED" and .at >= $t))] | length)}')"
  emit "l.pr_review_stats_window" "$L_ROUTE: review stats" "$GH_LIMIT" "$L_PR_STATS_JSON"
  emit "l.pr_authors_window" "$L_ROUTE: authors" "$GH_LIMIT" "$L_PR_AUTHORS_JSON"
  emit "l.ai_pr_stats_window" "$L_ROUTE: AI-authored / AI-reviewed / human-approved-after-AI-review PRs" "$GH_LIMIT" "$L_AI_STATS_JSON"
else
  L_FAILURE_REASON="$(gh_failure_reason)"
  emit_gh_failure "l.pr_review_stats_window" "gh pr list / gh api: merged PR review stats in window" "$GH_LIMIT" "$L_FAILURE_REASON"
  emit_gh_failure "l.pr_authors_window" "gh pr list / gh api: merged PR authors in window" "$GH_LIMIT" "$L_FAILURE_REASON"
  emit_gh_failure "l.ai_pr_stats_window" "gh pr list / gh api: AI involvement in merged PRs in window" "$GH_LIMIT" "$L_FAILURE_REASON"
fi

# 単独メンテナか：bot を除いたコミット著者（名寄せ後）が 1 名以下なら true。
# そうでなくても、窓内にマージされた PR の作成者（bot を除く）が 1 名だけなら true とし、判定の根拠を残す。
if [ "$(json_int "$HUMAN_COMMIT_AUTHORS")" -le 1 ]; then
  SINGLE_AUTHOR="true"; SINGLE_AUTHOR_BASIS='"commit_authors"'
elif [ "$L_HUMAN_PR_AUTHORS" = "1" ]; then
  SINGLE_AUTHOR="true"; SINGLE_AUTHOR_BASIS='"pr_authors"'
else
  SINGLE_AUTHOR="false"; SINGLE_AUTHOR_BASIS="null"
fi

# ---------------------------------------------------------------------------
# M. 合成ユーザーリサーチ
# ---------------------------------------------------------------------------
UR_PTN="${USER_RESEARCH_REGEX:-persona|ペルソナ|user-research|ux-research|user-interview|usability}"
gh_int_key "m.user_research_issues_count" "gh api search/issues q='type:issue created:>=<window-start> <keywords joined with OR>' --jq .total_count" "" \
  api -X GET search/issues -f q="repo:$REPO_NWO type:issue created:>=$WINDOW_START $(regex_to_gh_query "$UR_PTN")" -f per_page=1 --jq .total_count

label_key "m.user_research_labels_count" "gh issue list labels matching user research" "$UR_PTN"

# ---------------------------------------------------------------------------
# N. 継続的改善のフィードバックループ
# ---------------------------------------------------------------------------
DOC_TARGETS="${DOC_DIRS:-docs}"
RETRO_DOC_PTN="${RETRO_DOC_REGEX:-ふりかえり|振り返り|retrospect|postmortem}"
DOC_TRACKED=()
for d in $DOC_TARGETS; do tracked "$d" && DOC_TRACKED+=("$d"); done
N_RETRO_DOCS=0
if [ ${#DOC_TRACKED[@]} -gt 0 ]; then
  N_RETRO_DOCS="$(git grep -liE -e "$RETRO_DOC_PTN" -- "${DOC_TRACKED[@]}" "${SELF_EXCLUDES[@]}" 2>/dev/null | wc -l | tr -d ' ')"
fi
emit "n.retro_docs_count" "git grep retro docs in DOC_DIRS ($DOC_TARGETS)" "" "$(json_int "$N_RETRO_DOCS")"

CHANGELOG_TARGET="${CHANGELOG_FILE:-CHANGELOG.md}"
N_CHANGELOG_LINES="0"
tracked "$CHANGELOG_TARGET" && [ -f "$CHANGELOG_TARGET" ] && N_CHANGELOG_LINES="$(wc -l < "$CHANGELOG_TARGET" | tr -d ' ')"
emit "n.changelog_lines" "wc -l $CHANGELOG_TARGET" "" "$(json_int "$N_CHANGELOG_LINES")"

RETRO_PR_SEARCH_PTN="${RETRO_PR_SEARCH:-retro OR retrospective OR postmortem OR ふりかえり OR 振り返り in:title}"
gh_int_key "n.retro_prs_window_count" "gh api search/issues q='type:pr is:merged merged:>=<window-start> $RETRO_PR_SEARCH_PTN' --jq .total_count" "" \
  api -X GET search/issues -f q="repo:$REPO_NWO type:pr is:merged merged:>=$WINDOW_START $RETRO_PR_SEARCH_PTN" -f per_page=1 --jq .total_count

# ---------------------------------------------------------------------------
# O. 価値計測
# ---------------------------------------------------------------------------
VAL_PTN="${VALUE_METRIC_REGEX:-lead time|リードタイム|サイクルタイム|cycle time|throughput|スループット|dora|deployment frequency|change failure rate|mttr}"
O_VALUE_MENTIONS=0
if [ ${#DOC_TRACKED[@]} -gt 0 ]; then
  # Markdown だけを数える（git grep -n の出力は「パス:行番号:本文」）
  O_VALUE_MENTIONS="$(git grep -nEi -e "$VAL_PTN" -- "${DOC_TRACKED[@]}" "${SELF_EXCLUDES[@]}" 2>/dev/null | grep -cE '^[^:]*\.md:[0-9]+:' || true)"
fi
emit "o.value_metric_mentions_count" "git grep value metrics mentions in DOC_DIRS ($DOC_TARGETS)" "" "$(json_int "$O_VALUE_MENTIONS")"

QUANT_PTN="${QUANTITATIVE_IMPACT_REGEX:-[0-9]+(\.[0-9]+)? ?(%|ms|sec|min|秒|分)|短縮|削減|speedup|faster|reduction}"
O_MEASUREMENT_LINES="0"
tracked "$CHANGELOG_TARGET" && O_MEASUREMENT_LINES="$(grep -cEi -- "$QUANT_PTN" "$CHANGELOG_TARGET" 2>/dev/null || true)"
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

# 設定ブロックの値（空文字は「既定値を使った」）。これと skill_version があれば同じスクリプトを再生成できる
CONFIG_JSON="$(for n in $CONFIG_VARS; do printf '%s\t%s\n' "$n" "${!n}"; done | \
  jq -R -s 'split("\n") | map(select(length > 0) | split("\t") | {(.[0]): (.[1:] | join("\t"))}) | add // {}')"

jq -n \
  --arg repo "$REPO_NWO" \
  --arg head "$HEAD_SHA" \
  --arg branch "$CURRENT_BRANCH" \
  --arg default_branch "$DEFAULT_BRANCH" \
  --argjson behind_default "$BEHIND_DEFAULT" \
  --argjson is_default_branch "$IS_DEFAULT_BRANCH" \
  --arg last_fetch_at "$LAST_FETCH_AT" \
  --argjson uncommitted_changes "$UNCOMMITTED_CHANGES" \
  --arg assessed_at "$ASSESSED_DATE" \
  --arg criteria_version "$CRITERIA_VERSION" \
  --arg skill_version "$SKILL_VERSION" \
  --arg framework_checked_at "$FRAMEWORK_CHECKED_AT" \
  --arg window_start "$WINDOW_START" \
  --arg window_end "$WINDOW_END" \
  --argjson window_days "$WINDOW_DAYS" \
  --arg last_commit_date "$LAST_COMMIT_DATE" \
  --argjson authors_top5 "$AUTHORS_TOP5_JSON" \
  --argjson single_author "$SINGLE_AUTHOR" \
  --argjson single_author_basis "$SINGLE_AUTHOR_BASIS" \
  --argjson authors_anonymized "$(json_bool "$ANONYMIZE_AUTHORS")" \
  --argjson gh_available "$(json_bool "$GH_AVAILABLE")" \
  --argjson config "$CONFIG_JSON" \
  --argjson evidence "$EVIDENCE_JSON" \
  'def nz: if . == "" then null else . end;
  {
    header: {
      repository: $repo,
      head_sha: $head,
      evaluated_ref: {
        branch: ($branch | nz),
        sha: $head,
        default_branch: ($default_branch | nz),
        is_default_branch: $is_default_branch,
        behind_default: $behind_default,
        last_fetch_at: ($last_fetch_at | nz),
        uncommitted_changes: $uncommitted_changes
      },
      assessed_at: $assessed_at,
      criteria_version: $criteria_version,
      skill_version: $skill_version,
      framework_checked_at: ($framework_checked_at | nz),
      window: {start: $window_start, end: $window_end, days: $window_days},
      last_commit_date: $last_commit_date,
      authors_top5: $authors_top5,
      single_author: $single_author,
      single_author_basis: $single_author_basis,
      authors_anonymized: $authors_anonymized,
      gh_available: $gh_available,
      collection_errors: [$evidence | to_entries[] | select(.value.error != null) | .key],
      config: $config
    },
    evidence: $evidence
  }'

# 評価したコミットが既定ブランチの最新と違えば、標準エラーに知らせる（出力 JSON は壊さない）
{
  if [ "$BEHIND_DEFAULT" != "null" ] && [ "$BEHIND_DEFAULT" -gt 0 ]; then
    echo "警告: HEAD は origin/$DEFAULT_BRANCH より $BEHIND_DEFAULT コミット遅れています（最終 fetch: ${LAST_FETCH_AT:-不明}）。最新を評価するなら fetch してから origin/$DEFAULT_BRANCH を別の worktree に取り出して実行してください。"
  fi
  if [ "$IS_DEFAULT_BRANCH" = "false" ]; then
    echo "警告: 評価したのは既定ブランチ（${DEFAULT_BRANCH}）ではなく ${CURRENT_BRANCH:-detached HEAD} です。"
  fi
  if [ "$UNCOMMITTED_CHANGES" = "true" ]; then
    echo "警告: 追跡されているファイルに未コミットの変更があります。ファイルの中身は作業ツリーの内容で数えています。"
  fi
} >&2

# 取得できなかったキーがあれば、標準エラーに一覧を出す（出力 JSON は壊さない）
COLLECTION_ERRORS="$(printf '%s' "$EVIDENCE_JSON" | jq -r 'to_entries[] | select(.value.error != null) | "\(.key): \(.value.error)"')"
if [ -n "$COLLECTION_ERRORS" ]; then
  {
    echo "警告: 次のキーは GitHub から取得できなかったため null にしました。採点では 0 ではなく「未取得」として扱ってください。"
    printf '%s\n' "$COLLECTION_ERRORS" | sed 's/^/  - /'
  } >&2
fi
