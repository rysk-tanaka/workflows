# Reusable Workflows 一覧

このディレクトリにある reusable workflow を用途別に整理した一覧です。

## リリース

| Workflow | 主目的 | 主要 inputs | secrets |
| --- | --- | --- | --- |
| [release-on-version-change.yml](./release-on-version-change.yml) | バージョン変更検知 → タグ・Release 作成 | `version_source`, `tag_prefix`, `force_released_output` | なし（`secrets: inherit` で可） |

## Claude 連携

| Workflow | 主目的 | 主要 inputs | secrets |
| --- | --- | --- | --- |
| [claude.yml](./claude.yml) | `@claude` メンションへの応答 | `claude_model`, `prompt`, `claude_args_extra` | `CLAUDE_CODE_OAUTH_TOKEN` |
| [claude-code-review.yml](./claude-code-review.yml) | ラベルトリガーの自動コードレビュー | `claude_model`, `prompt`, `claude_args_extra`, `allowed_bots`, `use_sticky_comment`, `track_progress` | `CLAUDE_CODE_OAUTH_TOKEN` |
| [issue-scan.yml](./issue-scan.yml) | open issue のトリアージ（難易度判定・ラベル付与） | `claude_model`, `max_turns`, `prompt` | `CLAUDE_CODE_OAUTH_TOKEN` |
| [issue-implement.yml](./issue-implement.yml) | Issue の自動実装 → PR 作成 | `package_manager`, `claude_args` (required), `prompt` (required), `allowed_bots`, `timeout_minutes` | `CLAUDE_CODE_OAUTH_TOKEN` |

## 依存管理

| Workflow | 主目的 | 主要 inputs | secrets |
| --- | --- | --- | --- |
| [dependabot-scan.yml](./dependabot-scan.yml) | `pnpm audit` で脆弱性を検出し Issue 起票・クローズ | `node_version`, `package_manager` | なし |

## Composite Actions

Workflow 内部で使用する composite action（`../.github/actions/` 配下）。

| Action | 主目的 | 利用元 |
| --- | --- | --- |
| [resolve-version](../actions/resolve-version/) | package.json / pyproject.toml / Cargo.toml / VERSION からバージョン検出 | `release-on-version-change.yml` |
| [release-core](../actions/release-core/) | タグ作成と GitHub Release 生成（冪等） | `release-on-version-change.yml` |
| [audit-scan](../actions/audit-scan/) | audit JSON を解析し GitHub Issue を管理 | `dependabot-scan.yml` |

## Caller 側の設計指針

### permissions

Reusable workflow の `permissions` は caller 側と交差（AND）されるため、caller 側にも明示的に指定が必要。

```yaml
jobs:
  claude:
    permissions:
      contents: write
      pull-requests: write
      issues: write
      id-token: write    # claude-code-action の OIDC に必須
    uses: rysk-tanaka/workflows/.github/workflows/claude.yml@main
```

### secrets

`secrets: inherit` ではなく明示的に渡す（可読性・安全性）。

```yaml
    secrets:
      CLAUDE_CODE_OAUTH_TOKEN: ${{ secrets.CLAUDE_CODE_OAUTH_TOKEN }}
```

### トリガーと if 条件

実トリガー（`issue_comment`, `pull_request`, `schedule` 等）と `if` 条件は caller 側に配置する。Reusable workflow は `workflow_call` のみ受け付ける。

### issue-implement の claude_args / prompt

`--allowed-tools` のパターンマッチが厳密で動的構築のバグリスクが高いため、caller から全文指定する設計。reusable workflow は骨格（PR ガード・セットアップ・git identity・post-report）のみ提供する。

## claude-code-action の権限メモ

| 操作 | 必要な権限 |
| --- | --- |
| `use_sticky_comment: true`（PR へのサマリーコメント投稿） | `issues: write` |
| PR review / インラインコメント投稿 | `pull-requests: write` |
| コードの読み取り（checkout） | `contents: read` |
| ファイル編集・push | `contents: write` |
| OIDC トークン取得（必須） | `id-token: write` |
