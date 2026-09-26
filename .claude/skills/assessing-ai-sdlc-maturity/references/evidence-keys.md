# 証拠キー リファレンス

`collect-evidence.sh` が出力する JSON の `evidence.<key>` それぞれが、何を数え、何の目安になるかの辞書。証拠はスクリプトの出力をそのまま使い、このファイルを見て手でコマンドを実行・転記しない（`gh` を使えない環境で補完するときだけ、末尾の「GitHub MCP・検索 API で補完するときのクエリ」を使う）。

キーを追加・削除・変更したら、`criteria.md` の該当項目にある「参照する証拠キー」行もあわせて直し、版を上げる。

## 出力の形

```json
{
  "header": {
    "repository": "owner/name",
    "head_sha": "…",
    "evaluated_ref": {
      "branch": "main",
      "sha": "…",
      "default_branch": "main",
      "is_default_branch": true,
      "behind_default": 0,
      "last_fetch_at": "YYYY-MM-DDThh:mm:ssZ",
      "uncommitted_changes": false
    },
    "assessed_at": "YYYY-MM-DD",
    "criteria_version": "0.3.0",
    "skill_version": "0.3.0",
    "framework_checked_at": null,
    "window": {"start": "YYYY-MM-DD", "end": "YYYY-MM-DD", "days": 90},
    "last_commit_date": "YYYY-MM-DD",
    "authors_top5": [{"author": "…", "count": 0}],
    "single_author": false,
    "single_author_basis": null,
    "authors_anonymized": false,
    "gh_available": true,
    "collection_errors": [],
    "config": {"ADR_DIR": "", "TEST_FILE_FIND_EXPR": "…"}
  },
  "evidence": {
    "<key>": {"value": "…", "command": "…", "limit": null, "collected_at": "…"}
  }
}
```

- `value`：採点と受け入れ基準に使う値
- `command`：値を出したコマンドの要約
- `limit`：`gh` の取得件数の上限。値がこの上限に張り付いているときは、実数がもっと多い可能性がある。検索 API の `total_count` で数えるキーは上限が無いので `null`
- `note`：`gh` の失敗以外の理由で値が 0 や `null` になったときの理由（例：集計期間にコミットが無い、設定ファイルの JSON が壊れている）。無いときはキーごと出さない
- `evaluated_ref`：評価したブランチとコミット。`default_branch` は `origin/HEAD`（無ければ `origin/main`・`origin/master`）から決め、分からなければ `null`。`behind_default` は HEAD が `origin/<既定ブランチ>` より何コミット遅れているか（最後の fetch の時点）。`last_fetch_at` は最後に fetch した日時。`uncommitted_changes` は追跡されているファイルに未コミットの変更があるか。遅れ・既定ブランチ以外・未コミットの変更があると、標準エラーに警告が出る
- `framework_checked_at`：上流フレームワーク（DEFRA / Gigacore）との差分を最後に確認した日。`--framework-checked-at YYYY-MM-DD` で渡す。渡さなければ `null`（未確認）
- `last_commit_date`：最後のコミットの日付。集計期間の開始日より前なら、`_window` のキーは休眠中のため 0 や `null` になる
- `single_author`：単独メンテナなら `true`。bot を除いたコミット著者（`.mailmap` で名寄せした後の名前）が 1 名以下か、集計期間にマージされた PR の作成者（bot を除く）が 1 名なら `true`。`criteria.md` の N/A 注記を当てるかどうかの判断に使う
- `single_author_basis`：`single_author` が `true` になった根拠。`"commit_authors"`（コミット著者）、`"pr_authors"`（PR の作成者）、`false` のときは `null`
- `authors_anonymized`：`--anonymize-authors` を付けて実行したなら `true`。このとき `header.authors_top5` と `l.pr_authors_window` の名前は `author-1`・`pr-author-1` のような仮の名前になる（bot は除く）。件数や順位は変わらない
- `gh_available`：実行の最初の確認で `gh` を使えたなら `true`。`false` のときは、GitHub から取るキーがすべて取得できていない
- `collection_errors`：取得できなかったキーの一覧。空でなければ、該当するキーを採点に使う前に再実行する
- `config`：設定ブロックに埋めた値（空文字は「既定値を使った」）。スクリプトをリポジトリに残さない運用でも、この値と `skill_version` のテンプレートから同じスクリプトを再生成できる

