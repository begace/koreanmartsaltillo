#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CHANNEL_ROOT="$(cd "$SCRIPT_DIR/.." && pwd -P)"
PROJECT_ROOT="$(cd "$CHANNEL_ROOT/../.." && pwd -P)"
EXPECTED_SIGNER_SHA256="5dca2229ef7332cdeb1a10b78e8fc95252e799f57b44de923dd75e7bad73e7f4"
EXPECTED_UPDATE_PUBLIC_KEY_BASE64="MIIBojANBgkqhkiG9w0BAQEFAAOCAY8AMIIBigKCAYEAte2TCy74/rT+IfVz1ZM2BYsP9MfSQbgH11+IpRv0UNZ5UKb2dbXl3qhbp9uKqwqaqlW9DzyLbho2ecN2OUrocm7vmZ+aBlIsjf8j6oMIsyFSWRM2lG9OLTF6MmURkTEf6T2PxESd6IVPTHPkxCSbHeayO1foS/TmmA87W7oSbwEFXmXpsT/ymrCVDnPFVpcFKAvUYiR6m6QZ+UaW9le8xgCWZpEncGiWOIRHyfmYCKPeWZhHWtVAfkqcvteOv1vKuWkfLjzH92o7B5Ddhwg543xQmkSWOqDnm2nojQIBrq1zKrCM0J2PTRITl5fw5Bz/0gKIyL6D1uBggzlkPGl6+nTosUV5LEy8h6AbaFFtTUSIKDpBLHtmVmVacdO8rdAHUYsh+WjZ566tKtWQU0A9k/2bdQftjb0LfokAJ0wyQKqxp3oiQPPvm5C2XuhmUEPbJyhGm6UXYzR5Ib0rgQsOs2iG8oyR4wwMH/zVQmkPoIJDfyW52oOAotfdk4UvHCZRAgMBAAE="

usage() {
  cat <<'EOF'
Usage:
  verify-release-apks.sh --version-name 1.1.5 --version-code 7 \
    --helper-version-code 1 --app /path/POS-Local-MX.apk \
    --helper /path/POS-Update-Helper.apk

Requires Android SDK build-tools (aapt and apksigner). JAVA_HOME must point to
a working JDK for apksigner.
EOF
}

VERSION_NAME=""
VERSION_CODE=""
HELPER_VERSION_CODE=""
APP_PATH=""
HELPER_PATH=""

while (($#)); do
  case "$1" in
    --version-name) VERSION_NAME="${2:-}"; shift 2 ;;
    --version-code) VERSION_CODE="${2:-}"; shift 2 ;;
    --helper-version-code) HELPER_VERSION_CODE="${2:-}"; shift 2 ;;
    --app) APP_PATH="${2:-}"; shift 2 ;;
    --helper) HELPER_PATH="${2:-}"; shift 2 ;;
    --help|-h) usage; exit 0 ;;
    *) printf 'ERROR: unknown argument: %s\n' "$1" >&2; usage >&2; exit 2 ;;
  esac
done

