#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHANNEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_ROOT="$(cd "$CHANNEL_ROOT/../.." && pwd -P)"
DEFAULT_PRIVATE_KEY="$PROJECT_ROOT/release-signing/update-manifest-private.pem"
PINNED_PUBLIC_KEY="$PROJECT_ROOT/release-signing/update-manifest-public.der"
PINNED_PUBLIC_KEY_SHA256="5a09306c2f87c79fe5f7c4e0bc40d3e79f37a28d96bf8cb6388d5ce6498e2571"

usage() {
  cat <<EOF
Usage:
  generate-update-manifest.sh --version-name 1.1.6 --version-code 8 \\
    --minimum-supported-version-code 7 --helper-version-code 2 \\
    --app /outside/POS-Local-MX.apk \\
    --helper /outside/POS-Update-Helper.apk [options]

Options:
  --private-key PATH  Default: $DEFAULT_PRIVATE_KEY
  --pos-download-url URL     Default: version-specific GitHub release asset
  --helper-download-url URL  Default: version-specific GitHub release asset
  --allow-bundled-catalog    Explicitly permit the reviewed 2026-10-20 catalog
  --notes-es TEXT
  --notes-ko TEXT

Writes docs/latest.json and docs/latest.json.sig. The RSA private key is read in
place and is never copied into update-channel.
EOF
}

VERSION_NAME=""
VERSION_CODE=""
MINIMUM_SUPPORTED_VERSION_CODE=""
HELPER_VERSION_CODE=""
APP_PATH=""
HELPER_PATH=""
PRIVATE_KEY_PATH="$DEFAULT_PRIVATE_KEY"
NOTES_ES=""
NOTES_KO=""
POS_DOWNLOAD_URL=""
HELPER_DOWNLOAD_URL=""
ALLOW_BUNDLED_CATALOG=false

while (($#)); do
  case "$1" in
    --version-name) VERSION_NAME="${2:-}"; shift 2 ;;
    --version-code) VERSION_CODE="${2:-}"; shift 2 ;;
    --minimum-supported-version-code) MINIMUM_SUPPORTED_VERSION_CODE="${2:-}"; shift 2 ;;
    --helper-version-code) HELPER_VERSION_CODE="${2:-}"; shift 2 ;;
    --app) APP_PATH="${2:-}"; shift 2 ;;
    --helper) HELPER_PATH="${2:-}"; shift 2 ;;
    --private-key) PRIVATE_KEY_PATH="${2:-}"; shift 2 ;;
    --notes-es) NOTES_ES="${2:-}"; shift 2 ;;
    --notes-ko) NOTES_KO="${2:-}"; shift 2 ;;
    --pos-download-url) POS_DOWNLOAD_URL="${2:-}"; shift 2 ;;
    --helper-download-url) HELPER_DOWNLOAD_URL="${2:-}"; shift 2 ;;
    --allow-bundled-catalog) ALLOW_BUNDLED_CATALOG=true; shift ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'ERROR: invalid --version-name.\n' >&2; exit 2; }