## 追跡されているファイルだけを見る

ファイルの有無と中身は、git で追跡されているファイル（`git ls-files`）だけを見る。ローカルにしかない未追跡のファイル（コミットしていない指示書、生成物など）は「存在しない」として数える。中身は作業ツリーの内容を読むので、未コミットの変更があるときは `evaluated_ref.uncommitted_changes` が `true` になる。

ローカルのチェックアウトが既定ブランチの最新より古いと、最近追加された指示書やワークフローが欠ける。最新を評価するときは、`git fetch` してから `git worktree add <一時ディレクトリ> origin/<既定ブランチ>` で取り出し、そのディレクトリを対象に実行する（作業ツリーには触れない）。

## 取得できなかったキー

GitHub から取るキー（`b.issues_*`、`f.deploy_runs`、`g.incident_labeled_issues_count`、`h.data_management_labels_count`、`l.*`、`m.*`、`n.retro_prs_window_count`、`p.roadmap_label_count`）は、`gh` が失敗すると取得できない。スクリプトは一時的な失敗（ネットワーク、API の 5xx、レート制限など）に備えて `GH_RETRY_MAX` 回（既定 3）まで試す。未認証・リモートが無い・HTTP 401/403/404 のように再試行しても直らない失敗は、すぐにあきらめる（HTTP 403 でもレート制限なら再試行する）。

GitHub からの取得は REST API（`gh api`、`gh run list`）で行うので、GraphQL API が使えない環境（Claude Code on the web 等）でも取得できる。GraphQL を使うのは `l.*` の PR 一覧だけで、失敗したら REST API（検索 API と PR ごとの API）で取り直す。どちらで取ったかは `l.*` の `command` に入る。bot のログインは、どちらの経路でも `app/<name>` の表記にそろえる。

それでも取得できなかったキーは次の形で記録する。値を `0` や `{}` にすると「実態が 0」と読み違えるので、`null` にする。

```json
"b.issues_open_count": {"value": null, "error": "HTTP 502: Bad Gateway", "command": "…", "limit": 500, "collected_at": "…"}
```

採点では、`value` が `null` のキーを 0 として扱わない。再実行しても取得できなければ「未取得」と明記し、そのキーに頼らずに判定するか、判定を保留する。

## 補完した値・近似した値の記録

`gh` を使えない環境で、GitHub MCP のツールや `curl` で値を補完したキーは、次の形で書き換える（`SKILL.md` の手順 2）。

- `value` を補完した値にし、`error` を消し、`command` を実際に使った手段（例：`GitHub MCP search_issues q='repo:o/n is:issue is:open'`）に置き換え、`"supplemented": true` を付ける。
- スクリプトと同じものを数えられず、別の方法で近い値を出したときは、さらに `"approximation": "<方法>"` を付ける（例：`"approximation": "期間内の PR と Issue に付いたラベルから推定"`）。近似した値は、採点ではその旨を書き、受け入れ基準の比較には使わない。
- 補完した値・近似した値の一覧は、レポートの評価の限界に書く。

```json
"h.data_management_labels_count": {"value": 12, "supplemented": true, "approximation": "期間内の PR と Issue のラベルから推定（ラベル一覧を取るツールが無い）", "command": "GitHub MCP search_issues …", "limit": null, "collected_at": "…"}
```

## GitHub MCP・検索 API で補完するときのクエリ

`gh` を使えない環境で補完するときは、評価者によって値が変わらないように、次のクエリを使う（`<o/n>` は対象リポジトリ、`<start>` は `header.window.start`）。件数だけが要るキーは、**1 ページ 1 件（`per_page=1`）で取り、結果の `total_count` だけを読む**。結果の本文（1 件あたり数十 KB）を取らないので、往復もトークンも大きく減る。

