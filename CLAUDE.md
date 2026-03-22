# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when
working with code in this repository.

## Overview

Reusable GitHub Actions workflows and composite actions for
personal projects. Other repositories consume these via
`uses: rysk-tanaka/workflows/.github/workflows/<name>@main`.

## Architecture

### Reusable Workflows (`.github/workflows/`)

All workflows use `on: workflow_call` only — they are called
from other repos, not triggered directly.

- **release-on-version-change.yml** — Detects version changes
  via `resolve-version` action, then creates a release via
  `release-core` action
- **claude.yml** — Responds to `@claude` mentions using
  `anthropics/claude-code-action`
- **claude-code-review.yml** — Automated PR review with
  3-level severity (critical/warning/info) and inline comments
- **issue-scan.yml** — Triages open issues by difficulty
  (easy/medium/hard), auto-labels
- **issue-implement.yml** — Auto-implements
  `claude-implement` labeled issues, creates PRs
- **dependabot-scan.yml** — Runs `pnpm audit`,
  creates/closes GitHub Issues per vulnerability

### Composite Actions (`.github/actions/`)

- **resolve-version** — Extracts version from
  package.json / pyproject.toml / Cargo.toml / VERSION file /
  custom command. Shell script `resolve-version.sh` does the
  actual parsing.
- **release-core** — Idempotent git tag + GitHub Release
  creation. Skips if tag already exists.
- **audit-scan** — Parses pnpm audit JSON, manages
  vulnerability issues. Shell script `audit-scan.sh` handles
  GHSA-based dedup and Renovate override suggestions.

### Key Design Decisions

- All Claude-powered workflows prompt in Japanese
- `issue-implement.yml` cannot modify `.github/workflows/`
  files (GitHub App token lacks `workflows` permission), so
  workflow changes are rated `difficulty/hard`
- Issue labels are applied sequentially (not simultaneously)
  to avoid concurrency cancellation of `issue-implement`
  triggers
- Release workflow is idempotent — safe to re-run on same
  version

## Validation

No build, lint, or test commands exist. Validate workflow
syntax with:

```bash
# Check YAML syntax
gh workflow view <workflow-file> --repo rysk-tanaka/workflows

# List recent runs
gh run list --repo rysk-tanaka/workflows
```

## Conventions

- Action versions are pinned to full commit SHA with version
  comment (e.g., `actions/checkout@<sha> # v6.0.2`)
- Workflow prompts and issue comments are in Japanese
- Commit messages in English, following Conventional Commits