[[ "$VERSION_NAME" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { printf 'ERROR: invalid --version-name.\n' >&2; exit 2; }
[[ "$VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: invalid --version-code.\n' >&2; exit 2; }
[[ "$HELPER_VERSION_CODE" =~ ^[1-9][0-9]*$ ]] || { printf 'ERROR: invalid --helper-version-code.\n' >&2; exit 2; }
[[ -f "$APP_PATH" ]] || { printf 'ERROR: POS APK not found.\n' >&2; exit 2; }
[[ -f "$HELPER_PATH" ]] || { printf 'ERROR: updater APK not found.\n' >&2; exit 2; }

find_android_tool() {
  local tool="$1"
  local found=""
  if command -v "$tool" >/dev/null 2>&1; then
    command -v "$tool"
    return
  fi

  local sdk_dir="${ANDROID_SDK_ROOT:-${ANDROID_HOME:-}}"
  if [[ -z "$sdk_dir" && -f "$PROJECT_ROOT/local.properties" ]]; then
    sdk_dir="$(sed -n 's/^sdk\.dir=//p' "$PROJECT_ROOT/local.properties" | head -n 1)"
  fi
  if [[ -n "$sdk_dir" && -d "$sdk_dir/build-tools" ]]; then
    found="$(find "$sdk_dir/build-tools" -mindepth 2 -maxdepth 2 -type f -name "$tool" -print | sort | tail -n 1)"
  fi
  if [[ -z "$found" && -n "$sdk_dir" && -d "$sdk_dir/cmdline-tools" ]]; then
    found="$(find "$sdk_dir/cmdline-tools" -type f -name "$tool" -print | sort | tail -n 1)"
  fi
  [[ -n "$found" ]] || { printf 'ERROR: Android build-tool not found: %s\n' "$tool" >&2; exit 1; }
  printf '%s\n' "$found"
}

AAPT="$(find_android_tool aapt)"
APKSIGNER="$(find_android_tool apksigner)"
APKANALYZER="$(find_android_tool apkanalyzer)"
command -v xmllint >/dev/null || { printf 'ERROR: xmllint is required.\n' >&2; exit 1; }

verify_identity() {
  local apk="$1"
  local expected_package="$2"
  local expected_version_code="$3"
  local expected_version_name="$4"
  local label="$5"
  local badging package_name version_code version_name min_sdk cert_output signer_count signer_digest

  unzip -tqq "$apk"
  badging="$("$AAPT" dump badging "$apk")"
  package_name="$(printf '%s\n' "$badging" | sed -n "s/^package: name='\([^']*\)'.*/\1/p" | head -n 1)"
  version_code="$(printf '%s\n' "$badging" | sed -n "s/^package: name='[^']*' versionCode='\([^']*\)'.*/\1/p" | head -n 1)"
  version_name="$(printf '%s\n' "$badging" | sed -n "s/^package: name='[^']*' versionCode='[^']*' versionName='\([^']*\)'.*/\1/p" | head -n 1)"
  min_sdk="$(printf '%s\n' "$badging" | sed -n "s/^sdkVersion:'\([^']*\)'.*/\1/p" | head -n 1)"

  [[ "$package_name" == "$expected_package" ]] || { printf 'ERROR: %s package mismatch: %s\n' "$label" "$package_name" >&2; exit 1; }
  [[ "$version_code" == "$expected_version_code" ]] || { printf 'ERROR: %s versionCode mismatch: %s\n' "$label" "$version_code" >&2; exit 1; }
  if [[ -n "$expected_version_name" && "$version_name" != "$expected_version_name" ]]; then
    printf 'ERROR: %s versionName mismatch: %s\n' "$label" "$version_name" >&2
    exit 1
  fi
  [[ "$min_sdk" == "26" ]] || { printf 'ERROR: %s minSdk must be 26, found %s.\n' "$label" "$min_sdk" >&2; exit 1; }

  cert_output="$("$APKSIGNER" verify --verbose --print-certs "$apk")"
  signer_count="$(printf '%s\n' "$cert_output" | sed -n 's/^Number of signers: //p' | head -n 1)"
  signer_digest="$(printf '%s\n' "$cert_output" | sed -n 's/^Signer #1 certificate SHA-256 digest: //p' | head -n 1 | tr '[:upper:]' '[:lower:]')"
  [[ "$signer_count" == "1" ]] || { printf 'ERROR: %s must have exactly one signer.\n' "$label" >&2; exit 1; }
  [[ "$signer_digest" == "$EXPECTED_SIGNER_SHA256" ]] || { printf 'ERROR: %s signing certificate mismatch.\n' "$label" >&2; exit 1; }
  printf '%s\n' "$cert_output" | grep -Fq 'Verified using v2 scheme (APK Signature Scheme v2): true' || {
    printf 'ERROR: %s is not verified with APK Signature Scheme v2.\n' "$label" >&2
    exit 1
  }

  printf '%s\n' "$badging"
}

POS_BADGING="$(verify_identity "$APP_PATH" 'com.koreanmarket.localpos' "$VERSION_CODE" "$VERSION_NAME" 'POS APK')"
HELPER_BADGING="$(verify_identity "$HELPER_PATH" 'com.koreanmarket.localpos.updater' "$HELPER_VERSION_CODE" '' 'updater APK')"

permission_names() {
  printf '%s\n' "$1" | sed -n "s/^uses-permission: name='\([^']*\)'.*/\1/p"
}

for required in android.permission.CAMERA android.permission.REQUEST_INSTALL_PACKAGES com.koreanmarket.localpos.permission.UPDATE_COMPANION; do
  if ! printf '%s\n' "$POS_BADGING" | grep -Fq "uses-permission: name='$required'"; then
    printf 'ERROR: POS APK is missing %s.\n' "$required" >&2
    exit 1
  fi
done

while IFS= read -r permission; do
  [[ -z "$permission" ]] && continue
  case "$permission" in
    android.permission.CAMERA|\
    android.permission.REQUEST_INSTALL_PACKAGES|\
    com.koreanmarket.localpos.permission.UPDATE_COMPANION|\
    com.koreanmarket.localpos.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) ;;
    *) printf 'ERROR: POS APK has an unexpected permission: %s\n' "$permission" >&2; exit 1 ;;
  esac
done < <(permission_names "$POS_BADGING")

for required in android.permission.INTERNET android.permission.ACCESS_NETWORK_STATE android.permission.REQUEST_INSTALL_PACKAGES android.permission.POST_NOTIFICATIONS com.koreanmarket.localpos.permission.UPDATE_COMPANION; do
  if ! printf '%s\n' "$HELPER_BADGING" | grep -Fq "uses-permission: name='$required'"; then
    printf 'ERROR: updater APK is missing %s.\n' "$required" >&2
    exit 1
  fi
done