| キー | クエリ（GitHub 検索構文） | 値の出し方 |
| --- | --- | --- |
| `b.issues_open_count` | `repo:<o/n> is:issue is:open` | `total_count` |
| `b.issues_closed_count` | `repo:<o/n> is:issue is:closed` | `total_count` |
| `g.incident_labeled_issues_count` | `repo:<o/n> is:issue created:>=<start> label:incident,postmortem` | `total_count`（`label:a,b` は OR）。ラベル名が違うときはそのラベル名にし、`approximation` を付ける |
| `h.data_management_labels_count`・`m.user_research_labels_count`・`p.roadmap_label_count` | `repo:<o/n> is:issue label:<ラベル名>`（該当するラベル名ごと） | ラベルごとの `total_count` の合計。スクリプトは新しい 1000 件の Issue の延べ数なので、ラベル一覧を取れずに名前を推定したときや 1000 件を超えるときは `approximation` を付ける |
| `l.pr_review_stats_window` の `count` | `repo:<o/n> is:pr is:merged merged:>=<start>` | `total_count` |
| 同 `with_review` | `repo:<o/n> is:pr is:merged merged:>=<start> -review:none` | `total_count` |
| 同 `with_comments` | `repo:<o/n> is:pr is:merged merged:>=<start> comments:>0` | `total_count` |
| 同 `avg_additions` | 検索では取れない | PR ごとの取得が要る。取らないなら `null` にして `note` に理由を書く |
| `l.pr_authors_window` | `repo:<o/n> is:pr is:merged merged:>=<start>`（一覧） | 作成者ごとに数える。件数が多いときは、主な作成者ごとに `author:<login>` を足したクエリの `total_count` で数え、`approximation` を付ける |
| `l.ai_pr_stats_window` の `ai_authored` | `repo:<o/n> is:pr is:merged merged:>=<start> author:app/<エージェント名>`（例：`app/copilot-swe-agent`） | エージェントごとの `total_count` の合計 |
| 同 `ai_reviewed` | `repo:<o/n> is:pr is:merged merged:>=<start> reviewed-by:<AI レビュアーのログイン>` | `total_count`。bot のレビュアーに `reviewed-by:` が効くかは、AI のレビューが付いた既知の PR 1 件で先に確かめる。効かなければ PR ごとのレビュー一覧から数え、`approximation` を付ける |
| 同 `human_approved_after_ai_review` | 検索では取れない | PR ごとのレビュー一覧（投稿日時つき）が要る。取らないなら `null` |
| `m.user_research_issues_count` | `repo:<o/n> is:issue created:>=<start> persona OR ペルソナ OR …`（`USER_RESEARCH_REGEX` の語を OR でつなぐ） | `total_count` |
| `n.retro_prs_window_count` | `repo:<o/n> is:pr is:merged merged:>=<start> retro OR retrospective OR postmortem OR ふりかえり OR 振り返り in:title`（`RETRO_PR_SEARCH`） | `total_count` |
| `f.deploy_runs` | 検索では取れない（Actions の実行結果の API が要る） | 取れなければ `null` のままにし、代わりの証拠として `repo:<o/n> is:pr is:merged merged:>=<start> status:success` と `status:failure` の `total_count` を所見に書く（`SKILL.md` の証拠の強さの順位を参照） |

## 個人名が含まれるキー

`header.authors_top5`（コミット著者名）と `l.pr_authors_window`（PR 作成者のログイン名）には個人名が入る。`k.coauthored_by_model` は AI エージェントの名前だけを数えるので、通常は個人名を含まない。証拠 JSON を公開の場所（Public リポジトリの Issue 等）に投稿するときは、`--anonymize-authors` を付けて実行する。

## 時間窓

