# POS Local public update channel

This directory is a **public-distribution staging repository**, not the Android source repository.
It contains only the GitHub Pages site, public release notes, a signed update-manifest template,
and local release-preparation scripts.

Never copy the Android source tree, the store catalog, an APK, a backup, or a signing key into
this directory. In particular, do not publish `initial_products.csv`, `precio.xlsx`,
`release-signing/`, `keystore.properties`, a JKS, or a POS database backup.

## Public repository layout

```text
README.md
.gitignore
docs/                         # GitHub Pages source: main:/docs
  .nojekyll
  index.html
  styles.css
  privacy.html
  latest.json                 # generated locally; safe to publish
  latest.json.sig             # Base64 RSA/SHA-256 signature
release-notes/v1.1.5.md
scripts/
templates/latest.json.template
```

Release binaries are GitHub Release assets only and are never committed to Git:

- `POS-Local-MX.apk`
- `POS-Update-Helper.apk`
- `SHA256SUMS.txt`

Keeping the asset names stable makes this permanent download URL possible:

```text
https://github.com/begace/koreanmartsaltillo/releases/latest/download/POS-Local-MX.apk
```

The website may use that `latest` link for people. The signed machine-readable manifest uses the
version-pinned `/releases/download/vX.Y.Z/` URL so publishing a later release cannot silently change
the bytes addressed by an older signed manifest.

## One-time update-signing key

The update manifest uses a dedicated RSA key. This is **not** the Android APK signing JKS.
Create and retain it outside this public staging directory. The default script path is
`../release-signing/update-manifest-private.pem`.

```bash
mkdir -p ../release-signing
openssl genpkey -algorithm RSA -aes-256-cbc \
  -pkeyopt rsa_keygen_bits:3072 \
  -out ../release-signing/update-manifest-private.pem
chmod 600 ../release-signing/update-manifest-private.pem
openssl pkey \
  -in ../release-signing/update-manifest-private.pem \
  -pubout \
  -out ../release-signing/update-manifest-public.pem
```

Back up both the Android JKS and this RSA private key offline. Embed only the RSA **public** key
in the updater. Never place either private key in this repository or in a GitHub Release.

## Prepare v1.1.5 without publishing

The public APK must be a generic build without the store-specific `assets/initial_products.csv`.
The preparation script refuses an APK containing that asset.

```bash
RELEASE_DIR="$(mktemp -d)"

./scripts/prepare-release.sh \
  --version v1.1.5 \
  --version-code 7 \
  --helper-version-code 1 \
  --app /absolute/path/to/generic-pos-release.apk \
  --helper /absolute/path/to/update-helper-release.apk \
  --output "$RELEASE_DIR"

./scripts/generate-update-manifest.sh \
  --version-name 1.1.5 \
  --version-code 7 \
  --minimum-supported-version-code 6 \
  --helper-version-code 1 \
  --app "$RELEASE_DIR/POS-Local-MX.apk" \
  --helper "$RELEASE_DIR/POS-Update-Helper.apk" \
  --private-key ../release-signing/update-manifest-private.pem

./scripts/check-public-tree.sh
```

`generate-update-manifest.sh` writes only `docs/latest.json` and `docs/latest.json.sig`. It reads
the private key in place and never copies it. The JSON signature is Base64-encoded RSA PKCS#1 v1.5
with SHA-256 (`SHA256withRSA`) over the exact bytes of `docs/latest.json`.

Before creating a release, verify the three files in `RELEASE_DIR` and the APK signer certificate.
Create the GitHub Release as a draft first, download its assets to a different temporary directory,
verify them again, and only then publish it.

Example after `gh auth login --web`:

```bash
gh release create v1.1.5 \
  --repo begace/koreanmartsaltillo \
  --target main \
  --title "POS Local MX v1.1.5" \
  --notes-file release-notes/v1.1.5.md \
  --draft \
  "$RELEASE_DIR/POS-Local-MX.apk#Android POS" \
  "$RELEASE_DIR/POS-Update-Helper.apk#Signed update helper" \
  "$RELEASE_DIR/SHA256SUMS.txt#SHA-256 checksums"
```

The scripts do not run `git init`, call GitHub, create a release, or push anything.

## GitHub Pages

After a deliberate review, initialize this directory as its own repository and add files by
allow-list rather than with a broad source-tree command:

```bash
git init -b main
git remote add origin https://github.com/begace/koreanmartsaltillo.git
git add -- .gitignore README.md docs release-notes scripts templates
git diff --cached --name-only
git diff --cached
git commit -m "Add POS download and update channel"
git push -u origin main
```

Then select **Settings → Pages → Deploy from a branch → main → /docs**. The expected site URL is:

```text
https://begace.github.io/koreanmartsaltillo/
```

Run `scripts/check-public-tree.sh` before every commit. Do not use `git add -f` to bypass the
allow-list.
