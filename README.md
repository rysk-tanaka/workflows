# workflows

Reusable GitHub Actions workflows and composite actions for personal projects.

## Reusable Workflows

| Workflow | Description |
| --- | --- |
| `release-on-version-change.yml` | Detect version changes and create GitHub Release |
| `claude.yml` | Respond to `@claude` mentions on issues/PRs |
| `claude-code-review.yml` | Automated code review on labeled PRs |
| `issue-scan.yml` | Triage open issues with Claude |
| `issue-implement.yml` | Auto-implement issues with Claude |
| `dependabot-scan.yml` | Run `pnpm audit` and manage vulnerability issues |

## Composite Actions

| Action | Description |
| --- | --- |
| `resolve-version` | Resolve version from package.json / pyproject.toml / Cargo.toml / VERSION |
| `release-core` | Create git tag and GitHub Release (idempotent) |
| `audit-scan` | Parse audit JSON and manage GitHub Issues for vulnerabilities |

## Usage

```yaml
jobs:
  release:
    uses: rysk-tanaka/workflows/.github/workflows/release-on-version-change.yml@main
    secrets: inherit
```

## Setup

For private repos, go to **Settings > Actions > General > Access** and enable **"Accessible from repositories owned by the user 'rysk-tanaka'"**.