`--window-days`（既定 90）で指定した日数を、実行日（UTC）から遡った期間を「窓」と呼ぶ。`_window` で終わるキーと、`created:>=` / `merged:>=` で検索するキーは窓の中だけを数える。件数の上限だけで区切ると実行する時期によって別の期間を指してしまうので、時間で区切っている。

## プロジェクト固有の設定

以下はテンプレートの設定ブロックにある変数で、初回のスキャフォールドで対象リポジトリに合わせて埋める。空文字にするとスクリプト内の既定値が使われる。存在しないファイル・ディレクトリを列挙しても、そのパスは無視されるだけで結果は誤らない。埋めた値は `header.config` に記録される。

| 変数 | 影響するキー | 既定値の要点 |
| --- | --- | --- |
| `ADR_DIR` | `c.adr_*`, `p.adr_recent_count_window` | `docs/adr` |
| `CHANGELOG_FILE` | `n.changelog_lines`, `o.changelog_measurement_lines_count` | `CHANGELOG.md` |
| `RULE_HISTORY_FILES` | `a.rule_history_doc_present`, `a.rule_change_commits_window` | `docs/rule-history.md rule-history.md`（仮の名前。エージェント向けルールの変更理由を残すファイルは決まった名前が無いので、スキャフォールドのときに探して設定する） |
| `RULE_FILES_REGEX` | `a.rule_files_count` | `.cursor/rules/*.mdc`、`.github/instructions/*.instructions.md`、`.claude/rules/*.md`、`.agents/rules/*.md`、`.windsurf/rules/*.md`、`.clinerules/*.md` |
| `TEST_FILE_FIND_EXPR`, `TEST_CASE_REGEX` | `e.test_files_count`, `e.test_cases_count` | Python / JS / TS / Go / Java / Kotlin / Ruby の一般的な命名 |
| `COVERAGE_GATE_FILES` | `e.coverage_gate_configured` | pytest / coverage / jest / vitest の設定ファイルと `build.gradle(.kts)` / `pom.xml`（JaCoCo の検証タスク・`violationRules`、Kover の `koverVerify` を探す。`ENFORCEMENT_FILES` も併せて探す） |
| `ARCH_LINT_CONFIG_FILES`, `ARCH_LINT_ENFORCE_PATTERN` | `c.arch_lint_*` | import-linter / dependency-cruiser / ArchUnit |
| `ENFORCEMENT_FILES` | `c.arch_lint_enforced`, `e.coverage_gate_configured`, `h.data_integrity_gate_configured` | pre-commit / husky / lefthook / Taskfile / Makefile / justfile / package.json / `.github/workflows` |
| `DEPLOY_WORKFLOW_REGEX`, `ROLLBACK_DOC_FILES` | `f.*` | ワークフロー名に deploy / release / publish を含むもの。`release` はリリースブランチの保護など、デプロイではないワークフローにも一致しやすいので、スキャフォールドのときに一致したファイルを確かめる |
| `MONITORING_PATTERNS`, `MONITORING_DIRS` | `g.monitoring_configured` | 監視ツール名を、ワークフロー・インフラ定義・スクリプトから探す（証拠収集スクリプト自身とテンプレートは除く） |
| `DATA_LABELS_REGEX`, `DATA_GATE_PATTERN` | `h.*` | dataset / schema / migration / etl 等 |
| `USER_RESEARCH_REGEX` | `m.*` | persona / user-research / usability 等 |
| `RETRO_DOC_REGEX`, `RETRO_PR_SEARCH` | `n.retro_*` | ふりかえり / retrospective / postmortem |
| `VALUE_METRIC_REGEX`, `QUANTITATIVE_IMPACT_REGEX` | `o.*` | リードタイム・スループット・DORA 指標 / 数値＋単位、短縮・削減 |
| `ROADMAP_LABELS_REGEX` | `p.roadmap_label_count` | roadmap / explore / rfc / proposal / spike |
| `DOC_DIRS` | `n.retro_docs_count`, `o.value_metric_mentions_count` | `docs` |
| `AI_COAUTHOR_REGEX` | `k.*` | Claude / Copilot / OpenAI / Gemini / Cursor / Devin / Aider / `[bot]` など |
| `AI_REVIEWER_REGEX`, `AI_AGENT_LOGIN_REGEX` | `l.ai_pr_stats_window` | AI のレビュアー（Copilot / CodeRabbit / Claude / Gemini / Codex 等）と、PR を作る AI エージェント（Copilot / Devin / Claude / Codex / Jules 等）のログイン |

