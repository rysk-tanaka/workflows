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

- inputs: `claude_model`, `prompt`, `claude_args_extra`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

#### claude-code-review.yml

- inputs: `claude_model`, `prompt`,
  `claude_args_extra`, `allowed_bots`,
  `use_sticky_comment`, `track_progress`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

#### issue-scan.yml

- inputs: `claude_model`, `max_turns`, `prompt`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

#### issue-implement.yml

- inputs: `package_manager`,
  `claude_args` (required), `prompt` (required),
  `allowed_bots`, `timeout_minutes`
- secrets: `CLAUDE_CODE_OAUTH_TOKEN`

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