while IFS= read -r permission; do
  [[ -z "$permission" ]] && continue
  case "$permission" in
    android.permission.INTERNET|\
    android.permission.ACCESS_NETWORK_STATE|\
    android.permission.REQUEST_INSTALL_PACKAGES|\
    android.permission.POST_NOTIFICATIONS|\
    android.permission.WAKE_LOCK|\
    android.permission.RECEIVE_BOOT_COMPLETED|\
    android.permission.FOREGROUND_SERVICE|\
    android.permission.FOREGROUND_SERVICE_DATA_SYNC|\
    com.koreanmarket.localpos.permission.UPDATE_COMPANION|\
    com.koreanmarket.localpos.updater.DYNAMIC_RECEIVER_NOT_EXPORTED_PERMISSION) ;;
    *) printf 'ERROR: updater APK has an unexpected permission: %s\n' "$permission" >&2; exit 1 ;;
  esac
done < <(permission_names "$HELPER_BADGING")

APP_ENTRIES="$(unzip -Z1 "$APP_PATH")"
if grep -Eiq '(^|/)(initial_products|precio)([^/]*)$|\.(csv|xlsx|xls|posbackup|sqlite|db)$' <<< "$APP_ENTRIES"; then
  printf 'ERROR: POS APK contains private catalog or database material.\n' >&2
  exit 1
fi

if ! grep -Fxq 'assets/POS-Update-Helper.apk' <<< "$APP_ENTRIES"; then
  printf 'ERROR: POS APK does not contain assets/POS-Update-Helper.apk.\n' >&2
  exit 1
fi

TEMP_HELPER="$(mktemp)"
POS_MANIFEST="$(mktemp)"
HELPER_MANIFEST="$(mktemp)"
HELPER_DEX="$(mktemp)"
HELPER_STRINGS="$(mktemp)"
cleanup() { rm -f "$TEMP_HELPER" "$POS_MANIFEST" "$HELPER_MANIFEST" "$HELPER_DEX" "$HELPER_STRINGS"; }
trap cleanup EXIT
unzip -p "$APP_PATH" assets/POS-Update-Helper.apk > "$TEMP_HELPER"
if ! cmp -s "$TEMP_HELPER" "$HELPER_PATH"; then
  printf 'ERROR: helper embedded in POS does not match the release helper APK.\n' >&2
  exit 1
fi

unzip -p "$HELPER_PATH" 'classes*.dex' > "$HELPER_DEX"
strings -a "$HELPER_DEX" > "$HELPER_STRINGS"
if ! grep -Fxq "$EXPECTED_UPDATE_PUBLIC_KEY_BASE64" "$HELPER_STRINGS"; then
  printf 'ERROR: updater APK does not contain the pinned update public key.\n' >&2
  exit 1
fi

"$APKANALYZER" manifest print "$APP_PATH" > "$POS_MANIFEST"
"$APKANALYZER" manifest print "$HELPER_PATH" > "$HELPER_MANIFEST"

xpath_value() {
  xmllint --xpath "string($2)" "$1"
}

[[ "$(xpath_value "$POS_MANIFEST" "//*[local-name()='permission'][@*[local-name()='name']='com.koreanmarket.localpos.permission.UPDATE_COMPANION']/@*[local-name()='protectionLevel']")" =~ ^(signature|0x2)$ ]] || {
  printf 'ERROR: POS signature permission is missing or not signature-protected.\n' >&2
  exit 1
}
[[ "$(xpath_value "$POS_MANIFEST" "//*[local-name()='activity'][@*[local-name()='name']='com.koreanmarket.localpos.platform.update.UpdateHelperInstallActivity']/@*[local-name()='exported']")" == "false" ]] || {
  printf 'ERROR: POS helper install callback Activity must be non-exported.\n' >&2
  exit 1
}
[[ "$(xpath_value "$HELPER_MANIFEST" "//*[local-name()='receiver'][@*[local-name()='name']='com.koreanmarket.localpos.updater.DailyCheckReceiver']/@*[local-name()='exported']")" == "true" ]] || {
  printf 'ERROR: updater daily receiver must be exported for the signed POS.\n' >&2
  exit 1
}
[[ "$(xpath_value "$HELPER_MANIFEST" "//*[local-name()='receiver'][@*[local-name()='name']='com.koreanmarket.localpos.updater.DailyCheckReceiver']/@*[local-name()='permission']")" == "com.koreanmarket.localpos.permission.UPDATE_COMPANION" ]] || {
  printf 'ERROR: updater daily receiver lacks the signature permission.\n' >&2
  exit 1
}
[[ "$(xpath_value "$HELPER_MANIFEST" "//*[local-name()='activity'][@*[local-name()='name']='com.koreanmarket.localpos.updater.InstallConfirmationActivity']/@*[local-name()='exported']")" == "false" ]] || {
  printf 'ERROR: updater install callback Activity must be non-exported.\n' >&2
  exit 1
}
[[ "$(xpath_value "$HELPER_MANIFEST" "//*[local-name()='activity'][@*[local-name()='name']='com.koreanmarket.localpos.updater.PosUpdateActivity']/@*[local-name()='exported']")" == "true" ]] || {
  printf 'ERROR: updater launcher Activity must be exported.\n' >&2
  exit 1
}

printf 'Verified release APK identities, signatures, permissions, and embedded helper.\n'