## A. エージェント運用知識の蓄積と継承

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `a.agent_instruction_files` | `AGENTS.md` / `CLAUDE.md` / `GEMINI.md` / `.agents` / `.claude` / `.cursor` / `.github/copilot-instructions.md` / `.github/instructions`（Copilot のパス別指示書）/ `.github/prompts` / `.github/chatmodes` / `.github/skills` / `.windsurfrules` / `.clinerules` / `CONVENTIONS.md` のうち、追跡されているもの | あればレベル 2 の候補 |
| `a.skills_count` | `.agents/skills` / `.claude/skills` / `.github/skills` / `skills` 直下のディレクトリ（symlink 含む）の数。同名はまとめて 1 | スキルとして体系化されていればレベル 3 の候補 |
| `a.rule_history_doc_present` | ルール変更の根拠履歴（`RULE_HISTORY_FILES`）の有無 | レベル 3 の候補 |
| `a.rule_files_count` | 識別子付きのルールファイル（`RULE_FILES_REGEX`）の数 | ルールの規模。レベル 3 の「識別子付きのルール」の目安 |
| `a.rule_change_commits_window` | 窓内に、指示書・ルール・ルール履歴のパスを変えた既定ブランチのコミット（squash なら PR）の数。`.claude`・`.agents` 等はディレクトリごと対象なので、スキルや設定ファイルだけを変えたコミットも数える。ラベルや Issue フォームは見ない。`git log` が失敗したら `null` と `note` | ルールを継続的に見直しているか（レベル 3 の候補）。上限が高めに出るので、ルールの変更そのものかは中身を見て確かめる。ルール変更を専用のラベルを付けた PR で管理している運用では、`repo:<o/n> is:pr is:merged merged:>=<start> label:<ラベル名>` の件数を所見に添える |

## B. 要件定義

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `b.issue_template_exists` | Issue テンプレート（ルート・`docs/`・`.github/` の `issue_template.md`、`ISSUE_TEMPLATE/`。大文字小文字を問わない）の有無 | レベル 1〜2（`criteria.md` の充足例を参照） |
| `b.pr_template_exists` | PR テンプレート（ルート・`docs/`・`.github/` の `pull_request_template.md`、`PULL_REQUEST_TEMPLATE/`。大文字小文字を問わない）の有無 | レベル 1〜2 |
| `b.issues_open_count` | 未完了 Issue 数（検索 API の `total_count`。上限なし） | 規模の把握 |
| `b.issues_closed_count` | 完了 Issue 数（検索 API の `total_count`。上限なし） | GitHub で要件を管理しているか |

## C. システム設計・アーキテクチャ

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `c.adr_count` | `ADR_DIR` 直下の `.md` 数（README / index / template で始まるものを除く） | レベル 2 |
| `c.adr_duplicates` | ファイル名の最初の数字列（先頭のゼロは無視）を ADR 番号とみなし、重複している番号の一覧。`0003-x.md` と `adr-003-y.md` はどちらも 3 | 空配列が望ましい |
| `c.arch_lint_configured` | 層構造・依存方向の静的検査の設定ファイルの有無 | 設定だけならレベル 2 止まり |
| `c.arch_lint_enforced` | その検査を呼ぶ行が `ENFORCEMENT_FILES` のどこかにあるか | レベル 3 には `true` が要る |

