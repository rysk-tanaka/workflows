#!/usr/bin/env bash
set -euo pipefail

# Requires Python 3.11+ (tomllib)
extract_from_pyproject() {
  [ -f pyproject.toml ] || return 1
  python3 - <<'PY'
import tomllib
from pathlib import Path

data = tomllib.loads(Path("pyproject.toml").read_text(encoding="utf-8"))
version = (
    data.get("project", {}).get("version")
    or data.get("tool", {}).get("poetry", {}).get("version")
)
if version:
    print(version)
PY
}

extract_from_package_json() {
  [ -f package.json ] || return 1
  jq -r '.version // empty' package.json
}

extract_from_cargo_toml() {
  [ -f Cargo.toml ] || return 1
  awk '
    /^\[package\]$/ { in_package = 1; next }
    /^\[/ { in_package = 0 }
    in_package && /^version[[:space:]]*=/ {
      version = $0
      sub(/^[^=]*=[[:space:]]*/, "", version)
      gsub(/"/, "", version)
      gsub(/[[:space:]]+$/, "", version)
      print version
      exit
    }
  ' Cargo.toml
}

extract_from_version_file() {
  local target_file="$1"
  [ -f "$target_file" ] || return 1
  head -n 1 "$target_file" | tr -d '\r'
}

detect_source_from_changes() {
  local changed_files
  # Intentional: fall through to file-existence heuristic when git history is unavailable
  # (e.g. shallow clone without GITHUB_SHA). The caller validates the extracted version,
  # so a wrong source pick still fails safely.
  changed_files="$(git show --name-only --pretty='' "$GITHUB_SHA" || true)"

  if echo "$changed_files" | grep -Fxq "pyproject.toml"; then
    echo "pyproject"
    return 0
  fi
  if echo "$changed_files" | grep -Fxq "package.json"; then
    echo "package_json"
    return 0
  fi
  if echo "$changed_files" | grep -Fxq "Cargo.toml"; then
    echo "cargo_toml"
    return 0
  fi
  if echo "$changed_files" | grep -Fxq "VERSION"; then
    echo "version_file:VERSION"
    return 0
  fi
  if echo "$changed_files" | grep -Fxq ".release-version"; then
    echo "version_file:.release-version"
    return 0
  fi

  if [ -f pyproject.toml ]; then
    echo "pyproject"
    return 0
  fi
  if [ -f package.json ]; then
    echo "package_json"
    return 0
  fi
  if [ -f Cargo.toml ]; then
    echo "cargo_toml"
    return 0
  fi
  if [ -f VERSION ]; then
    echo "version_file:VERSION"
    return 0
  fi
  if [ -f .release-version ]; then
    echo "version_file:.release-version"
    return 0
  fi

  return 1
}

version_source="${INPUT_VERSION_SOURCE:-auto}"
version_file="${INPUT_VERSION_FILE:-VERSION}"
version_command="${INPUT_VERSION_COMMAND:-}"
tag_prefix="${INPUT_TAG_PREFIX:-v}"

if [ "$version_source" = "auto" ]; then
  if ! detected="$(detect_source_from_changes)"; then
    echo "Could not detect version source automatically"
    exit 1
  fi
  version_source="${detected%%:*}"
  if [ "$version_source" = "version_file" ] && [ "$detected" != "$version_source" ]; then
    version_file="${detected#*:}"
  fi
fi

case "$version_source" in
  pyproject)
    version="$(extract_from_pyproject || true)"
    ;;
  package_json)
    version="$(extract_from_package_json || true)"
    ;;
  cargo_toml)
    version="$(extract_from_cargo_toml || true)"
    ;;
  version_file)
    if [ ! -f "$version_file" ] && [ -f ".release-version" ]; then
      version_file=".release-version"
    fi
    version="$(extract_from_version_file "$version_file" || true)"
    ;;
  command)
    if [ -z "$version_command" ]; then
      echo "version_command is required when version_source=command"
      exit 1
    fi
    # Intentional: caller controls version_command via workflow input (trusted callers only)
    version="$(bash -c "$version_command" | head -n 1 | tr -d '\r')"
    ;;
  *)
    echo "Unsupported version_source: $version_source"
    exit 1
    ;;
esac

version="${version#"${version%%[![:space:]]*}"}"
version="${version%"${version##*[![:space:]]}"}"

if [ -z "$version" ]; then
  echo "Failed to extract version from source: $version_source"
  exit 1
fi

if [[ "$version" =~ [[:space:]] ]]; then
  echo "Version must not contain whitespace: $version"
  exit 1
fi

tag="${tag_prefix}${version}"

echo "version_source=$version_source" >> "$GITHUB_OUTPUT"
echo "version=$version" >> "$GITHUB_OUTPUT"
echo "tag=$tag" >> "$GITHUB_OUTPUT"
echo "Resolved version $version from $version_source"
