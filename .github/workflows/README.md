# Reusable Workflows 一覧

このディレクトリにある reusable workflow を
用途別に整理した一覧です。

## リリース

| Workflow | 主目的 | 主要 inputs | secrets |
| --- | --- | --- | --- |
| [release-on-version-change.yml] | バージョン変更検知 → タグ・Release 作成 | `version_source`, `tag_prefix`, `force_released_output` | なし（`secrets: inherit` で可） |

## Claude 連携

| Workflow | 主目的 |
| --- | --- |
| [claude.yml] | `@claude` メンションへの応答 |
| [claude-code-review.yml] | ラベルトリガーの自動コードレビュー |
| [issue-scan.yml] | open issue のトリアージ（難易度判定・ラベル付与） |
| [issue-implement.yml] | Issue の自動実装 → PR 作成 |

### 各ワークフローの詳細

#### claude.yml

- inputs: `claude_model`, `prompt`, `claude_args_extra`,
  `include_comments_by_actor`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

#### claude-code-review.yml

- inputs: `claude_model`, `prompt`,
  `claude_args_extra`, `allowed_bots`,
  `use_sticky_comment`, `track_progress`,
  `include_comments_by_actor`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

#### issue-scan.yml

- inputs: `claude_model`, `max_turns`, `prompt`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`
- デフォルトの prompt はリポジトリオーナーが作成した issue のみを対象にする

#### issue-implement.yml

- inputs: `package_manager`,
  `claude_args` (required), `prompt` (required),
  `allowed_bots`, `timeout_minutes`, `subprocess_env_scrub`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`
- issue の `author_association` が `OWNER` / `COLLABORATOR` のときのみ実行する
  （それ以外はジョブをスキップ）

## 依存管理

| Workflow | 主目的 | 主要 inputs | secrets |
| --- | --- | --- | --- |
| [dependabot-scan.yml] | `pnpm audit` で脆弱性を検出し Issue 起票・クローズ | `node_version`, `package_manager` | なし |

## 静的解析

| Workflow | 主目的 | 備考 |
| --- | --- | --- |
| [workflow-lint.yml] | actionlint + zizmor によるワークフロー構文・セキュリティチェック | `on: push` / `on: pull_request`（reusable ではない） |

## Composite Actions

Workflow 内部で使用する composite action
（`../.github/actions/` 配下）。

| Action | 主目的 | 利用元 |
| --- | --- | --- |
| [resolve-version] | バージョン検出 | `release-on-version-change.yml` |
| [release-core] | タグ・Release 生成（冪等） | `release-on-version-change.yml` |
| [audit-scan] | audit JSON 解析・Issue 管理 | `dependabot-scan.yml` |

## Caller 側の設計指針

### permissions

Reusable workflow の `permissions` は caller 側と
交差（AND）されるため、caller 側にも明示的に
指定が必要。

```yaml
jobs:
  claude:
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write  # claude-code-action の OIDC に必須
    uses: >-
      rysk-tanaka/workflows/.github/workflows/
      claude.yml@main
```

### secrets

`secrets: inherit` ではなく明示的に渡す
（可読性・安全性）。

```yaml
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: >-
        ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### トリガーと if 条件

実トリガー（`issue_comment`, `pull_request`,
`schedule` 等）と `if` 条件は caller 側に配置する。
Reusable workflow は `workflow_call` のみ受け付ける。

### issue-implement の claude_args / prompt

`--allowed-tools` のパターンマッチが厳密で
動的構築のバグリスクが高いため、caller から全文指定する
設計。reusable workflow は骨格
（PR ガード・セットアップ・git identity・post-report）
のみ提供する。

## Claude ワークフローのセキュリティ

### Claude に渡るコメント

claude-code-action は、`@claude` でメンションした人やレビューを起動した人に
書き込み権限があるかを確かめる。ただし確かめるのはその人だけで、
同じ Issue / PR に第三者が書いたコメントも、そのままでは Claude への入力に含まれる。

`claude.yml` と `claude-code-review.yml` は `include_comments_by_actor` で、
Claude に渡すコメントの投稿者を絞る。

- 既定（空文字）は、リポジトリのオーナーと bot（`*[bot]`）だけ
- ほかの人のコメントも渡したい場合は、`rysk-tanaka,someone,*[bot]` のように全員を並べて指定する。
  パターンは完全一致と `*[bot]` だけで、`*` は使えない
- 絞れるのはコメント・レビュー・インラインコメントで、Issue / PR の本文は絞れない。
  第三者が立てた Issue や PR で `@claude` を使うときは、本文を先に確認する

### issue-implement の `gh issue view`

Agent Mode で動くため、Issue のコメントは自動では渡らない。
ただし caller の `--allowed-tools` に `Bash(gh issue view *)` があると、
`--comments` を付けて第三者のコメントを読んだり、ほかの Issue を読んだりできる。
caller では Issue 番号まで含めた完全一致にする。

```yaml
claude_args: '... --allowed-tools "...,Bash(gh issue view ${{ github.event.issue.number }}),..."'
```

### ビルド時に実行されるコード

issue-implement は Claude のトークンと `contents: write` の `GITHUB_TOKEN` を持ったまま、
`cargo build` や `pnpm install` を実行する。
依存に悪意のある `build.rs` や install スクリプトが入ると、次のものを読まれるおそれがある。

| 対象 | 置き場所 | 有効期間 |
| --- | --- | --- |
| `CLAUDE_CODE_OAUTH_TOKEN` | Claude の Bash サブプロセスの環境変数 | 発行から 1 年 |
| `GITHUB_TOKEN` | `.git/config`（`persist-credentials: true`） | ジョブの終了まで |

いまの対策は次のとおり。

- ロックファイルに固定した版を使い、Renovate と pnpm の `minimumReleaseAge` で公開直後の版を避ける
- main は ruleset で直接 push を禁止しているので、`GITHUB_TOKEN` を盗まれても main は書き換えられない
- Claude が新しい依存を足す PR は、マージ前に追加されたクレート・パッケージを確認する

`CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` にすると、サブプロセスから Anthropic のトークンなどを消せる。
ただし GitHub のトークンは残り、Linux では Bash がサンドボックス内で動くようになる。
issue-implement では `subprocess_env_scrub: true` で有効にできるが、
`cargo build` や `git push` への影響を確かめている段階なので、既定はオフにしている。

## claude-code-action の権限メモ

| 操作 | 必要な権限 |
| --- | --- |
| `use_sticky_comment: true` | `issues: write` |
| PR review / インラインコメント | `pull-requests: write` |
| コードの読み取り（checkout） | `contents: read` |
| ファイル編集・push | `contents: write` |
| OIDC トークン取得（必須） | `id-token: write` |

<!-- リンク定義 -->
[release-on-version-change.yml]: ./release-on-version-change.yml
[claude.yml]: ./claude.yml
[claude-code-review.yml]: ./claude-code-review.yml
[issue-scan.yml]: ./issue-scan.yml
[issue-implement.yml]: ./issue-implement.yml
[dependabot-scan.yml]: ./dependabot-scan.yml
[workflow-lint.yml]: ./workflow-lint.yml
[resolve-version]: ../actions/resolve-version/
[release-core]: ../actions/release-core/
[audit-scan]: ../actions/audit-scan/