## D. コーディング・開発

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `d.commit_count_total` | 総コミット数 | 規模の把握 |
| `d.commits_window` | 窓内のコミット数。0 のときは `note` に最後のコミットの日付が入る | 活動量 |
| `d.commits_by_month` | 直近 12 か月の月別コミット数 | 活動の推移 |
| `d.pr_commit_ratio_window` | 既定ブランチの first-parent 履歴（窓内）のうち、件名が `(#N)`（squash merge）または `Merge pull request #N`（merge commit）のコミットの割合。窓内にコミットが無ければ `null` で、`note` に理由が入る | PR を経由する運用の度合い。rebase merge だけの運用では低く出る |

## E. テスト・QA

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `e.test_files_count` | 追跡されているテストファイル数（`node_modules`、仮想環境、worktree、ビルド出力を除く） | 規模の把握 |
| `e.test_cases_count` | テストファイル内で `TEST_CASE_REGEX` に一致する行の数 | 規模の把握 |
| `e.coverage_gate_configured` | カバレッジの下限設定（`fail-under`、`coverageThreshold`、JaCoCo の `violationRules`、Kover の `koverVerify` 等）の有無 | レベル 3 の候補 |

## F. デプロイ・リリース

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `f.smoke_steps` | デプロイ系ワークフロー内の検証ステップ（smoke / health / verify / curl）に一致する行の数 | 0 なら F はレベル 3 未達 |
| `f.rollback_doc_present` | デプロイ系ワークフローのどれかに rollback の記載があるか、ロールバック手順のドキュメント（`ROLLBACK_DOC_FILES`）があるか | レベル 3 の候補 |
| `f.deploy_runs` | 窓内のデプロイ系ワークフローの実行結果（ワークフロー別 × conclusion 別の件数） | `success` が無く `skipped` / `action_required` / `failure` ばかりなら「存在のみ」でレベル 2 止まり |

## G. 監視・インシデント対応

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `g.monitoring_configured` | ワークフロー・インフラ定義・スクリプト内の監視ツールへの言及の有無（証拠収集スクリプト自身は除く） | 言及だけなので、実際に運用しているかは別に確認する |
| `g.incident_labeled_issues_count` | 窓内に作られた `incident` / `postmortem` ラベル付き Issue 数（検索 API の上限 1000 件の中から数える） | 障害が GitHub に記録されているか |

## H. データ管理

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `h.data_management_labels_count` | データ管理系ラベル（`DATA_LABELS_REGEX`）の延べ数（上限 1000） | 取り込み・スキーマを管理しているか |
| `h.data_integrity_gate_configured` | 整合性・ドリフト検査（`DATA_GATE_PATTERN`）を呼ぶ行が `ENFORCEMENT_FILES` のどこかにあるか | レベル 3 の候補 |

## I. 開発環境・パイプラインへの AI 組み込み

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `i.tool_integration_files` | AI ツールの共有設定（`.claude/settings.json` / `.cursor` / `.github/copilot-instructions.md` / `.github/instructions` / `.gemini` / `.aider.conf.yml` / `.windsurfrules` / `.clinerules` 等） | レベル 2 |
| `i.local_guardrail_hooks_count` | pre-commit の `repo: local` の数 + `.husky` のフックファイル数 + `lefthook.yml` の有無（1） | ガードレールを機械的に強制しているか（レベル 3） |
| `i.agent_hooks_count` | AI エージェントの設定（`.claude/settings.json`、`.gemini/settings.json`）の `hooks` に登録されたフックの数 | エージェントの操作にガードレールを掛けているか（レベル 3 の候補）。JSON が壊れていれば `null` と `note` |
| `i.agent_permission_denies_count` | `.claude/settings.json` 等の `permissions.deny`（秘密情報の読み取り禁止など）のルール数 | 同上 |

## J. AI 利用ポリシーと機械的強制

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `j.governance_docs_present` | ガイドライン文書（`AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md` / `.github/instructions` / `docs/ai-policy.md` 等）の有無 | レベル 2。中身に AI 利用の制約が書かれているかは人が確かめる |
| `j.dependabot_or_renovate_present` | 依存関係の自動更新設定の有無 | 自動の準拠チェック（レベル 3）の一部 |
| `j.codeql_security_workflow_present` | セキュリティ系ワークフロー（CodeQL / Snyk / Trivy / Semgrep 等）の有無 | 同上 |

