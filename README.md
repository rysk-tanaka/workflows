# workflows

個人プロジェクト向けの再利用可能な GitHub Actions
ワークフローとコンポジットアクション集。

## Reusable Workflows

| Workflow | 説明 |
| --- | --- |
| `release-on-version-change.yml` | バージョン変更を検知し GitHub Release を作成 |
| `claude.yml` | Issue/PR での `@claude` メンションに応答 |
| `claude-code-review.yml` | ラベル付き PR の自動コードレビュー |
| `issue-scan.yml` | Claude による open issue のトリアージ |
| `issue-implement.yml` | Claude による issue の自動実装 |
| `dependabot-scan.yml` | `pnpm audit` で脆弱性を検出し Issue 管理 |

## Composite Actions

| Action | 説明 |
| --- | --- |
| `resolve-version` | package.json / pyproject.toml / Cargo.toml / VERSION からバージョン取得 |
| `release-core` | Git タグと GitHub Release を作成（冪等） |
| `audit-scan` | audit JSON を解析し脆弱性 Issue を管理 |

## 使い方

```yaml
jobs:
  release:
    uses: >-
      rysk-tanaka/workflows/.github/workflows/
      release-on-version-change.yml@main
    secrets: inherit
```

## セットアップ

プライベートリポジトリの場合は
**Settings > Actions > General > Access** で
**「Accessible from repositories owned by the user
'rysk-tanaka'」** を有効にしてください。