[[ "$VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: --version-code must be positive.\n' >&2; exit 2; }
[[ "$MINIMUM_SUPPORTED_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: minimum supported version code must be positive.\n' >&2; exit 2; }
[[ "$HELPER_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: helper version code must be positive.\n' >&2; exit 2; }
(( MINIMUM_SUPPORTED_VERSION_CODE < VERSION_CODE )) || { printf 'ERROR: minimum version must be lower than the published version.\n' >&2; exit 2; }
[[ -f "$APP_PATH" ]] || { printf 'ERROR: POS APK not found.\n' >&2; exit 2; }
[[ -f "$HELPER_PATH" ]] || { printf 'ERROR: updater APK not found.\n' >&2; exit 2; }
[[ -f "$PRIVATE_KEY_PATH" ]] || { printf 'ERROR: RSA private key not found: %s\n' "$PRIVATE_KEY_PATH" >&2; exit 2; }
[[ -f "$PINNED_PUBLIC_KEY" ]] || { printf 'ERROR: pinned RSA public key not found.\n' >&2; exit 2; }
command -v jq >/dev/null || { printf 'ERROR: jq is required.\n' >&2; exit 1; }
command -v openssl >/dev/null || { printf 'ERROR: openssl is required.\n' >&2; exit 1; }

DOWNLOAD_BASE="https://github.com/begace/koreanmartsaltillo/releases/download/v$VERSION_NAME"
POS_DOWNLOAD_URL="${POS_DOWNLOAD_URL:-$DOWNLOAD_BASE/POS-Local-MX.apk}"
HELPER_DOWNLOAD_URL="${HELPER_DOWNLOAD_URL:-$DOWNLOAD_BASE/POS-Update-Helper.apk}"
validate_download_url() {
  local url="$1" asset="$2"
  local drive_endpoint='https://(drive\.google\.com/uc|drive\.usercontent\.google\.com/download)'
  local drive_id='[A-Za-z0-9_-]{10,200}'
  if [[ "$url" == "$DOWNLOAD_BASE/$asset" ]] ||
     [[ "$url" =~ ^${drive_endpoint}\?id=${drive_id}\&export=download$ ]] ||
     [[ "$url" =~ ^${drive_endpoint}\?export=download\&id=${drive_id}$ ]]; then
    return
  fi
  # Drive executable downloads can require this fixed public-download flag.
  # Only usercontent /download may carry confirm=t; no arbitrary confirmation
  # token, page-provided HTML action, or extra query parameter is accepted.
  local confirmed_endpoint='https://drive\.usercontent\.google\.com/download'
  local confirmed_query
  for confirmed_query in \
    "id=$drive_id&export=download&confirm=t" \
    "id=$drive_id&confirm=t&export=download" \
    "export=download&id=$drive_id&confirm=t" \
    "export=download&confirm=t&id=$drive_id" \
    "confirm=t&id=$drive_id&export=download" \
    "confirm=t&export=download&id=$drive_id"; do
    if [[ "$url" =~ ^${confirmed_endpoint}\?${confirmed_query}$ ]]; then
      return
    fi
  done
  printf 'ERROR: invalid %s URL. Use this version\x27s GitHub asset or canonical HTTPS Google Drive id/export=download; only usercontent /download may additionally use confirm=t.\n' "$asset" >&2
  exit 2
}
validate_download_url "$POS_DOWNLOAD_URL" 'POS-Local-MX.apk'
validate_download_url "$HELPER_DOWNLOAD_URL" 'POS-Update-Helper.apk'

APP_PATH="$(cd "$(dirname "$APP_PATH")" && pwd -P)/$(basename "$APP_PATH")"
HELPER_PATH="$(cd "$(dirname "$HELPER_PATH")" && pwd -P)/$(basename "$HELPER_PATH")"
PRIVATE_KEY_PATH="$(cd "$(dirname "$PRIVATE_KEY_PATH")" && pwd -P)/$(basename "$PRIVATE_KEY_PATH")"

[[ "$(basename "$APP_PATH")" == "POS-Local-MX.apk" ]] || { printf 'ERROR: POS asset name must be POS-Local-MX.apk.\n' >&2; exit 1; }
[[ "$(basename "$HELPER_PATH")" == "POS-Update-Helper.apk" ]] || { printf 'ERROR: updater asset name must be POS-Update-Helper.apk.\n' >&2; exit 1; }
for external_path in "$APP_PATH" "$HELPER_PATH" "$PRIVATE_KEY_PATH"; do
  case "$external_path" in "$CHANNEL_ROOT"|"$CHANNEL_ROOT"/*) printf 'ERROR: APKs and private keys must remain outside update-channel.\n' >&2; exit 1;; esac
done

unzip -tqq "$APP_PATH"
unzip -tqq "$HELPER_PATH"
VERIFY_ARGS=(
  --version-name "$VERSION_NAME" \
  --version-code "$VERSION_CODE" \
  --helper-version-code "$HELPER_VERSION_CODE" \
  --app "$APP_PATH" \
  --helper "$HELPER_PATH"
)
if [[ "$ALLOW_BUNDLED_CATALOG" == true ]]; then
  VERIFY_ARGS+=(--allow-bundled-catalog)
fi
"$SCRIPT_DIR/verify-release-apks.sh" "${VERIFY_ARGS[@]}"
openssl pkey -in "$PRIVATE_KEY_PATH" -noout -check >/dev/null
PRIVATE_PUBLIC_SHA256="$(openssl pkey -in "$PRIVATE_KEY_PATH" -pubout -outform DER | shasum -a 256 | awk '{print $1}')"
PINNED_DER_SHA256="$(shasum -a 256 "$PINNED_PUBLIC_KEY" | awk '{print $1}')"
if [[ "$PRIVATE_PUBLIC_SHA256" != "$PINNED_PUBLIC_KEY_SHA256" || "$PINNED_DER_SHA256" != "$PINNED_PUBLIC_KEY_SHA256" ]]; then
  printf 'ERROR: update manifest key does not match the public key pinned in the updater.\n' >&2
  exit 1
fi

file_size() {
  if stat -f '%z' "$1" >/dev/null 2>&1; then stat -f '%z' "$1"; else stat -c '%s' "$1"; fi
}

POS_SHA256="$(shasum -a 256 "$APP_PATH" | awk '{print $1}')"
UPDATER_SHA256="$(shasum -a 256 "$HELPER_PATH" | awk '{print $1}')"
POS_SIZE="$(file_size "$APP_PATH")"
UPDATER_SIZE="$(file_size "$HELPER_PATH")"
PUBLISHED_AT="$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
NOTES_ES="${NOTES_ES:-Actualización de POS Local MX $VERSION_NAME. Consulta las notas de la versión antes de instalar.}"
NOTES_KO="${NOTES_KO:-로컬 POS $VERSION_NAME 업데이트입니다. 설치 전에 릴리스 안내를 확인하세요.}"

TEMP_DIR="$(mktemp -d)"
cleanup() {
  rm -f "$TEMP_DIR/latest.json" "$TEMP_DIR/latest.json.sig.bin" "$TEMP_DIR/latest.json.sig"
  rmdir "$TEMP_DIR" 2>/dev/null || true
}
trap cleanup EXIT

jq -n \
  --arg packageName 'com.koreanmarket.localpos' \
  --arg versionName "$VERSION_NAME" \
  --argjson versionCode "$VERSION_CODE" \
  --argjson minimumSupportedVersionCode "$MINIMUM_SUPPORTED_VERSION_CODE" \
  --arg publishedAt "$PUBLISHED_AT" \
  --arg notesEs "$NOTES_ES" \
  --arg notesKo "$NOTES_KO" \
  --arg posDownloadUrl "$POS_DOWNLOAD_URL" \
  --arg updaterDownloadUrl "$HELPER_DOWNLOAD_URL" \
  --arg posSha256 "$POS_SHA256" \
  --argjson posSizeBytes "$POS_SIZE" \
  --arg updaterSha256 "$UPDATER_SHA256" \
  --argjson updaterSizeBytes "$UPDATER_SIZE" \
  '{schemaVersion: 1, packageName: $packageName, versionName: $versionName,
    versionCode: $versionCode, minimumSupportedVersionCode: $minimumSupportedVersionCode,
    publishedAt: $publishedAt, notesEs: $notesEs, notesKo: $notesKo,
    pos: {assetName: "POS-Local-MX.apk", downloadUrl: $posDownloadUrl, sha256: $posSha256, sizeBytes: $posSizeBytes},
    updater: {assetName: "POS-Update-Helper.apk", downloadUrl: $updaterDownloadUrl, sha256: $updaterSha256, sizeBytes: $updaterSizeBytes}}' \
  > "$TEMP_DIR/latest.json"

openssl dgst -sha256 -sign "$PRIVATE_KEY_PATH" -out "$TEMP_DIR/latest.json.sig.bin" "$TEMP_DIR/latest.json"
openssl dgst -sha256 -verify "$PINNED_PUBLIC_KEY" -keyform DER \
  -signature "$TEMP_DIR/latest.json.sig.bin" "$TEMP_DIR/latest.json" >/dev/null
openssl base64 -A -in "$TEMP_DIR/latest.json.sig.bin" -out "$TEMP_DIR/latest.json.sig"
printf '\n' >> "$TEMP_DIR/latest.json.sig"

install -m 0644 "$TEMP_DIR/latest.json" "$CHANNEL_ROOT/docs/latest.json"
install -m 0644 "$TEMP_DIR/latest.json.sig" "$CHANNEL_ROOT/docs/latest.json.sig"
"$SCRIPT_DIR/check-public-tree.sh"

printf 'Signed update manifest written to docs/latest.json and docs/latest.json.sig\n'
