#!/usr/bin/env bash
set -euo pipefail

# Parse pnpm audit JSON and manage GitHub Issues for vulnerabilities.
# Usage: bash audit-scan.sh <audit-result.json>

AUDIT_FILE="${1:?Usage: audit-scan.sh <audit-result.json>}"

if [[ ! -f "$AUDIT_FILE" ]]; then
  echo "::error::File not found: $AUDIT_FILE"
  exit 1
fi

# ---------------------------------------------------------------------------
# Renovate excluded packages (parsed from renovate.json)
# ---------------------------------------------------------------------------
RENOVATE_FILE="renovate.json"
RENOVATE_EXCLUDED=""
if [[ -f "$RENOVATE_FILE" ]]; then
  RENOVATE_EXCLUDED=$(jq -r '
    .packageRules[]
    | select(.enabled == false)
    | .matchDepNames[]?
  ' "$RENOVATE_FILE" 2>/dev/null || true)
fi

is_renovate_excluded() {
  local pkg="$1"
  echo "$RENOVATE_EXCLUDED" | grep -qxF "$pkg"
}

# ---------------------------------------------------------------------------
# pnpm.overrides (parsed from package.json)
# ---------------------------------------------------------------------------
has_override() {
  local pkg="$1"
  jq -e --arg p "$pkg" '.pnpm.overrides[$p] // empty' package.json > /dev/null 2>&1
}

# ---------------------------------------------------------------------------
# Ensure labels exist
# ---------------------------------------------------------------------------
ensure_label() {
  local name="$1" color="$2" description="$3"
  if ! gh label list --limit 500 --json name --jq '.[].name' | grep -qxF "$name"; then
    gh label create "$name" --color "$color" --description "$description"
    echo "Created label: $name"
  fi
}

ensure_label "security" "e11d48" "Security vulnerability"
ensure_label "dependencies" "0075ca" "Dependency updates"

# ---------------------------------------------------------------------------
# Collect advisory GHSA IDs from audit result
# pnpm audit --json uses the npm v6 advisory format (.advisories key) as of
# pnpm v10. The workflow's "Verify audit output" step will fail fast if this
# format changes in a future pnpm version.
# ---------------------------------------------------------------------------
ADVISORY_KEYS=$(jq -r '.advisories | keys[]' "$AUDIT_FILE" 2>/dev/null || true)
GHSA_IDS=""

if [[ -n "$ADVISORY_KEYS" ]]; then
  GHSA_IDS=$(jq -r '.advisories[].github_advisory_id // empty' "$AUDIT_FILE")
fi

# ---------------------------------------------------------------------------
# Create Issues for each advisory
# ---------------------------------------------------------------------------
if [[ -z "$ADVISORY_KEYS" ]]; then
  echo "No advisories found."
else
  while IFS= read -r key; do
    [[ -z "$key" ]] && continue
    module_name=$(jq -r --arg k "$key" '.advisories[$k].module_name // "unknown"' "$AUDIT_FILE")
    severity=$(jq -r --arg k "$key" '.advisories[$k].severity // "unknown"' "$AUDIT_FILE")
    ghsa_id=$(jq -r --arg k "$key" '.advisories[$k].github_advisory_id // empty' "$AUDIT_FILE")
    if [[ -z "$ghsa_id" ]]; then
      echo "Skipping advisory $key (no GHSA ID)"
      continue
    fi
    # These fields are always present in pnpm audit advisories (verified with
    # pnpm v10). The // empty fallbacks are purely defensive; if patched_versions
    # were empty, the recommendation text would be incomplete but the Issue would
    # still be created with the Advisory URL for reference.
    url=$(jq -r --arg k "$key" '.advisories[$k].url // empty' "$AUDIT_FILE")
    title_text=$(jq -r --arg k "$key" '.advisories[$k].title // empty' "$AUDIT_FILE")
    vulnerable_versions=$(jq -r --arg k "$key" '.advisories[$k].vulnerable_versions // empty' "$AUDIT_FILE")
    patched_versions=$(jq -r --arg k "$key" '.advisories[$k].patched_versions // empty' "$AUDIT_FILE")

    # Dependency chains from findings[].paths
    dep_paths=$(jq -r --arg k "$key" '
      .advisories[$k].findings[]?.paths[]?
    ' "$AUDIT_FILE" | sort -u)

    # Determine direct vs indirect dependency.
    # pnpm audit --json paths use ">" delimiter with "." as project root:
    #   direct:   ".>package"          (2 segments)
    #   indirect: ".>root>...>package" (3+ segments, root dep = 2nd segment)
    # Verified with pnpm v10 on this project.
    is_direct=false
    root_deps=""
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      segment_count=$(echo "$path" | tr '>' '\n' | wc -l | tr -d ' ')
      if [[ "$segment_count" -le 2 ]]; then
        is_direct=true
      else
        root=$(echo "$path" | cut -d'>' -f2)
        root_deps="$root_deps $root"
      fi
    done <<< "$dep_paths"
    root_deps=$(echo "$root_deps" | tr ' ' '\n' | sort -u | tr '\n' ' ' | xargs)

    # Decide recommendation
    recommendation=""
    if [[ "$is_direct" == "true" ]]; then
      recommendation="直接依存のため、\`package.json\` の \`${module_name}\` のバージョンを \`${patched_versions}\` 以上に更新してください。"
    else
      renovate_excluded_root=false
      for root in $root_deps; do
        if is_renovate_excluded "$root"; then
          renovate_excluded_root=true
          break
        fi
      done

      # Convert a simple ">=X.Y.Z" (major>=1) to "^X.Y.Z" to limit overrides
      # within the current major. For compound ranges (e.g. ">=1.2.3 <2.0.0
      # || >=3.0.0") or 0.x packages, keep patched_versions as-is to avoid
      # generating invalid semver or overly narrow ranges.
      override_range="$patched_versions"
      if [[ "$patched_versions" =~ ^">="([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        major="${BASH_REMATCH[1]}"
        if (( major >= 1 )); then
          override_range="^${BASH_REMATCH[1]}.${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
        fi
      fi

      if [[ "$renovate_excluded_root" == "true" ]]; then
        if has_override "$module_name"; then
          recommendation="既に \`pnpm.overrides\` にエントリがあります。\`package.json\` の \`pnpm.overrides[\"${module_name}\"]\` のバージョン範囲を \`${override_range}\` に更新してください。"
        else
          recommendation="ルート依存（${root_deps}）が Renovate の自動更新対象外のため、\`pnpm.overrides\` に \`\"${module_name}\": \"${override_range}\"\` を追加してください。"
        fi
      else
        recommendation="Renovate による自動更新で修正される見込みです。ルート依存（${root_deps}）の更新 PR をお待ちください。"
      fi
    fi

    # Format dependency paths for issue body
    dep_paths_formatted=""
    while IFS= read -r path; do
      [[ -z "$path" ]] && continue
      dep_paths_formatted="${dep_paths_formatted}\`${path}\`
"
    done <<< "$dep_paths"

    issue_title="security(deps): ${module_name} — ${severity} (${ghsa_id})"

    # Check for existing open issue with same title
    existing=$(gh issue list --label security --state open --limit 500 --search "in:title ${ghsa_id}" --json title --jq '.[].title')
    if echo "$existing" | grep -qF "$issue_title"; then
      echo "Issue already exists: $issue_title"
      continue
    fi

    # Create issue body
    body=$(cat <<EOF
## 概要

- 深刻度: ${severity}
- パッケージ: ${module_name} ${vulnerable_versions}
- 修正バージョン: ${patched_versions}
- Advisory: ${url}

## 脆弱性の説明

${title_text}

## 依存チェーン

<details>
<summary>依存パス</summary>

$(printf '%s' "$dep_paths_formatted")

</details>

## 推奨対応

${recommendation}
EOF
)

    gh issue create \
      --title "$issue_title" \
      --body "$body" \
      --label "security" \
      --label "dependencies"

    echo "Created issue: $issue_title"
  done <<< "$ADVISORY_KEYS"
fi

# ---------------------------------------------------------------------------
# Close resolved Issues
# ---------------------------------------------------------------------------
echo ""
echo "Checking for resolved issues to close..."

open_issues=$(gh issue list --label security --label dependencies --state open --limit 500 --json number,title --jq '.[] | "\(.number)\t\(.title)"')

if [[ -z "$open_issues" ]]; then
  echo "No open security issues found."
  exit 0
fi

while IFS=$'\t' read -r issue_number issue_title; do
  [[ -z "$issue_number" ]] && continue

  # Extract GHSA ID from title: "security(deps): ... (GHSA-xxxx-xxxx-xxxx)"
  issue_ghsa=$(echo "$issue_title" | grep -oE 'GHSA-[a-z0-9]+-[a-z0-9]+-[a-z0-9]+' || true)

  if [[ -z "$issue_ghsa" ]]; then
    echo "Skipping issue #${issue_number} (no GHSA ID in title)"
    continue
  fi

  # Check if this GHSA ID still exists in audit results
  if echo "$GHSA_IDS" | grep -qxF "$issue_ghsa"; then
    echo "Issue #${issue_number} still active: ${issue_ghsa}"
  else
    echo "Closing resolved issue #${issue_number}: ${issue_title}"
    gh issue close "$issue_number" \
      --comment "pnpm audit で検出されなくなったため、この Issue をクローズします。"
  fi
done <<< "$open_issues"
