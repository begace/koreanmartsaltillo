#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHANNEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"

usage() {
  cat <<'EOF'
Usage:
  prepare-release.sh --version v1.1.5 --version-code 7 --helper-version-code 1 \
    --app /path/to/app.apk \
    --helper /path/to/updater.apk --output /path/outside/update-channel/release

Creates, outside the public staging tree:
  POS-Local-MX.apk
  POS-Update-Helper.apk
  SHA256SUMS.txt
EOF
}

VERSION=""
VERSION_CODE=""
HELPER_VERSION_CODE=""
APP_PATH=""
HELPER_PATH=""
OUTPUT_DIR=""

while (($#)); do
  case "$1" in
    --version) VERSION="${2:-}"; shift 2 ;;
    --version-code) VERSION_CODE="${2:-}"; shift 2 ;;
    --helper-version-code) HELPER_VERSION_CODE="${2:-}"; shift 2 ;;
    --app) APP_PATH="${2:-}"; shift 2 ;;
    --helper) HELPER_PATH="${2:-}"; shift 2 ;;
    --output) OUTPUT_DIR="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$VERSION" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'ERROR: --version must look like v1.1.5.\n' >&2; exit 2; }
[[ "$VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: --version-code must be positive.\n' >&2; exit 2; }
[[ "$HELPER_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: --helper-version-code must be positive.\n' >&2; exit 2; }
[[ -f "$APP_PATH" ]] || { printf 'ERROR: POS APK not found: %s\n' "$APP_PATH" >&2; exit 2; }
[[ -f "$HELPER_PATH" ]] || { printf 'ERROR: updater APK not found: %s\n' "$HELPER_PATH" >&2; exit 2; }
[[ -n "$OUTPUT_DIR" ]] || { printf 'ERROR: --output is required.\n' >&2; exit 2; }

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$(basename "$APP_PATH")"
HELPER_PATH="$(cd "$(dirname "$HELPER_PATH")" && pwd -P)/$(basename "$HELPER_PATH")"
mkdir -p "$OUTPUT_DIR"
OUTPUT_DIR="$(cd "$OUTPUT_DIR" && pwd -P)"

case "$APP_PATH" in "$CHANNEL_ROOT"/*) printf 'ERROR: input APK must remain outside update-channel.\n' >&2; exit 1;; esac
case "$HELPER_PATH" in "$CHANNEL_ROOT"/*) printf 'ERROR: input APK must remain outside update-channel.\n' >&2; exit 1;; esac
case "$OUTPUT_DIR" in "$CHANNEL_ROOT"|"$CHANNEL_ROOT"/*) printf 'ERROR: release output must remain outside update-channel.\n' >&2; exit 1;; esac

if find "$OUTPUT_DIR" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
  printf 'ERROR: output directory must be empty: %s\n' "$OUTPUT_DIR" >&2
  exit 1
fi

unzip -tqq "$APP_PATH"
unzip -tqq "$HELPER_PATH"

"$SCRIPT_DIR/verify-release-apks.sh" \
  --version-name "${VERSION#v}" \
  --version-code "$VERSION_CODE" \
  --helper-version-code "$HELPER_VERSION_CODE" \
  --app "$APP_PATH" \
  --helper "$HELPER_PATH"

APP_ENTRIES="$(unzip -Z1 "$APP_PATH")"
if grep -Eiq '(^|/)initial_products\.csv$' <<< "$APP_ENTRIES"; then
  printf 'ERROR: POS APK contains initial_products.csv; do not publish a store catalog.\n' >&2
  exit 1
fi

cp "$APP_PATH" "$OUTPUT_DIR/POS-Local-MX.apk"
cp "$HELPER_PATH" "$OUTPUT_DIR/POS-Update-Helper.apk"

(
  cd "$OUTPUT_DIR"
  shasum -a 256 POS-Local-MX.apk POS-Update-Helper.apk > SHA256SUMS.txt
  shasum -a 256 -c SHA256SUMS.txt
)

printf 'Release assets prepared for %s in %s\n' "$VERSION" "$OUTPUT_DIR"