## K. 透明性・監査証跡

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `k.coauthored_count` | AI エージェント（`AI_COAUTHOR_REGEX` に一致）の `Co-authored-by` トレーラーを持つコミット数。キーの大文字小文字は区別せず、1 コミットに複数いても 1 と数える | レベル 2 |
| `k.coauthored_by_model` | AI エージェントの `Co-authored-by` の名前別の件数（上位 10） | どのエージェントが関与しているか |
| `k.coauthored_ratio_lower_bound` | `k.coauthored_count / d.commit_count_total`（全履歴） | AI 関与率の**下限値**。トレーラーを付けない運用のコミットは判別できない。歴史の長いリポジトリでは極端に小さく出る |
| `k.coauthored_ratio_window` | 窓内の、マージコミットを除いたコミットのうち、AI エージェントの `Co-authored-by` を持つものの割合。窓内にコミットが無ければ `null` と `note` | 最近の AI 関与率の下限値。squash と merge commit が混在していても比べやすい |

## L. 人間–AI・AI–AI の協働プロトコル

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `l.pr_review_stats_window` | 窓内にマージされた PR の件数・レビュー付き件数・コメント付き件数・平均追加行数（上限 500）。GraphQL が使えないときは REST で PR ごとに取るので、PR が多いと時間がかかる | レビュー工程に AI の出力を通しているか |
| `l.pr_authors_window` | 窓内にマージされた PR の著者別の件数（上限 500）。bot は `app/<name>` | 人間と複数エージェントの関与 |
| `l.ai_pr_stats_window` | 窓内にマージされた PR のうち、AI エージェント（`AI_AGENT_LOGIN_REGEX`）が作った件数 `ai_authored`、AI のレビュアー（`AI_REVIEWER_REGEX`）のレビューが付いた件数 `ai_reviewed`、最初の AI のレビューの後に人が承認した件数 `human_approved_after_ai_review`（上限 500） | `ai_reviewed` はレベル 2（AI の出力をレビューに通す）、`human_approved_after_ai_review` はレベル 4（人と AI の共同監督）の目安。`ai_authored` は D・F の判定にも使う |

## M. 合成ユーザーリサーチ

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `m.user_research_issues_count` | 窓内に作られ、`USER_RESEARCH_REGEX` のキーワードのどれか（GitHub 検索の OR）を含む Issue 数（検索 API の `total_count`） | キーワード検索なので取りこぼしも誤検知もある |
| `m.user_research_labels_count` | リサーチ系ラベルの延べ数（上限 1000） | 探索を Issue 化しているか |

## N. 継続的改善のフィードバックループ

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `n.retro_docs_count` | `DOC_DIRS` 内でふりかえり系キーワードを含むファイル数 | レベル 2 |
| `n.changelog_lines` | `CHANGELOG_FILE` の行数 | 変更を記録しているか |
| `n.retro_prs_window_count` | 窓内にマージされた、タイトルがふりかえり系の PR 数（検索 API の `total_count`） | 改善が PR として出ているか（レベル 3） |

## O. 価値計測

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `o.value_metric_mentions_count` | `DOC_DIRS` 内の Markdown にあるフロー指標（リードタイム・スループット・DORA 指標等）への言及行数 | レベル 1〜2 |
| `o.changelog_measurement_lines_count` | `CHANGELOG_FILE` 内の定量的な効果の記載行数（数値＋単位、短縮・削減等） | 個別の改善を計測しているか（レベル 2） |

## P. ビジョンと適応

| キー | 数えるもの | 目安 |
| --- | --- | --- |
| `p.roadmap_label_count` | ロードマップ・探索系ラベルの延べ数（上限 1000） | レベル 2 |
| `p.adr_recent_count_window` | 窓内に更新された ADR ファイルの数（README / index / template を除く） | 判断を ADR に残しているか（レベル 3） |
