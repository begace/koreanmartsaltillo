# POS Local public update channel

This is the public distribution repository, not the Android source repository.
It contains the GitHub Pages site, signed release metadata, release notes and local verification scripts.
Never commit APKs, Android source, product CSV/Excel, databases, backups or signing secrets here.

## Staged update: 1.1.5 → 1.1.5.1 → 1.1.6

| Stage | POS version / code | Embedded helper | APK host | Signed metadata |
| --- | --- | --- | --- | --- |
| Existing installation | 1.1.5 / 7 | 1.0.0 / 1 | GitHub | `latest.json` |
| Compatibility bridge | 1.1.5.1 / 9 | 1.1.1 / 3 | GitHub | `latest.json` |
| Final release | 1.1.6 / 10 | 1.1.1 / 3 | Google Drive | `latest-drive.json` |

Existing users press the POS update button and install the GitHub bridge. On reopening POS,
the app guides them through installing its embedded helper and then offers the Drive update.
No separate search for a helper APK is needed. Android installation permissions and confirmation
still require user action; this is not silent installation. Keep an off-device backup and install
over the existing app—never uninstall it to update.

The previously published 1.1.6 / code 8 files are retained, not overwritten. Code 10 ensures
that Android accepts the final release after the code 9 bridge.

## Channel contract

- `https://begace.github.io/koreanmartsaltillo/latest.json` and `.json.sig` remain pinned to
  **1.1.5.1 / code 9**, with exact version-specific GitHub APK URLs. Never replace this legacy
  endpoint with the final Drive release: old helpers cannot download from Drive.
- `https://begace.github.io/koreanmartsaltillo/latest-drive.json` and `.json.sig` provide the
  final release to helper 1.1.1. All final APK download URLs are canonical HTTPS Drive URLs.
- Signatures use the existing pinned RSA key and SHA-256 over the exact JSON bytes.
  APK hash, size, package, signer, version code and version name are checked before installation.
- Anonymous Drive downloads use `drive.usercontent.google.com/download` with `id`,
  `export=download` and optionally fixed `confirm=t`. HTML/login/error pages are rejected.
- Publish a manifest and its detached signature together. A transient mismatch fails closed.
  Do not change bytes behind a published Drive file ID; create new IDs for new builds.

Main compatible download:
[POS 1.1.5.1 bridge](https://github.com/begace/koreanmartsaltillo/releases/download/v1.1.5.1/POS-Local-MX.apk)

Final distribution folder:
[POS 1.1.6 / code 10 on Google Drive](https://drive.google.com/drive/folders/1jyvxuWEefI8_qI4mhivRSnKh-GzqXeyF)

## Catalog and privacy

The bridge contains no store catalog. Only the final 1.1.6 APK includes the explicitly approved
2,557-product snapshot (names, prices, costs and numeric stock). Anyone with the link can extract
those assets. Original Excel files, store databases, sales, backups and credentials are not uploaded.
POS creates a verified internal backup before applying the snapshot once; sales, payments and
returns are preserved, numeric stock is replaced, and unknown stock remains unchanged.

POS still has no INTERNET permission. The separate helper downloads updates only; neither app
contains Drive upload credentials or a store-data upload function. Physical-device installation,
reopening and data-preservation tests have not been performed; they require a store-device check.

## Preparing metadata locally

APKs and the existing private signing key must remain outside this repository. Do not create a
replacement signing key: deployed helpers trust the existing pinned public key.

```bash
# Bridge: GitHub URLs are derived from the exact version tag. No catalog flag.
./scripts/generate-update-manifest.sh \
  --manifest-name latest \
  --version-name 1.1.5.1 --version-code 9 \
  --minimum-supported-version-code 7 --helper-version-code 3 \
  --app ../releases/v1.1.5.1/POS-Local-MX.apk \
  --helper ../releases/v1.1.5.1/POS-Update-Helper.apk

# Final: verify anonymous downloads before signing these uploaded file IDs.
./scripts/generate-update-manifest.sh \
  --manifest-name latest-drive \
  --version-name 1.1.6 --version-code 10 \
  --minimum-supported-version-code 7 --helper-version-code 3 \
  --app ../releases/v1.1.6/code-10/POS-Local-MX.apk \
  --helper ../releases/v1.1.6/code-10/POS-Update-Helper.apk \
  --pos-download-url 'https://drive.usercontent.google.com/download?export=download&id=1uIz10wlkmeZNhfyTDQyqiA43W_4c37R-&confirm=t' \
  --helper-download-url 'https://drive.usercontent.google.com/download?export=download&id=1OlasLvGkAKa-2rpA2ImsQ5k6aP_abPvy&confirm=t' \
  --allow-bundled-catalog

bash ./scripts/test-release-policy.sh
./scripts/check-public-tree.sh
```

Only `latest` and `latest-drive` are allowed manifest names. The generator rejects the wrong
host/channel, bridge catalog inclusion, version conflicts, unauthorized catalog assets and secrets.
Only the two reviewed catalog assets are accepted with `--allow-bundled-catalog`.

## Publication

GitHub Pages uses `main:/docs`. Upload verified bridge APKs as assets of GitHub Release
`v1.1.5.1`, not as Git files. Upload final APKs to the approved Drive folder. Verify anonymous
downloads and their signatures/checksums before publishing metadata. Then publish both signed
channel pairs, the website and release notes; confirm the served bytes and signatures afterward.

Run `scripts/check-public-tree.sh` before every commit and review the file list. Never bypass
the `.gitignore` allow-list to add private material. The scripts do not publish or push anything.
