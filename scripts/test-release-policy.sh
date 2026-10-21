#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=release-policy.sh
source "$SCRIPT_DIR/release-policy.sh"

passed=0
expect_accept() {
  local label="$1"; shift
  if ! "$@" >/dev/null 2>&1; then printf 'FAIL (rejected): %s\n' "$label" >&2; exit 1; fi
  passed=$((passed + 1))
}
expect_reject() {
  local label="$1"; shift
  if "$@" >/dev/null 2>&1; then printf 'FAIL (accepted): %s\n' "$label" >&2; exit 1; fi
  passed=$((passed + 1))
}

expect_accept 'ordinary version' release_version_name_valid 1.1.6
expect_accept 'four-part bridge version' release_version_name_valid 1.1.5.1
for version in 1 1.1 1.1.5.1.1 v1.1.5 1.1.5-beta '1.1.5/../x' '1.1.5 ' ''; do
  expect_reject "invalid version: $version" release_version_name_valid "$version"
done
expect_accept legacy-channel release_manifest_name_valid latest
expect_accept drive-channel release_manifest_name_valid latest-drive
for channel in latest.json '../latest' /latest latest-evil 'latest-drive/../../file' ''; do
  expect_reject "invalid channel: $channel" release_manifest_name_valid "$channel"
done

bridge_base=https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.5.1
bridge_pos="$bridge_base/POS-Local-MX.apk"
bridge_helper="$bridge_base/POS-Update-Helper.apk"
drive_pos='https://drive.usercontent.google.com/download?id=Abcdefghijk0123456789&export=download&confirm=t'
drive_helper='https://drive.google.com/uc?export=download&id=Zyxwvutsrqp0123456789'
expect_accept bridge-route release_route_valid latest 1.1.5.1 9 3 false "$bridge_pos" "$bridge_helper"
expect_accept drive-route release_route_valid latest-drive 1.1.6 10 3 true "$drive_pos" "$drive_helper"
expect_accept historic-route release_route_valid latest 1.1.5 7 1 false \
  'https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.5/POS-Local-MX.apk' \
  'https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.5/POS-Update-Helper.apk'
expect_reject 'bridge cannot contain catalog' release_route_valid latest 1.1.5.1 9 3 true "$bridge_pos" "$bridge_helper"
expect_reject 'bridge cannot download from Drive' release_route_valid latest 1.1.5.1 9 3 false "$drive_pos" "$drive_helper"
expect_reject 'bridge cannot use old helper' release_route_valid latest 1.1.5.1 9 2 false "$bridge_pos" "$bridge_helper"
expect_reject 'code9 must have bridge name' release_route_valid latest 1.1.6 9 3 false "$bridge_pos" "$bridge_helper"
expect_reject 'bridge name must have code9' release_route_valid latest 1.1.5.1 7 3 false "$bridge_pos" "$bridge_helper"
expect_reject 'bridge cannot point at latest redirect' release_route_valid latest 1.1.5.1 9 3 false \
  'https://github.com/begace/koreanmartsaltillo/releases/latest/download/POS-Local-MX.apk' "$bridge_helper"
expect_reject 'bridge cannot point at another tag' release_route_valid latest 1.1.5.1 9 3 false \
  'https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.5/POS-Local-MX.apk' "$bridge_helper"
expect_reject 'code10 cannot replace legacy endpoint' release_route_valid latest 1.1.6 10 3 true "$drive_pos" "$drive_helper"
expect_reject 'old final code8 cannot replace legacy endpoint' release_route_valid latest 1.1.6 8 2 false \
  'https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.6/POS-Local-MX.apk' \
  'https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.6/POS-Update-Helper.apk'
expect_reject 'Drive cannot use GitHub APK URLs' release_route_valid latest-drive 1.1.6 10 3 true "$bridge_pos" "$bridge_helper"
expect_reject 'Drive requires new helper' release_route_valid latest-drive 1.1.6 10 2 true "$drive_pos" "$drive_helper"
expect_reject 'Drive requires greater code than bridge' release_route_valid latest-drive 1.1.6 8 3 true "$drive_pos" "$drive_helper"
expect_reject 'code10 requires catalog approval' release_route_valid latest-drive 1.1.6 10 3 false "$drive_pos" "$drive_helper"
expect_reject 'code10 requires final name' release_route_valid latest-drive 1.1.5.1 10 3 true "$drive_pos" "$drive_helper"

expect_accept 'unconfirmed usercontent URL' release_drive_url_valid 'https://drive.usercontent.google.com/download?export=download&id=Abcdefghijk0123456789'
expect_accept 'confirm-first usercontent URL' release_drive_url_valid 'https://drive.usercontent.google.com/download?confirm=t&export=download&id=Abcdefghijk0123456789'
for url in \
  'http://drive.google.com/uc?id=Abcdefghijk0123456789&export=download' \
  'https://drive.google.com.evil.test/uc?id=Abcdefghijk0123456789&export=download' \
  'https://drive.google.com/uc?id=Abcdefghijk0123456789&export=download&confirm=t' \
  'https://drive.google.com/uc?id=Abcdefghijk0123456789&export=download&id=OtherFile012345' \
  'https://drive.google.com/uc?id=short&export=download' \
  'https://drive.google.com/file/d/Abcdefghijk0123456789/view' \
  'https://drive.usercontent.google.com/download?id=Abcdefghijk0123456789&export=download&confirm=arbitrary' \
  'https://drive.usercontent.google.com/download?id=Abcdefghijk0123456789&export=download&confirm=t&token=secret' \
  'https://drive.usercontent.google.com/download?id=Abcdefghijk0123456789&export=download#fragment'; do
  expect_reject "unsafe Drive URL: $url" release_drive_url_valid "$url"
done

for script in "$SCRIPT_DIR"/*.sh "$SCRIPT_DIR/../../verify-current-release.sh"; do
  bash -n "$script"
done
printf 'Release policy checks passed: %d assertions, shell syntax valid.\n' "$passed"
