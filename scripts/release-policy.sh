#!/usr/bin/env bash
# Pure validation shared by release tools and their offline regression tests.

release_version_name_valid() {
  [[ "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]
}

release_manifest_name_valid() {
  [[ "$1" == latest || "$1" == latest-drive ]]
}

release_drive_url_valid() {
  local url="$1"
  local endpoint='https://(drive\.google\.com/uc|drive\.usercontent\.google\.com/download)'
  local file_id='[A-Za-z0-9_-]{10,200}'
  if [[ "$url" =~ ^${endpoint}\?id=${file_id}\&export=download$ ]] ||
     [[ "$url" =~ ^${endpoint}\?export=download\&id=${file_id}$ ]]; then
    return 0
  fi
  # Only Google's public binary-download endpoint may use this fixed flag.
  # No arbitrary HTML form destination, token, host, or query key is trusted.
  local confirmed_endpoint='https://drive\.usercontent\.google\.com/download'
  local query
  for query in \
    "id=$file_id&export=download&confirm=t" \
    "id=$file_id&confirm=t&export=download" \
    "export=download&id=$file_id&confirm=t" \
    "export=download&confirm=t&id=$file_id" \
    "confirm=t&id=$file_id&export=download" \
    "confirm=t&export=download&id=$file_id"; do
    [[ "$url" =~ ^${confirmed_endpoint}\?${query}$ ]] && return 0
  done
  return 1
}

release_route_valid() {
  local manifest="$1" version="$2" code="$3" helper_code="$4" catalog="$5" pos_url="$6" helper_url="$7"
  release_manifest_name_valid "$manifest" || { printf 'ERROR: --manifest-name must be latest or latest-drive.\n' >&2; return 1; }
  release_version_name_valid "$version" || { printf 'ERROR: invalid release version name.\n' >&2; return 1; }
  [[ "$code" =~ ^[1-9][0-9]*$ && "$helper_code" =~ ^[1-9][0-9]*$ ]] || {
    printf 'ERROR: version codes must be positive integers.\n' >&2; return 1;
  }
  [[ "$catalog" == true || "$catalog" == false ]] || { printf 'ERROR: invalid catalog approval flag.\n' >&2; return 1; }
  if [[ "$manifest" == latest ]]; then
    [[ "$catalog" == false ]] || { printf 'ERROR: legacy GitHub channel must not contain a bundled catalog.\n' >&2; return 1; }
    # This endpoint is permanently the bridge for old GitHub-only downloaders.
    (( code <= 7 || code == 9 )) || { printf 'ERROR: final releases belong in latest-drive, not the legacy latest channel.\n' >&2; return 1; }
    if (( code == 9 )); then
      [[ "$version" == 1.1.5.1 && "$helper_code" == 3 ]] || {
        printf 'ERROR: bridge code 9 must be POS 1.1.5.1 with helper code 3.\n' >&2; return 1;
      }
    elif [[ "$version" == 1.1.5.1 ]]; then
      printf 'ERROR: POS 1.1.5.1 must use bridge code 9.\n' >&2; return 1
    fi
    local base="https://github.com/begace/koreanmartsaltillo/releases/download/v$version"
    [[ "$pos_url" == "$base/POS-Local-MX.apk" && "$helper_url" == "$base/POS-Update-Helper.apk" ]] || {
      printf 'ERROR: legacy latest requires exact version-specific GitHub asset URLs for both APKs.\n' >&2; return 1;
    }
  else
    (( code >= 10 && helper_code >= 3 )) || {
      printf 'ERROR: latest-drive requires POS code >=10 and helper code >=3.\n' >&2; return 1;
    }
    if (( code == 10 )); then
      [[ "$version" == 1.1.6 && "$helper_code" == 3 && "$catalog" == true ]] || {
        printf 'ERROR: code 10 must be POS 1.1.6, helper code 3, with the approved catalog.\n' >&2; return 1;
      }
    fi
    release_drive_url_valid "$pos_url" && release_drive_url_valid "$helper_url" || {
      printf 'ERROR: latest-drive requires canonical HTTPS Drive download URLs for both APKs.\n' >&2; return 1;
    }
  fi
}
