#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHANNEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

required_files=(
  ".gitignore"
  "README.md"
  "docs/.nojekyll"
  "docs/index.html"
  "docs/privacy.html"
  "docs/styles.css"
  "release-notes/v1.1.5.md"
  "templates/latest.json.template"
  "scripts/check-public-tree.sh"
  "scripts/prepare-release.sh"
  "scripts/generate-update-manifest.sh"
  "scripts/verify-release-apks.sh"
)

for relative_path in "${required_files[@]}"; do
  if [[ ! -f "$CHANNEL_ROOT/$relative_path" ]]; then
    printf 'ERROR: required public file is missing: %s\n' "$relative_path" >&2
    exit 1
  fi
done

forbidden_path_pattern='(^|/)(precio|initial_products)([^/]*)$|(^|/)(keystore|local)\.properties$|\.(apk|aab|jks|keystore|p12|pfx|pem|key|csv|xlsx|xls|posbackup|sqlite|db)$'

while IFS= read -r -d '' file_path; do
  relative_path="${file_path#"$CHANNEL_ROOT/"}"
  if printf '%s\n' "$relative_path" | grep -Eiq "$forbidden_path_pattern"; then
    printf 'ERROR: forbidden release material is inside the public tree: %s\n' "$relative_path" >&2
    exit 1
  fi
done < <(find "$CHANNEL_ROOT" -type f -print0)

if git -C "$CHANNEL_ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  while IFS= read -r tracked_path; do
    if printf '%s\n' "$tracked_path" | grep -Eiq "$forbidden_path_pattern"; then
      printf 'ERROR: forbidden release material is tracked by Git: %s\n' "$tracked_path" >&2
      exit 1
    fi
  done < <(git -C "$CHANNEL_ROOT" ls-files)
fi

printf 'Public-tree check passed: %s\n' "$CHANNEL_ROOT"
